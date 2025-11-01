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
        std.log.info("SUCCESS: Gathered cpp file {s}", .{entry.file});
    }
}

fn gatherCompileCommandEntries(
    alloc: std.mem.Allocator,
    step: *std.Build.Step,
    compile_command_entries: *std.ArrayListUnmanaged(CompileCommandsEntry),
) !void {
    for (step.dependencies.items) |dependency| {
        if (dependency.cast(std.Build.Step.Compile)) |compile_step| {
            std.log.info("Dependency name={s}", .{dependency.name});
            for (compile_step.root_module.link_objects.items) |link_object| {
                switch (link_object) {
                    .c_source_files => |csf| {
                        for (csf.files) |f| {
                            std.log.info(".c_source_files branch hit: {s}", .{f});
                        }
                    },
                    .c_source_file => |csf| {
                        std.log.info("Looking at {s}", .{csf.file.getDisplayName()});
                        switch (csf) {
                            else => {
                                std.log.info("Looking at {s}", .{csf.file.getDisplayName()});
                            },
                        }
                    },
                    else => {},
                }
            }
        }
        try gatherCompileCommandEntries(alloc, dependency, compile_command_entries);
    }
}
