const std = @import("std");
const builtin = @import("builtin");
const ansi = @import("./ansi.zig");
const fileinfo = @import("./fileinfo.zig");
const base64 = std.base64;
const fmt = std.fmt;
const fs = std.fs;
const io = std.io;
const math = std.math;
const mem = std.mem;
const process = std.process;
const time = std.time;

const addNullByte = std.cstr.addNullByte;
const isAbsolute = fs.path.isAbsolute;
const parseBytes = @import("./space_shower.zig").parseBytes;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const StaticStringMap = std.StaticStringMap;

const XiloError = error{
    TryToRemoveDirectoryWithoutRecursiveFlag,
};

const yesValue = StaticStringMap(void).initComptime(.{
    .{ "y", void },
    .{ "Y", void },
    .{ "yes", void },
    .{ "Yes", void },
    .{ "YES", void },
});

// fields for Remover
allocator: Allocator,
trashbin_path: ArrayList(u8),
trashbin_dir: fs.Dir,
recursive: bool,
force: bool,
permanent: bool,
show_space: bool,
file_contents: []const []const u8,
// END of fields

const Self = @This();

pub fn init(
    allocator: Allocator,
    recursive: bool,
    force: bool,
    permanent: bool,
    show_space: bool,
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
        .show_space = show_space,
        .file_contents = file_contents,
    };
}

pub fn deinit(self: *Self) void {
    self.trashbin_dir.close();
}

pub fn run(self: Self) !void {
    const stdout = std.io.getStdOut().writer();
    if (self.show_space) {
        const trashbin_size = try self.getTrashbinSize();
        const size_human_readable = try parseBytes(self.allocator, trashbin_size);
        defer size_human_readable.deinit();

        // zig fmt: off
        const msg_fmt = ansi.note
            ++ "Note: " ++ ansi.reset ++ "The space of the current trashbin is {s}.\n";
        // zig fmt: on
        try stdout.print(msg_fmt, .{size_human_readable.items});
    } else if (self.permanent) {
        return self.deletePermanently();
    } else {
        return self.delete();
    }
}

fn delete(self: Self) !void {
    const stdout = std.io.getStdOut().writer();
    for (self.file_contents) |filename| {
        if (!self.force) {
            const msg_fmt = ansi.warn ++ "Warn: " ++
                ansi.reset ++ "Are you sure to remove `{s}`? (y/N): ";
            try stdout.print(msg_fmt, .{filename});

            const stdin = io.getStdIn().reader();
            const data = try stdin.readUntilDelimiterAlloc(self.allocator, '\n', 4096);
            defer self.allocator.free(data);

            // Since windows uses CRLF for EOL, we should trim \r character.
            if (builtin.os.tag == .windows) {
                if (!yesValue.has(mem.trimRight(u8, data, "\r"))) return;
            } else {
                if (!yesValue.has(data)) return;
            }
        }

        if (try fileinfo.isDir(filename) and !self.recursive) {
            return error.TryToRemoveDirectoryWithoutRecursiveFlag;
        }

        var mangled_name: ArrayList(u8) = undefined;
        if (isAbsolute(filename)) {
            mangled_name = try self.nameMangling(true, filename);
            defer mangled_name.deinit();
            try @import("./rename.zig").renameAbsolute(
                self.allocator,
                filename,
                mangled_name.items,
            );
        } else {
            mangled_name = try self.nameMangling(false, filename);
            defer mangled_name.deinit();
            try @import("./rename.zig").rename(
                self.allocator,
                fs.cwd(),
                filename,
                self.trashbin_dir,
                mangled_name.items,
            );
        }
    }
}

fn deletePermanently(self: Self) !void {
    const stdout = std.io.getStdOut().writer();
    if (self.file_contents.len == 0) {
        const msg_fmt = ansi.warn ++ "Warn: " ++
            ansi.reset ++ "Are you sure to empty the trashbin? (y/N): ";
        try stdout.print(msg_fmt, .{});

        const stdin = io.getStdIn().reader();
        const data = try stdin.readUntilDelimiterAlloc(self.allocator, '\n', 4096);
        defer self.allocator.free(data);

        // Since windows uses CRLF for EOL, we should trim \r character.
        if (builtin.os.tag == .windows) {
            if (!yesValue.has(mem.trimRight(u8, data, "\r"))) return;
        } else {
            if (!yesValue.has(data)) return;
        }

        var dir_iter = try self.trashbin_dir.openDir(".", .{ .iterate = true });
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
            const file_msg_fmt = ansi.warn ++ "Warn: " ++ ansi.reset ++
                "the file `{s}` will be removed permantly.\n" ++
                " " ** 6 ++ "Are you sure to remove this? (y/N): ";
            const dir_msg_fmt = ansi.warn ++ "Warn: " ++ ansi.reset ++
                "the directory `{s}` and its subcontents will be removed permantly.\n" ++
                " " ** 6 ++ "Are you sure to remove this? (y/N): ";

            if (try fileinfo.isDir(filename)) {
                try stdout.print(dir_msg_fmt, .{filename});
            } else {
                try stdout.print(file_msg_fmt, .{filename});
            }

            const stdin = io.getStdIn().reader();
            const data = try stdin.readUntilDelimiterAlloc(self.allocator, '\n', 4096);
            defer self.allocator.free(data);

            // Since windows uses CRLF for EOL, we should trim \r character.
            if (builtin.os.tag == .windows) {
                if (!yesValue.has(mem.trimRight(u8, data, "\r"))) return;
            } else {
                if (!yesValue.has(data)) return;
            }
        }

        if (isAbsolute(filename)) {
            fs.deleteFileAbsolute(filename) catch |err| {
                switch (err) {
                    error.IsDir => {
                        if (!self.recursive)
                            return error.TryToRemoveDirectoryWithoutRecursiveFlag;
                        try fs.deleteTreeAbsolute(filename);
                    },
                    else => return err,
                }
            };
        } else {
            fs.cwd().deleteFile(filename) catch |err| {
                switch (err) {
                    error.IsDir => {
                        if (!self.recursive)
                            return error.TryToRemoveDirectoryWithoutRecursiveFlag;
                        try fs.cwd().deleteTree(filename);
                    },
                    else => return err,
                }
            };
        }
    }
}

fn getTrashbinSize(self: Self) !u64 {
    return fileinfo.getDirSize(self.allocator, self.trashbin_path.items);
}

fn getTrashbinPath(allocator: Allocator) !ArrayList(u8) {
    var output = try ArrayList(u8).initCapacity(allocator, 150);
    errdefer output.deinit();

    switch (builtin.os.tag) {
        .linux => {
            try output.appendSlice(std.posix.getenv("HOME").?);
            try output.appendSlice("/.cache/xilo");
        },
        .macos => {
            try output.appendSlice(std.posix.getenv("HOME").?);
            try output.appendSlice("/.Trash");
        },
        .windows => {
            const appdata_location = try process.getEnvVarOwned(
                allocator,
                "APPDATA",
            );
            defer allocator.free(appdata_location);
            try output.appendSlice(appdata_location);
            try output.appendSlice("\\xilo");
        },
        else => @compileError("only linux, macos and windows are supported"),
    }

    return output;
}

fn nameMangling(
    self: Self,
    comptime is_absolute: bool,
    filename: []const u8,
) !ArrayList(u8) {
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
        try writer.print("{s}/{s}!{s}", .{
            self.trashbin_path.items,
            basename,
            hashed_string,
        });
    } else {
        try writer.print("{s}!{s}", .{ basename, hashed_string });
    }

    return output;
}
