const std = @import("std");
const builtin = @import("builtin");

const xilo_version = std.SemanticVersion.parse("0.5.0") catch unreachable;
const min_zig_string = "0.12.0";

// NOTE: This code came from
// https://github.com/zigtools/zls/blob/master/build.zig.
const Build = blk: {
    const current_zig = builtin.zig_version;
    const min_zig = std.SemanticVersion.parse(min_zig_string) catch unreachable;
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

    const zlap_module = b.dependency("zlap", .{}).module("zlap");

    const exe = b.addExecutable(
        .{
            .name = "xilo",
            .root_source_file = .{ .path = "src/main.zig" },
            .target = target,
            .optimize = optimize,
            .version = xilo_version,
            .strip = switch (optimize) {
                .Debug, .ReleaseSafe => false,
                else => true,
            },
        },
    );
    exe.root_module.addImport("zlap", zlap_module);
    exe.linkLibCpp();
    exe.addCSourceFile(.{ .file = .{ .path = "./src/fileinfo.cc" }, .flags = &.{"-std=c++17"} });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
