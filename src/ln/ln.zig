const std = @import("std");
const Io = std.Io;

pub fn ln(io: Io, source: []const u8, dest: []const u8) !void {
    const source_stat = try Io.Dir.statFile(.cwd(), io, source, .{ .follow_symlinks = false });
    const source_is_dir = source_stat.kind == .directory;

    try Io.Dir.symLink(.cwd(), io, source, dest, .{ .is_directory = source_is_dir });
}
