const std = @import("std");

// 100 build targets out be enough for everyone :)
var compile_commands_targets: [100]?*std.Build.Step.Compile = @splat(null);

pub fn addCompileCommands(target: *std.Build.Step.Compile) void {
    var i: usize = 0;
    while (i < compile_commands_targets.len) {
        if (compile_commands_targets[i] == null) {
            compile_commands_targets[i] = target;
            return;
        }
        i += 1;
    }
    @panic("compile_commands_targets is full, cannot mark target");
}

pub fn addCompileCommandsStep(b: *std.Build) void {
    const create_compile_commands_step = b.allocator.create(std.Build.Step) catch {
        @panic("OOM");
    };
    create_compile_commands_step.* = std.Build.Step.init(.{
        .id = .custom,
        .name = "compile-commands/step",
        .owner = b,
        .makeFn = makeCompileCommandsStep,
    });

    const top_level_step = b.step("compile-commands", "Build compile_commands.json file from marked targets");
    top_level_step.dependOn(create_compile_commands_step);
}

pub fn build(b: *std.Build) void {
    _ = b;
}

fn makeCompileCommandsStep(step: *std.Build.Step, make_options: std.Build.Step.MakeOptions) anyerror!void {
    _ = make_options;
    const b = step.owner;
    const alloc = b.allocator;
    const root_levels = b.top_level_steps.values();

    var compile_commands_db = CompileCommandsDb.init(alloc);
    for (root_levels) |root_level| {
        const root_level_step = &root_level.step;
        gatherCompileCommandEntries(
            step,
            root_level_step,
            &compile_commands_db,
        ) catch {
            @panic("Error while gathering compile command entries");
        };
    }

    var compile_commands_it = compile_commands_db.compile_commands_by_file_name.valueIterator();
    var jsonWriter = std.Io.Writer.Allocating.init(alloc);
    defer jsonWriter.deinit();

    var strigify = std.json.Stringify{
        .writer = &jsonWriter.writer,
        .options = .{ .emit_null_optional_fields = true, .whitespace = .indent_2 },
    };
    try strigify.beginArray();
    while (compile_commands_it.next()) |compile_command_ptr| {
        const cc = compile_command_ptr.*;
        const jsonEntry = try cc.toJson(alloc, b.build_root.path.?);
        try strigify.write(jsonEntry);
    }
    try strigify.endArray();

    const jsonString: []const u8 = try jsonWriter.toOwnedSlice();
    defer alloc.free(jsonString);

    const compile_commands_file = try b.build_root.handle.createFile("compile_commands.json", .{});
    try compile_commands_file.writeAll(jsonString);
}

fn gatherCompileCommandEntries(
    owning_step: *std.Build.Step,
    step: *std.Build.Step,
    compile_commands_db: *CompileCommandsDb,
) !void {
    const b = owning_step.owner;
    const alloc = b.allocator;

    for (step.dependencies.items) |dependency| {
        if (dependency.cast(std.Build.Step.Compile)) |compile_step| {
            if (!isCompileCommandsMarked(compile_step)) continue;

            var headers: std.ArrayListUnmanaged([]const u8) = try .initCapacity(alloc, 16);
            defer headers.deinit(alloc);
            for (compile_step.root_module.include_dirs.items) |d| {
                const path = getIncludeDirPath(d) orelse continue;
                try headers.append(alloc, path);
            }

            var libraries: std.ArrayListUnmanaged([]const u8) = try .initCapacity(alloc, 16);
            defer libraries.deinit(alloc);
            for (compile_step.root_module.link_objects.items) |link_object| {
                switch (link_object) {
                    .system_lib => |sl| {
                        try libraries.append(alloc, sl.name);
                    },
                    else => {},
                }
            }

            for (compile_step.root_module.link_objects.items) |link_object| {
                switch (link_object) {
                    .c_source_file => |csf| {
                        const file_path = getFilePath(csf.file) orelse continue;
                        try compile_commands_db.update(
                            file_path,
                            headers.items,
                            libraries.items,
                            csf.flags,
                        );
                    },
                    .c_source_files => |csfs| {
                        for (csfs.files) |file_path| {
                            try compile_commands_db.update(
                                file_path,
                                headers.items,
                                libraries.items,
                                csfs.flags,
                            );
                        }
                    },
                    else => {},
                }
            }
        }
        try gatherCompileCommandEntries(owning_step, dependency, compile_commands_db);
    }
}

fn getFilePath(lazyPath: std.Build.LazyPath) ?[]const u8 {
    switch (lazyPath) {
        .cwd_relative => |cwd| {
            return cwd;
        },
        else => return null,
    }
}

fn getIncludeDirPath(include_dir: std.Build.Module.IncludeDir) ?[]const u8 {
    switch (include_dir.path) {
        .cwd_relative => |cwd| {
            return cwd;
        },
        else => return null,
    }
}

fn isCompileCommandsMarked(compile: *std.Build.Step.Compile) bool {
    for (compile_commands_targets) |t| {
        if (t == compile) return true;
    }
    return false;
}

const CompileCommandsDb = struct {
    const Self = @This();

    arena: std.heap.ArenaAllocator,
    compile_commands_by_file_name: std.StringHashMapUnmanaged(*CompileCommand),

    pub fn init(gpa: std.mem.Allocator) Self {
        const arena = std.heap.ArenaAllocator.init(gpa);
        return .{
            .arena = arena,
            .compile_commands_by_file_name = std.StringHashMapUnmanaged(*CompileCommand){},
        };
    }

    pub fn forEach(self: *Self, callback: fn (cc: CompileCommand) void) void {
        var it = self.compile_commands_by_file_name.valueIterator();
        while (it.next()) |cc| {
            callback(cc.*.*);
        }
    }

    pub fn update(
        self: *Self,
        file_name: []const u8,
        headers: []const []const u8,
        libraries: []const []const u8,
        flags: []const []const u8,
    ) !void {
        const alloc = self.arena.allocator();
        const cc_gop = try self.compile_commands_by_file_name.getOrPut(alloc, file_name);
        var compile_command = blk: {
            if (cc_gop.found_existing) {
                break :blk cc_gop.value_ptr.*;
            } else {
                const owned_file_name = try alloc.dupe(u8, file_name);
                const cc = try alloc.create(CompileCommand);
                cc.* = .init(owned_file_name);
                cc_gop.value_ptr.* = cc;
                break :blk cc;
            }
        };
        for (headers) |header| {
            if (!compile_command.headers.has(header)) {
                const owned_header = try alloc.dupe(u8, header);
                try compile_command.headers.add(alloc, owned_header);
            }
        }
        for (libraries) |library| {
            if (!compile_command.libraries.has(library)) {
                const owned_library = try alloc.dupe(u8, library);
                try compile_command.libraries.add(alloc, owned_library);
            }
        }
        for (flags) |flag| {
            if (!compile_command.libraries.has(flag)) {
                const owned_flag = try alloc.dupe(u8, flag);
                try compile_command.flags.add(alloc, owned_flag);
            }
        }
    }

    pub fn deinit(self: *Self) void {
        self.arena.deinit();
    }
};

const StringSet = struct {
    const Self = @This();
    map: std.StringHashMapUnmanaged(void),

    pub fn init() StringSet {
        const backing_map = std.StringHashMapUnmanaged(void){};
        return .{ .map = backing_map };
    }

    fn add(self: *Self, alloc: std.mem.Allocator, key: []const u8) !void {
        try self.map.put(alloc, key, {});
    }

    fn has(self: *Self, key: []const u8) bool {
        return self.map.contains(key);
    }

    fn count(self: Self) u32 {
        return self.map.count();
    }

    fn deinit(self: *Self, alloc: std.mem.Allocator) void {
        self.map.deinit(alloc);
    }
};

fn printCompileCommand(cc: CompileCommand) void {
    std.log.info("File: {s}", .{cc.file_name});
    std.log.info("  Headers: {d} items", .{cc.headers.map.count()});
    var header_it = cc.headers.map.keyIterator();
    while (header_it.next()) |header| {
        std.log.info("    - {s}", .{header.*});
    }
    std.log.info("  Libraries: {d} items", .{cc.libraries.map.count()});
    var lib_it = cc.libraries.map.keyIterator();
    while (lib_it.next()) |library| {
        std.log.info("    - {s}", .{library.*});
    }
    std.log.info("  Flags: {d} items", .{cc.flags.map.count()});
    var flag_it = cc.flags.map.keyIterator();
    while (flag_it.next()) |flag| {
        std.log.info("    - {s}", .{flag.*});
    }
}

const CompileCommandJson = struct {
    arguments: []const []const u8,
    directory: []const u8,
    file: []const u8,
    output: []const u8,
    pub fn deinit(self: CompileCommandJson, alloc: std.mem.Allocator) void {
        for (self.arguments) |arg| alloc.free(arg);
        alloc.free(self.arguments);
        alloc.free(self.directory);
        alloc.free(self.file);
        alloc.free(self.output);
    }
};

const CompileCommand = struct {
    file_name: []const u8,
    flags: StringSet,
    headers: StringSet,
    libraries: StringSet,

    pub fn init(file_name: []const u8) CompileCommand {
        return .{
            .file_name = file_name,
            .flags = .init(),
            .headers = .init(),
            .libraries = .init(),
        };
    }

    pub fn toJson(self: CompileCommand, alloc: std.mem.Allocator, project_root: []const u8) !CompileCommandJson {
        const input_file = try std.fs.path.resolve(alloc, &.{ project_root, self.file_name });
        errdefer alloc.free(input_file);

        const as_object_file = try std.fmt.allocPrint(alloc, "{s}.o", .{self.file_name});
        defer alloc.free(as_object_file);

        const output_file = try std.fs.path.resolve(alloc, &.{ "/tmp", as_object_file });

        var arguments_builder = try std.ArrayListUnmanaged([]const u8).initCapacity(
            alloc,
            4 + self.flags.count() + self.headers.count() + self.libraries.count(),
        );
        errdefer {
            for (arguments_builder.items) |i| alloc.free(i);
            arguments_builder.deinit(alloc);
        }

        arguments_builder.appendAssumeCapacity(try alloc.dupe(u8, "clang"));
        arguments_builder.appendAssumeCapacity(try alloc.dupe(u8, input_file));
        arguments_builder.appendAssumeCapacity(try alloc.dupe(u8, "-o"));
        arguments_builder.appendAssumeCapacity(try alloc.dupe(u8, output_file));

        var flagsIt = self.flags.map.keyIterator();
        while (flagsIt.next()) |flag| {
            arguments_builder.appendAssumeCapacity(try alloc.dupe(u8, flag.*));
        }

        var libsIt = self.libraries.map.keyIterator();
        while (libsIt.next()) |lib| {
            const libArg = try std.fmt.allocPrint(alloc, "-l{s}", .{lib.*});
            arguments_builder.appendAssumeCapacity(libArg);
        }

        var headersIt = self.headers.map.keyIterator();
        while (headersIt.next()) |header| {
            const headerArg = try std.fmt.allocPrint(alloc, "-I{s}", .{header.*});
            arguments_builder.appendAssumeCapacity(try alloc.dupe(u8, headerArg));
        }

        return .{
            .file = input_file,
            .arguments = try arguments_builder.toOwnedSlice(alloc),
            .directory = try alloc.dupe(u8, project_root),
            .output = output_file,
        };
    }
};

test "CompileCommandsDb checks" {
    std.testing.log_level = .debug;
    const alloc = std.testing.allocator;
    var db = CompileCommandsDb.init(alloc);
    try db.update("random.cpp", &.{"/opt/foo/include"}, &.{"/opt/foo/lib"}, &.{});
    try db.update("bar.cpp", &.{ "/opt/bar/include", "/opt/foo/include" }, &.{ "/opt/bar/lib", "/opt/foo/lib" }, &.{});
    try db.update("bar.cpp", &.{ "/opt/quaz/include", "/opt/quaz/include" }, &.{ "/opt/quaz/lib", "/opt/quaz/lib" }, &.{});
    db.forEach(printCompileCommand);
    db.deinit();
}
