const std = @import("std");
const fs = std.fs;

const Allocator = std.mem.Allocator;
const FixedBufferAllocator = std.heap.FixedBufferAllocator;

// Fixed Size Allocator
var buf = [_]u8{0} ** 4096;
var fixed_allocator = FixedBufferAllocator.init(&buf);
const allocator = fixed_allocator.allocator();

extern "C" fn isDirRaw(path: [*c]const u8, result: ?*bool) bool;
extern "C" fn fileSizeRaw(path: [*c]const u8, result: ?*u64) bool;

const FileInfoError = error{
    CannotGetFileInfo,
    CannotGetFileSize,
    CannotGetDirSize,
};

pub fn isDir(path: []const u8) !bool {
    const path_null = try allocator.dupeZ(u8, path);
    defer allocator.free(path_null);

    var result = false;
    if (!isDirRaw(path_null.ptr, &result)) return error.CannotGetFileInfo;

    return result;
}

pub fn isDirZ(path: [:0]const u8) !bool {
    var result = false;
    if (!isDirRaw(path.ptr, &result)) return error.CannotGetFileInfo;

    return result;
}

pub fn getFileSize(path: []const u8) !u64 {
    const path_null = try allocator.dupeZ(u8, path);
    defer allocator.free(path_null);

    var result: u64 = 0;
    if (!fileSizeRaw(path_null.ptr, &result)) return error.CannotGetFileSize;

    return result;
}

pub fn getDirSize(outsize_allocator: Allocator, dir_path: []const u8) !u64 {
    var output: u64 = 0;
    var trashbin = try fs.openDirAbsolute(dir_path, .{ .iterate = true });
    defer trashbin.close();

    var walker = try trashbin.walk(outsize_allocator);
    defer walker.deinit();

    while (true) {
        const file_content = walker.next() catch |err| switch (err) {
            error.NotDir, error.FileNotFound => continue,
            else => return err,
        };

        if (file_content) |fc| {
            const absolute_file_path = fc.dir.realpathAlloc(
                allocator,
                fc.path,
            ) catch |err| {
                switch (err) {
                    // XXX: Why error.NotDir can occur?
                    error.FileNotFound, error.NotDir => continue,
                    else => return err,
                }
            };
            defer allocator.free(absolute_file_path);

            const file_size = if (try isDir(absolute_file_path))
                try getDirSize(outsize_allocator, absolute_file_path)
            else
                try getFileSize(absolute_file_path);
            output +|= file_size;
        } else break;
    }

    return output;
}
