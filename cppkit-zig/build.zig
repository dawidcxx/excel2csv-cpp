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

    var compile_command_entries: std.ArrayListUnmanaged(CompileCommandsEntry) = try .initCapacity(alloc, 256);
    for (root_levels) |root_level| {
        const root_level_step = &root_level.step;
        gatherCompileCommandEntries(alloc, root_level_step, &compile_command_entries) catch {
            @panic("Error while gathering compile command entries");
        };
    }

    for (compile_command_entries.items) |entry| {
        const flags = try std.mem.join(alloc, ",", entry.flags);
        defer alloc.free(flags);
        const libs = try std.mem.join(alloc, ",", entry.linkObjects);
        defer alloc.free(libs);
        const headers = try std.mem.join(alloc, ",", entry.includes);
        defer alloc.free(headers);
        std.log.info("SUCCESS: Gathered cpp file '{s}' with flags '{s}' with headers '{s}' ", .{ entry.file, flags, headers });
    }
}

fn gatherCompileCommandEntries(
    alloc: std.mem.Allocator,
    step: *std.Build.Step,
    compile_command_entries: *std.ArrayListUnmanaged(CompileCommandsEntry),
) !void {
    for (step.dependencies.items) |dependency| {
        if (dependency.cast(std.Build.Step.Compile)) |compile_step| {
            var headers: std.ArrayListUnmanaged([]const u8) = try .initCapacity(alloc, compile_step.root_module.include_dirs.items.len);
            defer headers.deinit(alloc);
            defer for (headers.items) |h| alloc.free(h);

            for (compile_step.root_module.include_dirs.items) |d| {
                switch (d.path) {
                    .cwd_relative => |path| {
                        headers.appendAssumeCapacity(try alloc.dupe(u8, path));
                    },
                    else => {},
                }
            }

            var libraries: std.ArrayListUnmanaged([]const u8) = try .initCapacity(alloc, compile_step.root_module.link_objects.items.len);
            defer libraries.deinit(alloc);
            defer for (libraries.items) |l| alloc.free(l);

            var source_files_and_flags: std.ArrayListUnmanaged([2][]const []const u8) = try .initCapacity(alloc, compile_step.root_module.link_objects.items.len * 2);
            // defer source_files_and_flags.deinit(alloc);
            // defer for (source_files_and_flags.items) |item| {
            //     for (item[0]) |file| alloc.free(file);
            //     for (item[1]) |flag| alloc.free(flag);
            // };

            for (compile_step.root_module.link_objects.items) |link_object| {
                on_item: {
                    switch (link_object) {
                        .system_lib => |sl| {
                            libraries.appendAssumeCapacity(sl.name);
                        },
                        .c_source_file => |cs| {
                            const file = blk: {
                                switch (cs.file) {
                                    .cwd_relative => |path| {
                                        break :blk try alloc.dupe(u8, path);
                                    },
                                    else => {
                                        break :on_item;
                                    },
                                }
                            };
                            const file_container = try alloc.alloc([]const u8, 1);
                            file_container[0] = file;
                            const flags = try cloneStringSlice(alloc, cs.flags);
                            try source_files_and_flags.append(alloc, .{ file_container, flags });
                        },
                        .c_source_files => |csf| {
                            const flags = try cloneStringSlice(alloc, csf.flags);
                            const files = try cloneStringSlice(alloc, csf.files);
                            try source_files_and_flags.append(alloc, .{ files, flags });
                        },
                        else => {},
                    }
                }
            }

            for (source_files_and_flags.items) |source_file_and_flags| {
                const files = source_file_and_flags[0];
                const flags = source_file_and_flags[1];
                for (files) |file| {
                    const compile_commands_entry: CompileCommandsEntry = .{
                        .file = file,
                        .flags = flags,
                        .includes = try headers.toOwnedSlice(alloc),
                        .linkObjects = try libraries.toOwnedSlice(alloc),
                    };
                    try compile_command_entries.append(alloc, compile_commands_entry);
                }
            }
        }
        try gatherCompileCommandEntries(alloc, dependency, compile_command_entries);
    }
}

fn cloneStringSlice(gpa: std.mem.Allocator, container: []const []const u8) error{OutOfMemory}![]const []const u8 {
    const result = try gpa.alloc([]const u8, container.len);
    for (container, 0..) |str, i| {
        result[i] = try gpa.dupe(u8, str);
    }
    return result;
}
