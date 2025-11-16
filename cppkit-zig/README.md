# CppKit-Zig

Set of Zig-Build utilities to quickly create C++ Application builds.

# Examples

- Query for sources

```zig
const my_cpp_sources = cpp.querySources(b.allocator, "./src", .{
    .recursive = false,
    .extensions = cpp.Exts.JUST_CPP,
});
```

- Remove a source from a sourceset

```zig
my_cpp_sources.filterOutByGlob("*_generated.cpp");
```

- Add ClangD based autocomplete for a target

```zig
   const my_app_exe = b.addExecutable(.{
        .name = "my_exe",
        .root_module = my_exe_module,
    });
    cpp.addCompileCommands(my_app_exe);

    // <... some other targets>
    
    cpp.addCompileCommandsStep(b); // available under zig build compile-commands

```