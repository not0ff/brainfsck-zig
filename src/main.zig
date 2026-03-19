const std = @import("std");

// https://esolangs.org/wiki/Brainfuck#Language_overview
const Cmd = enum(u8) {
    MOVE_RIGHT = '>',
    MOVE_LEFT = '<',
    INC = '+',
    DEC = '-',
    OUTPUT = '.',
    INPUT = ',',
    JUMP_IF_ZERO = '[',
    JUMP_IF_NONZERO = ']',
};

const Op = struct {
    cmd: Cmd,
    value: ?usize = null,
};

pub fn main() !void {
    const allocator = std.heap.smp_allocator;
    const argv = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, argv);

    if (argv.len < 2) {
        std.log.err("Missing arguments!\nUsage: ./brainfsck <filename>\n", .{});
        return;
    }

    var file_buf: [1024]u8 = undefined;
    const file = try std.fs.cwd().openFileZ(argv[1], .{ .mode = .read_only });
    defer file.close();
    var file_reader = file.reader(&file_buf);
    const reader = &file_reader.interface;

    const stat = try file.stat();
    const content = try reader.readAlloc(allocator, stat.size);
    defer allocator.free(content);

    var ops_list: std.ArrayList(Op) = .empty;
    defer ops_list.deinit(allocator);

    var jump_stack: std.ArrayList(usize) = .empty;
    defer jump_stack.deinit(allocator);

    var pos: usize = 0;
    var i: usize = 0;
    while (i < content.len) : (i += 1) {
        const cmd = std.enums.fromInt(Cmd, content[i]) orelse continue;
        var op: Op = .{ .cmd = cmd };

        switch (cmd) {
            .JUMP_IF_ZERO => {
                try jump_stack.append(allocator, pos);
            },
            .JUMP_IF_NONZERO => {
                if (jump_stack.pop()) |jump| {
                    if (ops_list.items[jump].cmd != Cmd.JUMP_IF_ZERO) {
                        std.log.err("Unclosed loop at index: {d}", .{i});
                        return;
                    }
                    ops_list.items[jump].value = pos;
                    op.value = jump;
                }
            },
            else => {},
        }
        try ops_list.append(allocator, op);
        pos += 1;
    }

    const ops = try ops_list.toOwnedSlice(allocator);
    defer allocator.free(ops);

    var memory: [30_000]u8 = undefined;
    @memset(&memory, 0);
    var p: usize = 0;
    pos = 0;
    while (pos < ops.len) : (pos += 1) {
        const op = ops[pos];
        switch (op.cmd) {
            .MOVE_RIGHT => p += 1,
            .MOVE_LEFT => p -= 1,
            .INC => memory[p] +%= 1,
            .DEC => memory[p] -%= 1,
            .OUTPUT => std.debug.print("{c}", .{memory[p]}),
            .INPUT => {
                std.log.err("input not implemented\n", .{});
                return;
            },
            .JUMP_IF_ZERO => {
                if (memory[p] == 0) {
                    pos = op.value.?;
                }
            },
            .JUMP_IF_NONZERO => {
                if (memory[p] != 0) {
                    pos = op.value.?;
                }
            },
        }
    }
}
