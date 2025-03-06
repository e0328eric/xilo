const std = @import("std");
const heap = std.heap;
const ansi = @import("./ansi.zig");
const Remover = @import("./Remover.zig");
const Zlap = @import("zlap").Zlap;

pub fn main() !u8 {
    var arena = std.heap.ArenaAllocator.init(heap.c_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    var zlap = try Zlap(@embedFile("./xilo_commands.zlap")).init(allocator);
    defer zlap.deinit();

    // Datas from command line argument
    const file_contents = zlap.main_args.get("FILES").?.value.strings.items;
    const is_recursive = flag: {
        const flag = zlap.main_flags.get("recursive") orelse break :flag false;
        break :flag flag.value.bool;
    };
    const is_force = flag: {
        const flag = zlap.main_flags.get("force") orelse break :flag false;
        break :flag flag.value.bool;
    };
    const is_permanent = flag: {
        const flag = zlap.main_flags.get("permanent") orelse break :flag false;
        break :flag flag.value.bool;
    };
    const is_show_space = flag: {
        const flag = zlap.main_flags.get("show_space") orelse break :flag false;
        break :flag flag.value.bool;
    };

    if (zlap.is_help) {
        const stdout = std.io.getStdOut().writer();
        try stdout.print("{s}\n", .{zlap.help_msg});
        return 1;
    }

    if (!is_show_space and !is_permanent and file_contents.len == 0) {
        const err_msg = ansi.@"error" ++ "Error: " ++ ansi.reset ++
            "there is no file/directory name to run this program.\n";
        const note_msg = ansi.note ++ "Note:  " ++ ansi.reset ++
            "add files or directories to remove.\n\n";

        std.debug.print(err_msg, .{});
        std.debug.print(note_msg, .{});
        std.debug.print("{s}\n", .{zlap.help_msg});
        return 1;
    }

    var remover = try Remover.init(
        allocator,
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

    return 0;
}
