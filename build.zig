const std = @import("std");
const zcc = @import("compile_commands");
// Import the local cppkit-zig build helper directly so edits in the workspace
// are used immediately instead of relying on Zig's package cache.
const cpp = @import("./cppkit-zig/build.zig");

var INCLUDE_PATH: []const u8 = undefined;
var CDB_TARGETS: std.ArrayListUnmanaged(*std.Build.Step.Compile) = undefined;

pub fn build(b: *std.Build) void {
    var env_map = std.process.getEnvMap(b.allocator) catch @panic("Failed to get environment variables");
    defer env_map.deinit();
    INCLUDE_PATH = env_map.get("FLAKE_INCLUDES") orelse @panic("missing FLAKE_INCLUDES");
    CDB_TARGETS = std.ArrayListUnmanaged(*std.Build.Step.Compile).initCapacity(b.allocator, 32) catch {
        @panic("OOM");
    };

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // START: app target
    const app_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libcpp = true,
        .single_threaded = true,
    });

    const app_mod_srcs = std.mem.concat(b.allocator, []const u8, &.{
        IMPL_SOURCES,
        &.{"./src/Main.cpp"},
    }) catch {
        @panic("OOM");
    };
    app_mod.addCSourceFiles(.{
        .files = app_mod_srcs,
        .language = .cpp,
        .flags = &.{ "-std=c++20", "-fcoroutines" },
    });

    linkupModule(app_mod);

    const app_exe = b.addExecutable(.{ .name = "excel2csv", .root_module = app_mod });
    cpp.addCompileCommands(app_exe);
    CDB_TARGETS.appendAssumeCapacity(app_exe);

    const app_exe_run = b.addRunArtifact(app_exe);
    if (b.args) |args| {
        app_exe_run.addArgs(args);
    }

    const run_step = b.step("run", "Run the Main application");
    run_step.dependOn(&app_exe_run.step);
    // END: app target
    // START: test target
    const test_mod = b.createModule(.{
        .target = target,
        .optimize = optimize,
        .link_libcpp = true,
    });
    const test_mod_srcs = std.mem.concat(b.allocator, []const u8, &.{
        IMPL_SOURCES,
        &.{
            "./test/SimpleTest.cpp",
            "./test/UtilsTest.cpp",
            "./test/StringTableReaderTest.cpp",
            "./test/ExcelRow2CsvTest.cpp",
            "./test/ExcelReaderTest.cpp",
            "./test/TestMain.cpp",
        },
    }) catch {
        @panic("OOM");
    };
    test_mod.addCSourceFiles(.{
        .files = test_mod_srcs,
        .language = .cpp,
        .flags = &.{ "-std=c++20", "-fcoroutines" },
    });
    linkupModule(test_mod);
    const test_exe = b.addExecutable(.{ .name = "excel2csv_tests", .root_module = test_mod });
    CDB_TARGETS.appendAssumeCapacity(test_exe);
    cpp.addCompileCommands(test_exe);

    const test_exe_run = b.addRunArtifact(test_exe);
    if (b.args) |args| {
        test_exe_run.addArgs(args);
    }

    const run_test_step = b.step("run-test", "Run the Tests");
    run_test_step.dependOn(&test_exe_run.step);
    // END: test target

    _ = zcc.createStep(b, "cdb", CDB_TARGETS.toOwnedSlice(b.allocator) catch @panic("OOM"));

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

const IMPL_SOURCES: []const []const u8 = &.{
    "./src/Impl/Utils.cpp",
    "./src/Impl/StringTableReader.cpp",
    "./src/Impl/ExcelRow2Csv.cpp",
    "./src/Impl/ExcelReader.cpp",
};
