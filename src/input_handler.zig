const std = @import("std");
const builtin = @import("builtin");
const mem = std.mem;

const Allocator = mem.Allocator;
const Io = std.Io;
const StaticStringMap = std.StaticStringMap;

const yesValue = StaticStringMap(void).initComptime(.{
    .{ "y", void },
    .{ "Y", void },
    .{ "yes", void },
    .{ "Yes", void },
    .{ "YES", void },
});

pub fn handleYesNo(
    io: Io,
    comptime fmt_str: []const u8,
    args: anytype,
) !bool {
    var writer_buf: [1024]u8 = undefined;
    var stdout = Io.File.stdout().writer(io, &writer_buf);
    try stdout.interface.print(fmt_str, args);
    try stdout.end();

    var reader_buf: [4096]u8 = undefined;
    var stdin = Io.File.stdin().reader(io, &reader_buf);
    const data = try stdin.interface.takeDelimiterExclusive('\n');

    // Since windows uses CRLF for EOL, we should trim \r character.
    return if (builtin.os.tag == .windows)
        yesValue.has(mem.trimRight(u8, data, "\r"))
    else
        yesValue.has(data);
}
