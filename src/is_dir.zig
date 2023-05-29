const std = @import("std");
const builtin = @import("builtin");
const c = @cImport({
    @cInclude("sys/stat.h");
});

const MACOS_SYSCALL_OFFSET = 0x2000000;
const LSTAT_SYSCALL = switch (builtin.os.tag) {
    .linux => switch (builtin.cpu.arch) {
        .x86_64 => 6,
        else => @compileError(
            \\Other machines are not tested yet.
            \\However, there is a plan to support various linux machines.
        ),
    },
    .macos => 340,
    else => @compileError("Other OS except macos or linux is not supported."),
};

pub fn isDir(path: []const u8) !bool {
    var stat: c.struct_stat = undefined;
    const result = switch (builtin.os.tag) {
        .linux => switch (builtin.cpu.arch) {
            // TODO: This code is not tested yet.
            .x86_64 => asm volatile ("syscall"
                : [ret] "={rax}" (-> usize),
                : [number] "{rax}" (LSTAT_SYSCALL),
                  [arg1] "{rdi}" (path.ptr),
                  [arg2] "{rsi}" (&stat),
                : "rcx", "r11"
            ),
            else => @compileError(
                \\Other machines are not tested yet.
                \\However, there is a plan to support various linux machines.
            ),
        },
        .macos => switch (builtin.cpu.arch) {
            .x86_64 => asm volatile ("syscall"
                : [ret] "={rax}" (-> usize),
                : [number] "{rax}" (MACOS_SYSCALL_OFFSET + LSTAT_SYSCALL),
                  [arg1] "{rdi}" (path.ptr),
                  [arg2] "{rsi}" (&stat),
                : "rcx", "r11"
            ),
            // TODO: This code is not tested yet.
            .aarch64 => asm volatile ("svc 0x80"
                : [ret] "={x0}" (-> usize),
                : [number] "{x16}" (LSTAT_SYSCALL),
                  [arg1] "{x1}" (path.ptr),
                  [arg2] "{x2}" (&stat),
            ),
            else => @compileError("Currently, the only cpu architectures of MacOS are x86_64 and arm64"),
        },
        else => @compileError("Other OS except macos or linux is not supported."),
    };

    if (result < 0) {
        return error.IsDirDeterminationFailed;
    }
    return stat.st_mode & c.S_IFDIR != 0;
}
