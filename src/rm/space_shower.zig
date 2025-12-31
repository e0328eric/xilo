const std = @import("std");
const powi = std.math.powi;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const KILOBYTE: u64 = powi(u64, 10, 3) catch unreachable;
const MEGABYTE: u64 = powi(u64, 10, 6) catch unreachable;
const GIGABYTE: u64 = powi(u64, 10, 9) catch unreachable;
const TERABYTE: u64 = powi(u64, 10, 12) catch unreachable;
const PETABYTE: u64 = powi(u64, 10, 15) catch unreachable;
const EXABYTE: u64 = powi(u64, 10, 18) catch unreachable;

pub fn parseBytes(allocator: Allocator, bytes: u64) !ArrayList(u8) {
    var output = try ArrayList(u8).initCapacity(allocator, 50);
    errdefer output.deinit(allocator);

    const exabyte = @divTrunc(bytes, EXABYTE);
    const petabyte = @divTrunc(@rem(bytes, EXABYTE), PETABYTE);
    const terabyte = @divTrunc(@rem(bytes, PETABYTE), TERABYTE);
    const gigabyte = @divTrunc(@rem(bytes, TERABYTE), GIGABYTE);
    const megabyte = @divTrunc(@rem(bytes, GIGABYTE), MEGABYTE);
    const kilobyte = @divTrunc(@rem(bytes, MEGABYTE), KILOBYTE);
    const byte = @rem(bytes, KILOBYTE);

    if (bytes >= EXABYTE) {
        @panic("Are you really using a normal computer?");
    }

    if (bytes < KILOBYTE) {
        try output.print(allocator, "{}B", .{byte});
    } else if (bytes < MEGABYTE) {
        try output.print(allocator, "{}K {}B", .{ kilobyte, byte });
    } else if (bytes < GIGABYTE) {
        try output.print(allocator, "{}M {}K {}B", .{ megabyte, kilobyte, byte });
    } else if (bytes < TERABYTE) {
        try output.print(allocator, "{}G {}M {}K {}B", .{
            gigabyte,
            megabyte,
            kilobyte,
            byte,
        });
    } else {
        try output.print(allocator, "{}E {}P {}T {}G {}M {}K {}B", .{
            exabyte,
            petabyte,
            terabyte,
            gigabyte,
            megabyte,
            kilobyte,
            byte,
        });
    }

    return output;
}
