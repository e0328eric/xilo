const std = @import("std");
const builtin = @import("builtin");
const io = std.io;
const mem = std.mem;

const Allocator = mem.Allocator;
const StaticStringMap = std.StaticStringMap;

const yesValue = StaticStringMap(void).initComptime(.{
    .{ "y", void },
    .{ "Y", void },
    .{ "yes", void },
    .{ "Yes", void },
    .{ "YES", void },
});

pub fn handleYesNo(
    allocator: Allocator,
    comptime fmt_str: []const u8,
    args: anytype,
) !bool {
    const stdout = io.getStdOut().writer();
    try stdout.print(fmt_str, args);

    const stdin = io.getStdIn().reader();
    const data = try stdin.readUntilDelimiterAlloc(allocator, '\n', 4096);
    defer allocator.free(data);

    // Since windows uses CRLF for EOL, we should trim \r character.
    return if (builtin.os.tag == .windows)
        yesValue.has(mem.trimRight(u8, data, "\r"))
    else
        yesValue.has(data);
}
