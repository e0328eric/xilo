const std = @import("std");

const Allocator = std.mem.Allocator;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;
const Io = std.Io;

// Fixed Size Allocator
var buf = [_]u8{0} ** 4096;
var fixed_allocator = FixedBufferAllocator.init(&buf);
const allocator = fixed_allocator.allocator();

const FileInfoError = error{
    CannotGetFileInfo,
    CannotGetFileSize,
    CannotGetDirSize,
};

inline fn lstat(
    dir: Io.Dir,
    io: Io,
    sub_path: []const u8,
) !Io.Dir.Stat {
    return Io.Dir.statFile(dir, io, sub_path, .{ .follow_symlinks = false });
}

pub fn isDir(io: Io, path: []const u8) !bool {
    const stat = try lstat(Io.Dir.cwd(), io, path);
    return stat.kind == .directory;
}

pub fn isDirZ(io: Io, path: [:0]const u8) !bool {
    return isDir(io, @ptrCast(path));
}

pub fn getFileSize(io: Io, path: []const u8) !u64 {
    const stat = try lstat(Io.Dir.cwd(), io, path);
    return stat.size;
}

pub fn getDirSize(
    outsize_allocator: Allocator,
    io: Io,
    dir_path: []const u8,
) !u64 {
    var output: u64 = 0;
    var trashbin = try Io.Dir.openDirAbsolute(
        io,
        dir_path,
        .{ .iterate = true },
    );
    defer trashbin.close(io);

    var walker = try trashbin.walk(outsize_allocator);
    defer walker.deinit();

    while (true) {
        const file_content = walker.next(io) catch |err| switch (err) {
            error.NotDir, error.FileNotFound => continue,
            else => return err,
        };

        if (file_content) |fc| {
            const absolute_file_path = fc.dir.realPathFileAlloc(
                io,
                fc.path,
                allocator,
            ) catch |err| {
                switch (err) {
                    // XXX: Why error.NotDir can occur?
                    error.FileNotFound, error.NotDir => continue,
                    else => return err,
                }
            };
            defer allocator.free(absolute_file_path);

            const file_size = if (try isDir(io, absolute_file_path))
                try getDirSize(outsize_allocator, io, absolute_file_path)
            else
                try getFileSize(io, absolute_file_path);
            output +|= file_size;
        } else break;
    }

    return output;
}
