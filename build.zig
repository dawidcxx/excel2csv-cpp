const std = @import("std");
// Import the local cppkit-zig build helper directly so edits in the workspace
// are used immediately instead of relying on Zig's package cache.
const cpp = @import("./cppkit-zig/build.zig");

var INCLUDE_PATH: []const u8 = undefined;

pub fn build(b: *std.Build) void {
    var env_map = std.process.getEnvMap(b.allocator) catch @panic("Failed to get environment variables");
    defer env_map.deinit();
    INCLUDE_PATH = env_map.get("FLAKE_INCLUDES") orelse @panic("missing FLAKE_INCLUDES");

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const base_srcs = cpp.querySources(b.allocator, "./src/Impl", .{
        .recursive = true,
        .extensions = cpp.Exts.JUST_CPP,
    });

    const app_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libcpp = true,
        .single_threaded = true,
    });

    var app_mod_srcs = base_srcs.with("./src", .{
        .extensions = cpp.Exts.JUST_CPP,
    });

    app_mod.addCSourceFiles(.{
        .files = app_mod_srcs.get(),
        .language = .cpp,
        .flags = &.{
            "-std=c++20",
        },
    });
    linkupModule(app_mod);

    const app_exe = b.addExecutable(.{
        .name = "excel2csv",
        .root_module = app_mod,
    });
    cpp.addCompileCommands(app_exe);

    const app_exe_run = b.addRunArtifact(app_exe);
    if (b.args) |args| {
        app_exe_run.addArgs(args);
    }

    const run_step = b.step("run", "Run the Main application");
    run_step.dependOn(&app_exe_run.step);

    const test_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libcpp = true,
    });

    const test_mod_srcs = base_srcs.with("./test", .{
        .extensions = cpp.Exts.JUST_CPP,
    });
    test_mod.addCSourceFiles(.{
        .files = test_mod_srcs.get(),
        .language = .cpp,
        .flags = &.{"-std=c++20"},
    });
    linkupModule(test_mod);
    const test_exe = b.addExecutable(.{
        .name = "excel2csv_tests",
        .root_module = test_mod,
    });
    cpp.addCompileCommands(test_exe);

    const test_exe_run = b.addRunArtifact(test_exe);
    if (b.args) |args| {
        test_exe_run.addArgs(args);
    }

    const run_test_step = b.step("run-test", "Run the Tests");
    run_test_step.dependOn(&test_exe_run.step);

    const output_test_exe = b.addInstallArtifact(test_exe, .{});
    const output_app_exe = b.addInstallArtifact(app_exe, .{});

    const compile_step = b.step("compile", "Output executables of the build process");
    compile_step.dependOn(&output_test_exe.step);
    compile_step.dependOn(&output_app_exe.step);

    cpp.addCompileCommandsStep(b);
}

fn linkupModule(mod: *std.Build.Module) void {
    var split = std.mem.splitScalar(u8, INCLUDE_PATH, ':');
    while (split.next()) |item| {
        mod.addIncludePath(.{ .cwd_relative = item });
    }
    mod.addIncludePath(.{ .cwd_relative = "./src/Include" });
    mod.linkSystemLibrary("minizip", .{});
    mod.linkSystemLibrary("expat", .{});
    mod.linkSystemLibrary("jemalloc", .{});
}
