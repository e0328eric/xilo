const std = @import("std");
const io = std.io;
const fs = std.fs;
const base64 = std.base64;
const fileinfo = @import("./fileinfo.zig");

const Allocator = std.mem.Allocator;

pub fn rename(
    allocator: Allocator,
    old_dir: fs.Dir,
    old_subpath: []const u8,
    new_dir: fs.Dir,
    new_subpath: []const u8,
) !void {
    fs.rename(old_dir, old_subpath, new_dir, new_subpath) catch |err| switch (err) {
        error.RenameAcrossMountPoints => try renameAcrossMountPoints(
            allocator,
            old_dir,
            old_subpath,
            new_dir,
            new_subpath,
        ),
        else => return err,
    };
}

pub fn renameAbsolute(
    allocator: Allocator,
    old_path: []const u8,
    new_path: []const u8,
) !void {
    fs.renameAbsolute(old_path, new_path) catch |err| switch (err) {
        error.RenameAcrossMountPoints => try renameAbsoluteAcrossMountPoints(
            allocator,
            old_path,
            new_path,
        ),
        else => return err,
    };
}

fn renameAcrossMountPoints(
    allocator: Allocator,
    old_dir: fs.Dir,
    old_subpath: []const u8,
    new_dir: fs.Dir,
    new_subpath: []const u8,
) !void {
    if (try fileinfo.isDir(old_subpath)) {
        try renameAcrossMountPointsDirs(allocator, old_dir, old_subpath, new_dir, new_subpath);
    } else {
        try renameAcrossMountPointsFiles(old_dir, old_subpath, new_dir, new_subpath);
    }
}

fn renameAcrossMountPointsDirs(
    allocator: Allocator,
    old_dir: fs.Dir,
    old_subpath: []const u8,
    new_dir: fs.Dir,
    new_subpath: []const u8,
) !void {
    var dir_movefrom = try old_dir.openDir(old_subpath, .{ .iterate = true });
    defer dir_movefrom.close();
    new_dir.makeDir(new_subpath) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    var dir_moveinto = try new_dir.openDir(new_subpath, .{});
    defer dir_moveinto.close();

    var walker = try dir_movefrom.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        const path = try entry.dir.realpathAlloc(allocator, entry.path);
        defer allocator.free(path);

        if (try fileinfo.isDir(path)) {
            try renameAcrossMountPointsDirs(
                allocator,
                entry.dir,
                entry.path,
                dir_moveinto,
                entry.path,
            );
        } else {
            try renameAcrossMountPointsFiles(
                entry.dir,
                entry.path,
                dir_moveinto,
                entry.path,
            );
        }
    }

    // delete directory recursively
    try old_dir.deleteTree(old_subpath);
}

fn renameAcrossMountPointsFiles(
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

    var reader_buf: [4096]u8 = undefined;
    var writer_buf: [4096]u8 = undefined;
    var buffer_movefrom = file_movefrom.reader(&reader_buf);
    var buffer_moveinto = file_moveinto.writer(&writer_buf);

    var buf = [_]u8{0} ** 4096;
    while (true) {
        const bytes_read = try buffer_movefrom.interface.readSliceShort(&buf);
        const bytes_writtten = try buffer_moveinto.interface.write(buf[0..bytes_read]);
        if (bytes_writtten == 0) break;
    }
    try buffer_moveinto.end();

    // all contents are copied. can close the file_movefrom
    file_movefrom.close();
    already_closed = true;

    // delete the file_movefrom
    try old_dir.deleteFile(old_subpath);
}

fn renameAbsoluteAcrossMountPoints(
    allocator: Allocator,
    old_path: []const u8,
    new_path: []const u8,
) !void {
    var dir_movefrom = try fs.openDirAbsolute(old_path, .{ .iterate = true });
    defer dir_movefrom.close();
    fs.makeDirAbsolute(new_path) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    var dir_moveinto = try fs.openDirAbsolute(new_path, .{});
    defer dir_moveinto.close();

    var walker = try dir_movefrom.walk(allocator);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        const path = try entry.dir.realpathAlloc(allocator, entry.path);
        defer allocator.free(path);

        if (try fileinfo.isDir(path)) {
            try renameAcrossMountPointsDirs(
                allocator,
                entry.dir,
                entry.path,
                dir_moveinto,
                entry.path,
            );
        } else {
            try renameAcrossMountPointsFiles(
                entry.dir,
                entry.path,
                dir_moveinto,
                entry.path,
            );
        }
    }

    // delete directory recursively
    var delete_walker = try dir_movefrom.walk(allocator);
    defer delete_walker.deinit();

    while (try walker.next()) |entry| {
        const path = try entry.dir.realpathAlloc(allocator, entry.path);
        defer allocator.free(path);

        if (try fileinfo.isDir(path)) {
            try entry.dir.deleteTree(entry.path);
        } else {
            try entry.dir.deleteFile(entry.path);
        }
    }
}

fn renameAbsoluteAcrossMountPointsFiles(old_path: []const u8, new_path: []const u8) !void {
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
