const std = @import("std");
const ansi = @import("../../ansi.zig");
const fileinfo = @import("../fileinfo.zig");
const win = @import("windows");
const fmt = std.fmt;
const fs = std.fs;
const mem = std.mem;
const time = std.time;
const unicode = std.unicode;

const addNullByte = std.cstr.addNullByte;
const isAbsolute = fs.path.isAbsolute;
const parseBytes = @import("../space_shower.zig").parseBytes;
const handleYesNo = @import("../input_handler.zig").handleYesNo;

const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Io = std.Io;

const XiloError = error{
    TryToRemoveDirectoryWithoutRecursiveFlag,
    FailedToRemoveFile,
    FailedToEmptyTrashbin,
    FailedToGetTrashbinSize,
};

// fields for Remover
allocator: Allocator,
io: Io,
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
    environ: std.process.Environ,
    recursive: bool,
    force: bool,
    permanent: bool,
    show_space: bool,
    file_contents: []const []const u8,
) !Self {
    _ = environ;

    return .{
        .allocator = allocator,
        .io = io,
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
    var buf: [4096]u8 = undefined;
    const stdout_fs = Io.File.stdout();
    var stdout_buf = stdout_fs.writer(self.io, &buf);
    var stdout = &stdout_buf.interface;

    var trashbin_info: win.SHQUERYRBINFO = undefined;
    trashbin_info.cbSize = @sizeOf(win.SHQUERYRBINFO);
    const hr = win.SHQueryRecycleBinW(null, &trashbin_info);
    if (win.FAILED(hr)) {
        try printError(self.allocator, @as(u32, @bitCast(hr)));
        return error.FailedToGetTrashbinSize;
    }

    var size_human_readable = try parseBytes(
        self.allocator,
        @intCast(trashbin_info.i64Size),
    );
    defer size_human_readable.deinit(self.allocator);

    const msg_fmt = ansi.note ++ "Note: " ++ ansi.reset ++
        "The space of the current trashbin is {s}.\n";
    try stdout.print(msg_fmt, .{size_human_readable.items});
    try stdout.flush();
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

        const filename_z = try unicode.utf8ToUtf16LeAllocZ(self.allocator, filename);
        defer self.allocator.free(filename_z);

        var shf = mem.zeroes(win.SHFILEOPSTRUCTW);

        shf.wFunc = win.FO_DELETE;
        shf.pFrom = filename_z.ptr;
        shf.fFlags = win.FOF_ALLOWUNDO | win.FOF_NOCONFIRMATION | win.FOF_SILENT;

        const errno = win.SHFileOperationW(&shf);
        if (errno != 0) {
            try printError(self.allocator, @intCast(errno));
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
        if (!(try handleYesNo(self.io, msg_fmt, .{}))) return;
        if (!(try handleYesNo(self.io, really_msg_fmt, .{}))) return;

        //const dw_flag = win.SHERB_NOCONFIRMATION | win.SHERB_NOSOUND;
        if (win.FAILED(win.SHEmptyRecycleBinW(null, null, 0))) {
            try printError(self.allocator, win.GetLastError());
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

fn printError(allocator: Allocator, errno: win.DWORD) !void {
    const buf = try allocator.alloc(u16, 255);
    defer allocator.free(buf);

    const buf_len = win.FormatMessageW(
        win.FORMAT_MESSAGE_FROM_SYSTEM,
        null,
        errno,
        win.MAKELANGID(win.LANG_NEUTRAL, win.SUBLANG_DEFAULT),
        buf.ptr,
        255,
        null,
    );

    const msg = try unicode.utf16LeToUtf8Alloc(allocator, buf[0..buf_len]);
    defer allocator.free(msg);

    std.debug.print(
        ansi.@"error" ++ "Error: " ++ ansi.reset ++ "{s}\n",
        .{msg},
    );
}
