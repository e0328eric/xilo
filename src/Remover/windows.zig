const std = @import("std");
const ansi = @import("../ansi.zig");
const fileinfo = @import("../fileinfo.zig");
const win = @import("windows");
const fmt = std.fmt;
const fs = std.fs;
const io = std.io;
const mem = std.mem;
const time = std.time;
const unicode = std.unicode;

const addNullByte = std.cstr.addNullByte;
const isAbsolute = fs.path.isAbsolute;
const parseBytes = @import("../space_shower.zig").parseBytes;
const handleYesNo = @import("../input_handler.zig").handleYesNo;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const XiloError = error{
    TryToRemoveDirectoryWithoutRecursiveFlag,
    FailedToRemoveFile,
    FailedToEmptyTrashbin,
};

// fields for Remover
allocator: Allocator,
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
    return .{
        .allocator = allocator,
        .recursive = recursive,
        .force = force,
        .permanent = permanent,
        .show_space = show_space,
        .file_contents = file_contents,
    };
}

// On windows, this function does nothing
pub fn deinit(self: *Self) void {
    _ = self;
}

pub fn run(self: Self) !void {
    if (self.show_space) {
        try self.showTrashbinSpace();
    } else if (self.permanent) {
        try self.deletePermanently();
    } else {
        try self.delete();
    }
}

fn showTrashbinSpace(self: Self) !void {
    const stdout = std.io.getStdOut().writer();

    var trashbin_info: win.SHQUERYRBINFO = undefined;
    const hr = win.SHQueryRecycleBinW(null, &trashbin_info);
    if (win.FAILED(hr)) {
        const errno = win.GetLastError();
        const buf = try self.allocator.alloc(u16, 255);
        defer self.allocator.free(buf);

        const buf_len = win.FormatMessageW(
            win.FORMAT_MESSAGE_FROM_SYSTEM,
            null,
            errno,
            win.MAKELANGID(win.LANG_NEUTRAL, win.SUBLANG_DEFAULT),
            buf.ptr,
            255,
            null,
        );

        const msg = try unicode.utf16LeToUtf8Alloc(self.allocator, buf[0..buf_len]);
        defer self.allocator.free(msg);
    }

    const size_human_readable = try parseBytes(
        self.allocator,
        @intCast(trashbin_info.i64Size),
    );
    defer size_human_readable.deinit();

    const msg_fmt = ansi.note ++ "Note: " ++ ansi.reset ++
        "The space of the current trashbin is {s}.\n";
    try stdout.print(msg_fmt, .{size_human_readable.items});
}

fn delete(self: Self) !void {
    for (self.file_contents) |filename| {
        if (!self.force) {
            const msg_fmt = ansi.warn ++ "Warn: " ++
                ansi.reset ++ "Are you sure to remove `{s}`? (y/N): ";
            if (!(try handleYesNo(self.allocator, msg_fmt, .{filename}))) return;
        }

        if (try fileinfo.isDir(filename) and !self.recursive) {
            return error.TryToRemoveDirectoryWithoutRecursiveFlag;
        }

        const filename_z = try unicode.utf8ToUtf16LeAllocZ(self.allocator, filename);
        defer self.allocator.free(filename_z);

        var shf = mem.zeroes(win.SHFILEOPSTRUCTW);

        shf.wFunc = win.FO_DELETE;
        shf.pFrom = filename_z.ptr;
        shf.fFlags = win.FOF_ALLOWUNDO | win.FOF_NOCONFIRMATION | win.FOF_SILENT;

        if (win.SHFileOperationW(&shf) != 0) {
            return error.FailedToRemoveFile;
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
        if (!(try handleYesNo(self.allocator, msg_fmt, .{}))) return;
        if (!(try handleYesNo(self.allocator, really_msg_fmt, .{}))) return;

        const dw_flag = win.SHERB_NOCONFIRMATION | win.SHERB_NOSOUND;
        if (win.FAILED(win.SHEmptyRecycleBinW(null, null, dw_flag))) {
            return error.FailedToEmptyTrashbin;
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
                if (!(try handleYesNo(self.allocator, dir_msg_fmt, .{filename})))
                    return;
            } else {
                if (!(try handleYesNo(self.allocator, file_msg_fmt, .{filename})))
                    return;
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
