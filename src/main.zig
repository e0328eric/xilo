const std = @import("std");
const builtin = @import("builtin");
const heap = std.heap;
const ansi = @import("./ansi.zig");
const zlap = @import("zlap");

const Allocator = std.mem.Allocator;
const Io = std.Io;
const Remover = switch (builtin.os.tag) {
    .windows => @import("./rm/Remover/windows.zig"),
    .linux, .macos => @import("./rm/Remover/posix.zig"),
    else => @compileError("only linux, macos and windows are supported"),
};
const Zlap = zlap.Zlap(@embedFile("./xilo_commands.zlap"), null);

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(heap.c_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var threaded = Io.Threaded.init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var zlap_cmd: Zlap = try .init(allocator);
    defer zlap_cmd.deinit();

    if (zlap_cmd.is_help) {
        var buf: [1024]u8 = undefined;
        var stdout = Io.File.stdout().writer(io, &buf);
        try stdout.interface.print("{s}\n", .{zlap_cmd.help_msg});
        return;
    }

    const subcmds = .{ "ln", "rm" };
    inline for (subcmds) |subcmd_str| {
        if (zlap_cmd.isSubcmdActive(subcmd_str)) {
            const subcmd = zlap_cmd.active_subcmd.?;
            try @field(@This(), subcmd_str ++ "Step")(
                allocator,
                io,
                subcmd,
            );
        }
    } else {
        std.debug.print("{s}\n", .{zlap_cmd.help_msg});
        return error.InvalidSubcommand;
    }
}

fn lnStep(
    allocator: Allocator,
    io: Io,
    ln_subcmd: *const zlap.Subcmd,
) !void {
    _ = allocator;

    const source = ln_subcmd.args.get("SOURCE").?.value.string;
    const dest = ln_subcmd.args.get("DEST").?.value.string;

    try @import("./ln/ln.zig").ln(io, source, dest);
}

fn rmStep(
    allocator: Allocator,
    io: Io,
    rm_subcmd: *const zlap.Subcmd,
) !void {
    // Datas from command line argument
    const file_contents = rm_subcmd.args.get("FILES").?.value.strings.items;
    const is_recursive = flag: {
        const flag = rm_subcmd.flags.get("recursive") orelse break :flag false;
        break :flag flag.value.bool;
    };
    const is_force = flag: {
        const flag = rm_subcmd.flags.get("force") orelse break :flag false;
        break :flag flag.value.bool;
    };
    const is_permanent = flag: {
        const flag = rm_subcmd.flags.get("permanent") orelse break :flag false;
        break :flag flag.value.bool;
    };
    const is_show_space = flag: {
        const flag = rm_subcmd.flags.get("show_space") orelse break :flag false;
        break :flag flag.value.bool;
    };

    if (!is_show_space and !is_permanent and file_contents.len == 0) {
        const err_msg = ansi.@"error" ++ "Error: " ++ ansi.reset ++
            "there is no file/directory name to run this program.\n";
        const note_msg = ansi.note ++ "Note:  " ++ ansi.reset ++
            "add files or directories to remove.\n\n";

        std.debug.print(err_msg, .{});
        std.debug.print(note_msg, .{});
        return error.InvalidRmArgument;
    }

    var remover = try Remover.init(
        allocator,
        io,
        is_recursive,
        is_force,
        is_permanent,
        is_show_space,
        file_contents,
    );
    defer remover.deinit();

    remover.run() catch |err| {
        switch (err) {
            error.TryToRemoveDirectoryWithoutRecursiveFlag => {
                std.debug.print(
                    ansi.@"error" ++ "Error: " ++
                        ansi.reset ++
                        "cannot remove a directory without `--recursive` flag\n",
                    .{},
                );
            },
            else => return err,
        }
    };
}
