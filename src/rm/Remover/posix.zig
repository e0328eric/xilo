const std = @import("std");
const ansi = @import("../../ansi.zig");
const fileinfo = @import("../fileinfo.zig");
const base64 = std.base64;
const fmt = std.fmt;
const fs = std.fs;
const math = std.math;
const mem = std.mem;
const process = std.process;
const time = std.time;

const addNullByte = std.cstr.addNullByte;
const isAbsolute = fs.path.isAbsolute;
const parseBytes = @import("../space_shower.zig").parseBytes;
const handleYesNo = @import("../input_handler.zig").handleYesNo;

const custom_trashbin_path = @import("xilo_build").custom_trashbin_path;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Io = std.Io;

const XiloError = error{
    TryToRemoveDirectoryWithoutRecursiveFlag,
};

// fields for Remover
allocator: Allocator,
io: Io,
trashbin_path: ArrayList(u8),
trashbin_dir: Io.Dir,
recursive: bool,
force: bool,
permanent: bool,
show_space: bool,
file_contents: []const []const u8,
// END of fields

const Self = @This();

pub fn init(
    allocator: Allocator,
    io: Io,
    recursive: bool,
    force: bool,
    permanent: bool,
    show_space: bool,
    file_contents: []const []const u8,
) !Self {
    var trashbin_path = try getTrashbinPath(allocator);
    errdefer trashbin_path.deinit(allocator);

    Io.Dir.createDirAbsolute(io, trashbin_path.items, .default_dir) catch |err| {
        switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        }
    };

    return .{
        .allocator = allocator,
        .io = io,
        .trashbin_path = trashbin_path,
        .trashbin_dir = try Io.Dir.openDirAbsolute(io, trashbin_path.items, .{}),
        .recursive = recursive,
        .force = force,
        .permanent = permanent,
        .show_space = show_space,
        .file_contents = file_contents,
    };
}

pub fn deinit(self: *Self) void {
    self.trashbin_dir.close(self.io);
}

pub fn run(self: Self) !void {
    if (self.show_space) {
        var buf: [1024]u8 = undefined;
        var stdout = Io.File.stdout().writer(self.io, &buf);

        const trashbin_size = try self.getTrashbinSize();
        var size_human_readable = try parseBytes(self.allocator, trashbin_size);
        defer size_human_readable.deinit(self.allocator);

        const msg_fmt = ansi.note ++ "Note: " ++ ansi.reset ++
            "The space of the current trashbin is {s}.\n";
        try stdout.interface.print(msg_fmt, .{size_human_readable.items});
        try stdout.interface.flush();
    } else if (self.permanent) {
        return self.deletePermanently();
    } else {
        return self.delete();
    }
}

fn delete(self: Self) !void {
    for (self.file_contents) |filename| {
        if (!self.force) {
            const msg_fmt = ansi.warn ++ "Warn: " ++
                ansi.reset ++ "Are you sure to remove `{s}`? (y/N): ";
            if (!(try handleYesNo(self.io, msg_fmt, .{filename}))) return;
        }

        if (try fileinfo.isDir(self.io, filename) and !self.recursive) {
            return error.TryToRemoveDirectoryWithoutRecursiveFlag;
        }

        var mangled_name: ArrayList(u8) = undefined;
        if (isAbsolute(filename)) {
            mangled_name = try self.nameMangling(true, filename);
            defer mangled_name.deinit(self.allocator);
            try @import("../rename.zig").renameAbsolute(
                self.io,
                self.allocator,
                filename,
                mangled_name.items,
            );
        } else {
            mangled_name = try self.nameMangling(false, filename);
            defer mangled_name.deinit(self.allocator);
            try @import("../rename.zig").rename(
                self.io,
                self.allocator,
                Io.Dir.cwd(),
                filename,
                self.trashbin_dir,
                mangled_name.items,
            );
        }
    }
}

fn deletePermanently(self: Self) !void {
    if (self.file_contents.len == 0) {
        const msg_fmt = ansi.warn ++ "Warn: " ++
            ansi.reset ++ "Are you sure to empty the trashbin? (y/N): ";
        const really_msg_fmt = ansi.warn ++ "Warn: " ++
            ansi.reset ++ "Are you " ++ ansi.bold ++ "really" ++
            ansi.reset ++ " sure to empty the trashbin? (y/N): ";
        if (!(try handleYesNo(self.io, msg_fmt, .{}))) return;
        if (!(try handleYesNo(self.io, really_msg_fmt, .{}))) return;

        var dir_iter = try self.trashbin_dir.openDir(
            self.io,
            ".",
            .{ .iterate = true },
        );
        defer dir_iter.close(self.io);
        var walker = try dir_iter.walk(self.allocator);
        defer walker.deinit();

        while (try walker.next(self.io)) |entry| {
            try self.trashbin_dir.deleteTree(self.io, entry.path);
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

            if (try fileinfo.isDir(self.io, filename)) {
                if (!(try handleYesNo(self.io, dir_msg_fmt, .{filename})))
                    return;
            } else {
                if (!(try handleYesNo(self.io, file_msg_fmt, .{filename})))
                    return;
            }
        }

        if (isAbsolute(filename)) {
            Io.Dir.deleteFileAbsolute(self.io, filename) catch |err| {
                switch (err) {
                    error.IsDir => {
                        if (!self.recursive)
                            return error.TryToRemoveDirectoryWithoutRecursiveFlag;
                        try Io.Dir.cwd().deleteTree(self.io, filename);
                    },
                    else => return err,
                }
            };
        } else {
            Io.Dir.cwd().deleteFile(self.io, filename) catch |err| {
                switch (err) {
                    error.IsDir => {
                        if (!self.recursive)
                            return error.TryToRemoveDirectoryWithoutRecursiveFlag;
                        try Io.Dir.cwd().deleteTree(self.io, filename);
                    },
                    else => return err,
                }
            };
        }
    }
}

fn getTrashbinSize(self: Self) !u64 {
    return fileinfo.getDirSize(self.allocator, self.io, self.trashbin_path.items);
}

fn getTrashbinPath(allocator: Allocator) !ArrayList(u8) {
    var output = try ArrayList(u8).initCapacity(allocator, 150);
    errdefer output.deinit(allocator);

    if (custom_trashbin_path) |trashbin_path| {
        try output.appendSlice(trashbin_path);
    } else {
        switch (@import("builtin").os.tag) {
            .linux => {
                try output.appendSlice(allocator, std.posix.getenv("HOME").?);
                try output.appendSlice(allocator, "/.cache/xilo");
            },
            .macos => {
                try output.appendSlice(allocator, std.posix.getenv("HOME").?);
                try output.appendSlice(allocator, "/.Trash");
            },
            else => @compileError("only linux, macos and windows are supported"),
        }
    }

    return output;
}

fn nameMangling(
    self: Self,
    comptime is_absolute: bool,
    filename: []const u8,
) !ArrayList(u8) {
    var output = try ArrayList(u8).initCapacity(self.allocator, 200);
    errdefer output.deinit(self.allocator);

    const basename = fs.path.basename(filename);

    const hashString = std.hash_map.hashString;

    const base64_codec = base64.url_safe_no_pad;
    const base64_encoder = comptime base64.Base64Encoder.init(
        base64_codec.alphabet_chars,
        base64_codec.pad_char,
    );
    var base64_buf: [@bitSizeOf(u64)]u8 = undefined;

    const timestamp = try Io.Clock.real.now(self.io);
    const path_hash = try fmt.allocPrint(self.allocator, "{d}|{d}", .{
        timestamp.toMilliseconds(),
        hashString(filename),
    });
    const hashed_string = base64_encoder.encode(&base64_buf, path_hash);

    if (is_absolute) {
        try output.print(self.allocator, "{s}/{s}!{s}", .{
            self.trashbin_path.items,
            basename,
            hashed_string,
        });
    } else {
        try output.print(self.allocator, "{s}!{s}", .{ basename, hashed_string });
    }

    return output;
}
