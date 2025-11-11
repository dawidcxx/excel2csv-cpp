const std = @import("std");

// 100 build targets out be enough for everyone :)
var marked_targets: [100]?*std.Build.Step.Compile = @splat(null);

pub fn mark(target: *std.Build.Step.Compile) void {
    var i: usize = 0;
    while (i < marked_targets.len) {
        if (marked_targets[i] == null) {
            marked_targets[i] = target;
            return;
        }
        i += 1;
    }
    @panic("markedTargets is full, cannot mark target");
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

const CompileCommandsEntry = struct {
    file: []const u8,
    flags: []const []const u8,
    linkObjects: []const []const u8,
    includes: []const []const u8,
};

fn makeCompileCommandsStep(step: *std.Build.Step, make_options: std.Build.Step.MakeOptions) anyerror!void {
    _ = make_options;
    const b = step.owner;
    const alloc = b.allocator;
    const root_levels = b.top_level_steps.values();

    var compile_commands_db = CompileCommandsDb.init(alloc);
    for (root_levels) |root_level| {
        const root_level_step = &root_level.step;
        gatherCompileCommandEntries(alloc, root_level_step, &compile_commands_db) catch {
            @panic("Error while gathering compile command entries");
        };
    }

    compile_commands_db.forEach(printCompileCommand);
}

fn gatherCompileCommandEntries(
    alloc: std.mem.Allocator,
    step: *std.Build.Step,
    compile_commands_db: *CompileCommandsDb,
) !void {
    for (step.dependencies.items) |dependency| {
        if (dependency.cast(std.Build.Step.Compile)) |compile_step| {
            var headers: std.ArrayListUnmanaged([]const u8) = try .initCapacity(alloc, 16);
            defer headers.deinit(alloc);
            for (compile_step.root_module.include_dirs.items) |d| {
                switch (d.path) {
                    .cwd_relative => |path| {
                        try headers.append(alloc, path);
                    },
                    else => {},
                }
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
                        const file_path = getFilePath(csf.file) orelse break;
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
        try gatherCompileCommandEntries(alloc, dependency, compile_commands_db);
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

fn cloneStringSlice(gpa: std.mem.Allocator, container: []const []const u8) error{OutOfMemory}![]const []const u8 {
    const result = try gpa.alloc([]const u8, container.len);
    for (container, 0..) |str, i| {
        result[i] = try gpa.dupe(u8, str);
    }
    return result;
}

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
};

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

    fn count(self: *Self) u32 {
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

test "StringSet basic operations" {
    std.testing.log_level = .debug;
    const alloc = std.testing.allocator;
    var string_set1: StringSet = .init();
    defer string_set1.deinit(alloc);

    var string_set2: StringSet = .init();
    defer string_set2.deinit(alloc);

    // Test adding strings
    try string_set1.add(alloc, "test1");
    try string_set1.add(alloc, "test2");
    try string_set1.add(alloc, "test4");
    try string_set1.add(alloc, "test5");
    try string_set1.add(alloc, "test6");
    try string_set1.add(alloc, "test7");
    try string_set1.add(alloc, "test8");
    try string_set1.add(alloc, "test9");
    try string_set1.add(alloc, "test10");

    // Test contains
    try std.testing.expect(string_set1.has("test1"));
    try std.testing.expect(string_set1.has("test2"));
    try std.testing.expect(!string_set1.has("test3"));

    // Test adding duplicate
    try string_set1.add(alloc, "test1");
    try std.testing.expect(string_set1.has("test1"));

    try string_set2.add(alloc, "foo");
    try string_set1.add(alloc, "bar");
    try std.testing.expect(!string_set1.has("foo"));
    try std.testing.expect(!string_set2.has("bar"));
}
