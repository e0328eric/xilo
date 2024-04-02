const std = @import("std");
const io = std.io;
const fs = std.fs;

pub fn rename(
    old_dir: fs.Dir,
    old_subpath: []const u8,
    new_dir: fs.Dir,
    new_subpath: []const u8,
) !void {
    fs.rename(old_dir, old_subpath, new_dir, new_subpath) catch |err| switch (err) {
        error.RenameAcrossMountPoints => try renameAcrossMountPoints(
            old_dir,
            old_subpath,
            new_dir,
            new_subpath,
        ),
        else => return err,
    };
}

pub fn renameAbsolute(old_path: []const u8, new_path: []const u8) !void {
    fs.renameAbsolute(old_path, new_path) catch |err| switch (err) {
        error.RenameAcrossMountPoints => try renameAbsoluteAcrossMountPoints(
            old_path,
            new_path,
        ),
        else => return err,
    };
}

fn renameAcrossMountPoints(
    old_dir: fs.Dir,
    old_subpath: []const u8,
    new_dir: fs.Dir,
    new_subpath: []const u8,
) !void {
    var already_closed = false;

    const file_movefrom = try old_dir.openFile(old_subpath, .{});
    defer if (!already_closed) file_movefrom.close();
    const file_moveinto = try new_dir.createFile(new_subpath, .{});
    defer file_moveinto.close();

    var buffer_movefrom = io.bufferedReader(file_movefrom.reader());
    var buffer_moveinto = io.bufferedWriter(file_moveinto.writer());

    var buf = [_]u8{0} ** 4096;
    while (true) {
        const bytes_read = try buffer_movefrom.read(&buf);
        const bytes_writtten = try buffer_moveinto.writer().write(buf[0..bytes_read]);
        if (bytes_writtten == 0) break;
    }
    try buffer_moveinto.flush();

    // all contents are copied. can close the file_movefrom
    file_movefrom.close();
    already_closed = true;

    // delete the file_movefrom
    try old_dir.deleteFile(old_subpath);
}

fn renameAbsoluteAcrossMountPoints(old_path: []const u8, new_path: []const u8) !void {
    var already_closed = false;

    const file_movefrom = try fs.openFileAbsolute(old_path, .{});
    defer if (!already_closed) file_movefrom.close();
    const file_moveinto = try fs.createFileAbsolute(new_path, .{});
    defer file_moveinto.close();

    var buffer_movefrom = io.bufferedReader(file_movefrom.reader());
    var buffer_moveinto = io.bufferedWriter(file_moveinto.writer());

    var buf = [_]u8{0} ** 4096;
    while (true) {
        const bytes_read = try buffer_movefrom.read(&buf);
        const bytes_writtten = try buffer_moveinto.writer().write(buf[0..bytes_read]);
        if (bytes_writtten == 0) break;
    }
    try buffer_moveinto.flush();

    // all contents are copied. can close the file_movefrom
    file_movefrom.close();
    already_closed = true;

    // delete the file_movefrom
    try fs.deleteFileAbsolute(old_path);
}
