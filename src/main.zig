const std = @import("std");
const tokenizer = @import("./tokenizer.zig");

pub fn main(init: std.process.Init) !void {
    // Prints to stderr, unbuffered, ignoring potential errors.
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});

    // This is appropriate for anything that lives as long as the process.
    const arena: std.mem.Allocator = init.arena.allocator();
    const source = "import std.io\n\nlet name = 2 + 2";

    var tok = tokenizer.Tokenizer.init(source);
    var tokens: std.ArrayList(tokenizer.Token) = .empty;

    while (true) {
        const t = tok.next();
        try tokens.append(arena, t);

        if (t.tag == .eof) break;
    }

    std.debug.print("{} , {}", .{ tok.next().tag, @TypeOf(source) });
}
