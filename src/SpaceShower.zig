const std = @import("std");

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const Self = @This();

const KILOBYTE: u64 = 1 << 10;
const MEGABYTE: u64 = 1 << 20;
const GIGABYTE: u64 = 1 << 30;
const TERABYTE: u64 = 1 << 40;
const PETABYTE: u64 = 1 << 50;
const EXABYTE: u64 = 1 << 60;

// fields for SpaceShower
allocator: Allocator,
// END of fields

pub fn init(allocator: Allocator) Self {
    return .{
        .allocator = allocator,
    };
}

pub fn parseBytes(self: Self, bytes: u64) !ArrayList(u8) {
    var output = try ArrayList(u8).initCapacity(self.allocator, 50);
    errdefer output.deinit();

    var writer = output.writer();

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
        try writer.print("{}B", .{byte});
    } else if (bytes < MEGABYTE) {
        try writer.print("{}K {}B", .{ kilobyte, byte });
    } else if (bytes < GIGABYTE) {
        try writer.print("{}M {}K {}B", .{ megabyte, kilobyte, byte });
    } else if (bytes < TERABYTE) {
        try writer.print("{}G {}M {}K {}B", .{ gigabyte, megabyte, kilobyte, byte });
    } else {
        try writer.print("{}E {}P {}T {}G {}M {}K {}B", .{
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
