const std = @import("std");
const builtin = @import("builtin");

const XILO_VERSION_STR = @import("build.zig.zon").version;
const XILO_VERSION = std.SemanticVersion.parse(XILO_VERSION_STR) catch unreachable;
const MIN_ZIG_STRING = @import("build.zig.zon").minimum_zig_version;
const PROGRAM_NAME = @tagName(@import("build.zig.zon").name);

// NOTE: This code came from
// https://github.com/zigtools/zls/blob/master/build.zig.
const Build = blk: {
    const current_zig = builtin.zig_version;
    const min_zig = std.SemanticVersion.parse(MIN_ZIG_STRING) catch unreachable;
    if (current_zig.order(min_zig) == .lt) {
        @compileError(std.fmt.comptimePrint(
            "Your Zig version v{} does not meet the minimum build requirement of v{}",
            .{ current_zig, min_zig },
        ));
    }
    break :blk std.Build;
};

pub fn build(b: *Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const custom_trashbin_path = b.option(
        []const u8,
        "trashbin_path",
        "Specify the custom trashbin_path",
    );
    const exe_options = b.addOptions();
    exe_options.addOption(?[]const u8, "custom_trashbin_path", custom_trashbin_path);

    const zlap_module = b.dependency("zlap", .{}).module("zlap");

    const win_zig_trans_c = b.addTranslateC(.{
        .root_source_file = b.path("./src/winzig.h"),
        .target = target,
        .optimize = optimize,
    });
    const win_zig = b.createModule(.{
        .root_source_file = win_zig_trans_c.getOutput(),
        .target = target,
        .optimize = optimize,
    });

    const exe_mod = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .strip = switch (optimize) {
            .Debug, .ReleaseSafe => false,
            else => true,
        },
        .link_libcpp = true,
        .imports = &.{
            .{ .name = "zlap", .module = zlap_module },
            .{ .name = "windows", .module = win_zig },
        },
    });
    const cpp_flags = [_][]const u8{"-std=c++17"} ++ if (optimize == .Debug)
        [_][]const u8{"-DZIG_DEBUG_MODE"}
    else
        [_][]const u8{""};
    exe_mod.addOptions("xilo_build", exe_options);
    exe_mod.addCSourceFile(.{
        .file = b.path("./src/fileinfo.cc"),
        .flags = &cpp_flags,
    });

    const exe = b.addExecutable(
        .{
            .name = PROGRAM_NAME,
            .root_module = exe_mod,
            .version = XILO_VERSION,
        },
    );
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
