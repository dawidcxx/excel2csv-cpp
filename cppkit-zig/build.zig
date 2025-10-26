const std = @import("std");

// 100 build targets out be enough for everyone :)
const marked_targets: [100]*std.Build.Step.Compile = @splat(null);

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
    @panic("cppkit-zig is not meant to be build");
}

const CompileCommandsEntry = struct {
    file: []const u8,
    std_lib: []const u8,
    flags: []const []const u8,
    linkObjects: []const []const u8,
    includes: []const []const u8,
};

fn makeCompileCommandsStep(step: *std.Build.Step, make_options: std.Build.Step.MakeOptions) anyerror!void {
    _ = make_options;
    const b = step.owner;
    const alloc = b.allocator;
    var root_level_steps: std.ArrayListUnmanaged(*std.Build.Step) = .initCapacity(alloc, 64);
    resolveRootLevelSteps(step, &root_level_steps);
}

fn resolveRootLevelSteps(step: *std.Build.Step, root_levels: *std.ArrayListUnmanaged(*std.Build.Step)) void {
    for (step.dependants.items) |dep| {
        if (dep.id == .top_level) {
            root_levels.appendAssumeCapacity(dep);
        }
    }
}
