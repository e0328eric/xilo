const std = @import("std");
const base64 = std.base64;
const fileinfo = @import("./fileinfo.zig");

const Allocator = std.mem.Allocator;
const Io = std.Io;

pub fn rename(
    io: Io,
    allocator: Allocator,
    old_dir: Io.Dir,
    old_subpath: []const u8,
    new_dir: Io.Dir,
    new_subpath: []const u8,
) !void {
    Io.Dir.rename(
        old_dir,
        old_subpath,
        new_dir,
        new_subpath,
        io,
    ) catch |err| switch (err) {
        error.RenameAcrossMountPoints => try renameAcrossMountPoints(
            io,
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
    io: Io,
    allocator: Allocator,
    old_path: []const u8,
    new_path: []const u8,
) !void {
    Io.Dir.renameAbsolute(old_path, new_path, io) catch |err| switch (err) {
        error.RenameAcrossMountPoints => try renameAbsoluteAcrossMountPoints(
            io,
            allocator,
            old_path,
            new_path,
        ),
        else => return err,
    };
}

fn renameAcrossMountPoints(
    io: Io,
    allocator: Allocator,
    old_dir: Io.Dir,
    old_subpath: []const u8,
    new_dir: Io.Dir,
    new_subpath: []const u8,
) !void {
    if (try fileinfo.isDir(old_subpath)) {
        try renameAcrossMountPointsDirs(
            io,
            allocator,
            old_dir,
            old_subpath,
            new_dir,
            new_subpath,
        );
    } else {
        try renameAcrossMountPointsFiles(
            io,
            old_dir,
            old_subpath,
            new_dir,
            new_subpath,
        );
    }
}

fn renameAcrossMountPointsDirs(
    io: Io,
    allocator: Allocator,
    old_dir: Io.Dir,
    old_subpath: []const u8,
    new_dir: Io.Dir,
    new_subpath: []const u8,
) !void {
    var dir_movefrom = try old_dir.openDir(
        io,
        old_subpath,
        .{ .iterate = true },
    );
    defer dir_movefrom.close(io);
    new_dir.createDir(io, new_subpath, .default_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    var dir_moveinto = try new_dir.openDir(io, new_subpath, .{});
    defer dir_moveinto.close(io);

    var walker = try dir_movefrom.walk(allocator);
    defer walker.deinit();

    while (try walker.next(io)) |entry| {
        const path = try entry.dir.realPathFileAlloc(
            io,
            entry.path,
            allocator,
        );
        defer allocator.free(path);

        if (try fileinfo.isDir(path)) {
            try renameAcrossMountPointsDirs(
                io,
                allocator,
                entry.dir,
                entry.path,
                dir_moveinto,
                entry.path,
            );
        } else {
            try renameAcrossMountPointsFiles(
                io,
                entry.dir,
                entry.path,
                dir_moveinto,
                entry.path,
            );
        }
    }

    // delete directory recursively
    try old_dir.deleteTree(io, old_subpath);
}

fn renameAcrossMountPointsFiles(
    io: Io,
    old_dir: Io.Dir,
    old_subpath: []const u8,
    new_dir: Io.Dir,
    new_subpath: []const u8,
) !void {
    var already_closed = false;

    const file_movefrom = try old_dir.openFile(io, old_subpath, .{});
    defer if (!already_closed) file_movefrom.close(io);
    const file_moveinto = try new_dir.createFile(io, new_subpath, .{});
    defer file_moveinto.close(io);

    var reader_buf: [1024]u8 = undefined;
    var writer_buf: [1024]u8 = undefined;
    var buffer_movefrom = file_movefrom.reader(io, &reader_buf);
    var buffer_moveinto = file_moveinto.writer(io, &writer_buf);

    var buf = [_]u8{0} ** 1024;
    while (true) {
        const bytes_read = try buffer_movefrom.interface.readSliceShort(&buf);
        const bytes_writtten = try buffer_moveinto.interface.write(buf[0..bytes_read]);
        if (bytes_writtten == 0) break;
    }
    try buffer_moveinto.end();

    // all contents are copied. can close the file_movefrom
    file_movefrom.close(io);
    already_closed = true;

    // delete the file_movefrom
    try old_dir.deleteFile(io, old_subpath);
}

fn renameAbsoluteAcrossMountPoints(
    io: Io,
    allocator: Allocator,
    old_path: []const u8,
    new_path: []const u8,
) !void {
    var dir_movefrom = try Io.Dir.openDirAbsolute(
        io,
        old_path,
        .{ .iterate = true },
    );
    defer dir_movefrom.close(io);
    Io.Dir.createDirAbsolute(io, new_path, .default_dir) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    var dir_moveinto = try Io.Dir.openDirAbsolute(io, new_path, .{});
    defer dir_moveinto.close(io);

    var walker = try dir_movefrom.walk(allocator);
    defer walker.deinit();

    while (try walker.next(io)) |entry| {
        const path = try entry.dir.realPathFileAlloc(
            io,
            entry.path,
            allocator,
        );
        defer allocator.free(path);

        if (try fileinfo.isDir(path)) {
            try renameAcrossMountPointsDirs(
                io,
                allocator,
                entry.dir,
                entry.path,
                dir_moveinto,
                entry.path,
            );
        } else {
            try renameAcrossMountPointsFiles(
                io,
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

    while (try walker.next(io)) |entry| {
        const path = try entry.dir.realPathFileAlloc(
            io,
            entry.path,
            allocator,
        );
        defer allocator.free(path);

        if (try fileinfo.isDir(path)) {
            try entry.dir.deleteTree(io, entry.path);
        } else {
            try entry.dir.deleteFile(io, entry.path);
        }
    }
}

fn renameAbsoluteAcrossMountPointsFiles(
    io: Io,
    old_path: []const u8,
    new_path: []const u8,
) !void {
    var already_closed = false;

    const file_movefrom = try Io.Dir.openFileAbsolute(io, old_path, .{});
    defer if (!already_closed) file_movefrom.close(io);
    const file_moveinto = try Io.Dir.createFileAbsolute(io, new_path, .{});
    defer file_moveinto.close(io);

    var reader_buf: [1024]u8 = undefined;
    var writer_buf: [1024]u8 = undefined;
    var buffer_movefrom = file_movefrom.reader(io, &reader_buf);
    var buffer_moveinto = file_moveinto.reader(io, &writer_buf);

    var buf = [_]u8{0} ** 1024;
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
    try Io.Dir.deleteFileAbsolute(io, old_path);
}
