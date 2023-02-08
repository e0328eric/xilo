const std = @import("std");
const ansi = @import("./ansi.zig");
const Remover = @import("./Remover.zig");
const Zlap = @import("zlap").Zlap;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const allocator = arena.allocator();

    var zlap = try Zlap.init(allocator, @embedFile("./xilo_command.json"));
    defer zlap.deinit();

    // Datas from command line argument
    const file_contents = zlap.main_args.items[0].value.strings.items;
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

    if (zlap.is_help or (!is_permanent and file_contents.len == 0)) {
        const err_msg = ansi.@"error" ++ "Error: " ++ ansi.reset ++ "there is no file/directory name to run this program.\n";
        const note_msg = ansi.warn ++ "Note:  " ++ ansi.reset ++ "add files or directories to remove.\n\n";

        std.debug.print(err_msg, .{});
        std.debug.print(note_msg, .{});
        std.debug.print("{s}\n", .{zlap.help_msg});
    }

    var remover = try Remover.init(
        allocator,
        is_recursive,
        is_force,
        is_permanent,
        file_contents,
    );
    defer remover.deinit();

    remover.run() catch |err| {
        switch (err) {
            error.TryToRemoveDirectoryWithoutRecursiveFlag => {
                std.debug.print(ansi.@"error" ++ "Error: " ++ ansi.reset ++ "cannot remove a directory without `--recursive` flag\n", .{});
            },
            else => return err,
        }
    };
}
