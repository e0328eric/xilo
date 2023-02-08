const std = @import("std");
const fmt = std.fmt;

pub const Color = enum(u8) {
    Black = 30,
    Red = 31,
    Green = 32,
    Yellow = 33,
    Blue = 34,
    Magenta = 35,
    Cyan = 36,
    White = 37,
    BrightBlac = 90,
    BrightRed = 91,
    BrightGreen = 92,
    BrightYellow = 93,
    BrightBlue = 94,
    BrightMagenta = 95,
    BrightCyan = 96,
    BrightWhite = 97,
};

pub const Attribute = enum(u8) {
    Reset = 0,
    Bold = 1,
    Faint = 2,
    Italic = 3,
    Underline = 4,
};

pub fn makeAnsi(comptime color: ?Color, comptime attr: ?Attribute) []const u8 {
    comptime var buf = [_]u8{0} ** 10;

    const attr_buf = if (attr) |a| blk: {
        break :blk fmt.bufPrint(&buf, "\x1b[{d}m", .{@enumToInt(a)}) catch unreachable;
    } else "";
    const color_buf = if (color) |c| blk: {
        break :blk fmt.bufPrint(&buf, "\x1b[{d}m", .{@enumToInt(c)}) catch unreachable;
    } else "";

    return attr_buf ++ color_buf;
}

pub const reset = makeAnsi(null, .Reset);
pub const @"error" = makeAnsi(.Red, .Bold);
pub const warn = makeAnsi(.Magenta, .Bold);
pub const note = makeAnsi(.Cyan, .Bold);
