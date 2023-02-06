const std = @import("std");
const builtin = @import("builtin");
const mem = std.mem;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

// fields for Remover
trashbin_path: ArrayList(u8),
recursive: bool,
force: bool,
permanent: bool,
file_contents: []const []const u8,
// END of fields

const Self = @This();

pub fn init(
    allocator: Allocator,
    recursive: bool,
    force: bool,
    permanent: bool,
    file_contents: []const []const u8,
) !Self {
    const trashbin_path = try getTrashbinPath(allocator);
    errdefer trashbin_path.deinit();

    std.fs.makeDirAbsolute(trashbin_path.items) catch |err| {
        switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        }
    };

    return .{
        .trashbin_path = trashbin_path,
        .recursive = recursive,
        .force = force,
        .permanent = permanent,
        .file_contents = file_contents,
    };
}

pub fn deinit(self: Self) void {
    self.trashbin_path.deinit();
}

fn getTrashbinPath(allocator: Allocator) !ArrayList(u8) {
    var output = try ArrayList(u8).initCapacity(allocator, 150);
    errdefer output.deinit();

    switch (builtin.os.tag) {
        .linux => {
            try output.appendSlice(std.os.getenv("HOME").?);
            try output.appendSlice("/.cache/xilo");
        },
        .macos => {
            try output.appendSlice(std.os.getenv("HOME").?);
            try output.appendSlice("/.Trash/xilo");
        },
        .windows => @compileError("wiindows not supported yet"),
        else => @compileError("only linux, macos and windows(not yet) are supported"),
    }

    return output;
}
