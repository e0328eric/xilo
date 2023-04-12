const std = @import("std");
const builtin = @import("builtin");
const ansi = @import("./ansi.zig");
const mem = std.mem;
const fs = std.fs;
const io = std.io;
const math = std.math;
const base64 = std.base64;
const fmt = std.fmt;
const time = std.time;

const isAbsolute = fs.path.isAbsolute;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const ComptimeStringMap = std.ComptimeStringMap;

const yesValue = ComptimeStringMap(void, .{
    .{ "y", void },
    .{ "Y", void },
    .{ "yes", void },
    .{ "Yes", void },
    .{ "YES", void },
});

const XiloError = error{
    TryToRemoveDirectoryWithoutRecursiveFlag,
};

// fields for Remover
allocator: Allocator,
trashbin_path: ArrayList(u8),
trashbin_dir: fs.Dir,
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
        .allocator = allocator,
        .trashbin_path = trashbin_path,
        .trashbin_dir = try fs.openDirAbsolute(trashbin_path.items, .{}),
        .recursive = recursive,
        .force = force,
        .permanent = permanent,
        .file_contents = file_contents,
    };
}

pub fn deinit(self: *Self) void {
    self.trashbin_dir.close();
}

pub fn run(self: Self) !void {
    if (self.permanent) {
        return self.deletePermanently();
    }

    return self.delete();
}

fn delete(self: Self) !void {
    for (self.file_contents) |filename| {
        if (!self.force) {
            const msg_fmt = ansi.warn ++ "Warn: " ++ ansi.reset ++ "Are you sure to remove `{s}`? (y/N): ";
            std.debug.print(msg_fmt, .{filename});

            const stdin = io.getStdIn().reader();
            const data = try stdin.readUntilDelimiterAlloc(self.allocator, '\n', 4096);

            if (!yesValue.has(data)) return;
        }

        // TODO: This cannot distinguish the symlink
        const is_dir = (try fs.cwd().statFile(filename)).kind == .Directory;

        if (is_dir and !self.recursive) return error.TryToRemoveDirectoryWithoutRecursiveFlag;

        var mangled_name: ArrayList(u8) = undefined;
        if (isAbsolute(filename)) {
            mangled_name = try self.nameMangling(true, filename);
            defer mangled_name.deinit();
            try fs.renameAbsolute(filename, mangled_name.items);
        } else {
            mangled_name = try self.nameMangling(false, filename);
            defer mangled_name.deinit();
            try fs.rename(fs.cwd(), filename, self.trashbin_dir, mangled_name.items);
        }
    }
}

fn deletePermanently(self: Self) !void {
    if (self.file_contents.len == 0) {
        const msg_fmt = ansi.warn ++ "Warn: " ++ ansi.reset ++ "Are you sure to empty the trashbin? (y/N): ";
        std.debug.print(msg_fmt, .{});

        const stdin = io.getStdIn().reader();
        const data = try stdin.readUntilDelimiterAlloc(self.allocator, '\n', 4096);

        if (!yesValue.has(data)) return;

        var dir_iter = try self.trashbin_dir.openIterableDir(".", .{});
        defer dir_iter.close();
        var walker = try dir_iter.walk(self.allocator);
        defer walker.deinit();

        while (try walker.next()) |entry| {
            try self.trashbin_dir.deleteTree(entry.path);
        }

        return;
    }

    for (self.file_contents) |filename| {
        if (!self.force) {
            // zig fmt: off
            const file_msg_fmt = ansi.warn ++ "Warn: " ++ ansi.reset ++ "the file `{s}` will be removed permantly.\n"
                ++ " " ** 6 ++ "Are you sure to remove this? (y/N): ";
            const dir_msg_fmt = ansi.warn ++ "Warn: " ++ ansi.reset ++ "the directory `{s}` and its subcontents will be removed permantly.\n"
                ++ " " ** 6 ++ "Are you sure to remove this? (y/N): ";
            // zig fmt: on

            // TODO: This cannot distinguish the symlink
            const is_dir = (try fs.cwd().statFile(filename)).kind == .Directory;
            if (is_dir) {
                std.debug.print(dir_msg_fmt, .{filename});
            } else {
                std.debug.print(file_msg_fmt, .{filename});
            }

            const stdin = io.getStdIn().reader();
            const data = try stdin.readUntilDelimiterAlloc(self.allocator, '\n', 4096);

            if (!yesValue.has(data)) return;
        }

        if (isAbsolute(filename)) {
            fs.deleteFileAbsolute(filename) catch |err| {
                switch (err) {
                    error.IsDir => {
                        if (!self.recursive) return error.TryToRemoveDirectoryWithoutRecursiveFlag;
                        try fs.deleteTreeAbsolute(filename);
                    },
                    else => return err,
                }
            };
        } else {
            fs.cwd().deleteFile(filename) catch |err| {
                switch (err) {
                    error.IsDir => {
                        if (!self.recursive) return error.TryToRemoveDirectoryWithoutRecursiveFlag;
                        try fs.cwd().deleteTree(filename);
                    },
                    else => return err,
                }
            };
        }
    }
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
            try output.appendSlice("/.Trash");
        },
        .windows => @compileError("windows not supported yet"),
        else => @compileError("only linux, macos and windows(not yet) are supported"),
    }

    return output;
}

fn nameMangling(self: Self, comptime is_absolute: bool, filename: []const u8) !ArrayList(u8) {
    var output = try ArrayList(u8).initCapacity(self.allocator, 200);
    errdefer output.deinit();
    var writer = output.writer();

    const basename = fs.path.basename(filename);

    const hashString = std.hash_map.hashString;

    const base64_codec = base64.url_safe_no_pad;
    const base64_encoder = comptime base64.Base64Encoder.init(
        base64_codec.alphabet_chars,
        base64_codec.pad_char,
    );
    var base64_buf: [@bitSizeOf(u64)]u8 = undefined;

    const path_hash = try fmt.allocPrint(self.allocator, "{d}|{d}", .{
        time.milliTimestamp(),
        hashString(filename),
    });
    const hashed_string = base64_encoder.encode(&base64_buf, path_hash);

    if (is_absolute) {
        try writer.print("{s}/{s}!{s}", .{ self.trashbin_path.items, hashed_string, basename });
    } else {
        try writer.print("{s}!{s}", .{ hashed_string, basename });
    }

    return output;
}
