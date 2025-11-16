const std = @import("std");
const cc = @import("./compile_commands.zig");
const file_queries = @import("file_queries.zig");

pub fn build(b: *std.Build) void {
    _ = b;
}

// querying for sources
pub const Ext = file_queries.Ext;
pub const Exts = struct {
    pub const JUST_C = file_queries.JUST_C;
    pub const JUST_CC = file_queries.JUST_CC;
    pub const JUST_CPP = file_queries.JUST_CPP;
    pub const JUST_H = file_queries.JUST_H;
};

pub const querySources = file_queries.querySources;
pub const SourceSet = file_queries.SourceSet;

// compile commands stuff
pub const addCompileCommands = cc.addCompileCommands;
pub const addCompileCommandsStep = cc.addCompileCommandsStep;
