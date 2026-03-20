//     brainfsck-zig - brainfuck interpreter written in zig
//     Copyright (C) 2026-present  Not0ff
//
//     This program is free software: you can redistribute it and/or modify
//     it under the terms of the GNU General Public License as published by
//     the Free Software Foundation, either version 3 of the License, or
//     (at your option) any later version.
//
//     This program is distributed in the hope that it will be useful,
//     but WITHOUT ANY WARRANTY; without even the implied warranty of
//     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//     GNU General Public License for more details.
//
//     You should have received a copy of the GNU General Public License
//     along with this program.  If not, see <https://www.gnu.org/licenses/>.

const std = @import("std");

// https://esolangs.org/wiki/Brainfuck#Language_overview
const Cmd = enum { MOVE_RIGHT, MOVE_LEFT, INC, DEC, OUTPUT, INPUT, JUMP_IF_ZERO, JUMP_IF_NONZERO, ZERO_MEM };

fn getCmd(c: u8) ?Cmd {
    return switch (c) {
        '>' => Cmd.MOVE_RIGHT,
        '<' => Cmd.MOVE_LEFT,
        '+' => Cmd.INC,
        '-' => Cmd.DEC,
        '.' => Cmd.OUTPUT,
        ',' => Cmd.INPUT,
        '[' => Cmd.JUMP_IF_ZERO,
        ']' => Cmd.JUMP_IF_NONZERO,
        else => null,
    };
}

const Param = u16;

const Op = struct {
    cmd: Cmd,
    param: Param,
};

fn parseOps(bytes: []u8, allocator: std.mem.Allocator) ![]Op {
    // NOTE: some optimizations are inefficient in the interpreter version though useful in later compilation step
    var ops: std.ArrayList(Op) = .empty;
    defer ops.deinit(allocator);

    // populate ops list initially
    var i: usize = 0;
    while (i < bytes.len) : (i += 1) {
        const cmd = getCmd(bytes[i]) orelse continue;
        var op: Op = .{ .cmd = cmd, .param = 0 };
        switch (cmd) {
            .JUMP_IF_ZERO, .JUMP_IF_NONZERO => {},
            else => {
                var rep: Param = 0;
                while (i + rep < bytes.len and bytes[i] == bytes[i + rep]) {
                    rep += 1;
                }
                i += rep - 1;
                op.param = rep;
            },
        }
        try ops.append(allocator, op);
    }

    // convert [-] and [+] ops to clearing memory
    i = 0;
    while (i + 3 <= ops.items.len) : (i += 1) {
        if ((ops.items[i].cmd == .JUMP_IF_ZERO) and
            (ops.items[i + 1].cmd == .DEC or ops.items[i + 1].cmd == .INC) and
            (ops.items[i + 2].cmd == .JUMP_IF_NONZERO))
        {
            const zero_op: Op = .{ .cmd = .ZERO_MEM, .param = 0 };
            try ops.replaceRange(allocator, i, 3, &[_]Op{zero_op});
            continue;
        }
    }

    // patch jump operations
    var jump_stack: std.ArrayList(Param) = .empty;
    defer jump_stack.deinit(allocator);

    var pos: Param = 0;
    while (pos < ops.items.len) : (pos += 1) {
        var op = &ops.items[pos];

        switch (op.cmd) {
            .JUMP_IF_ZERO => try jump_stack.append(allocator, pos),
            .JUMP_IF_NONZERO => {
                if (jump_stack.items.len == 0) return error.UnclosedLoop;
                if (jump_stack.pop()) |jump| {
                    var jump_op = &ops.items[jump];
                    switch (jump_op.cmd) {
                        .JUMP_IF_ZERO => {
                            jump_op.param = pos + 1;
                            op.param = jump;
                        },
                        else => unreachable,
                    }
                }
            },
            else => {},
        }
    }
    if (jump_stack.items.len != 0) {
        return error.UnclosedLoop;
    }

    return try ops.toOwnedSlice(allocator);
}

fn interpret(ops: []Op, output: *std.Io.Writer, input: *std.Io.Reader) !void {
    var memory: [30_000]u8 = undefined;
    @memset(&memory, 0);

    var ptr: usize = 0;
    var pos: usize = 0;
    while (pos < ops.len) : (pos += 1) {
        const op = ops[pos];
        // std.log.info("pos: <{d}> ptr <{d}> val: <{d}> op: {any}", .{ pos, ptr, memory[ptr], op });
        switch (op.cmd) {
            .MOVE_RIGHT => ptr = (ptr + op.param) % memory.len,
            .MOVE_LEFT => ptr = (ptr + memory.len - (op.param % memory.len)) % memory.len,
            .INC => memory[ptr] +%= @intCast(op.param % 256),
            .DEC => memory[ptr] -%= @intCast(op.param % 256),
            .ZERO_MEM => memory[ptr] = 0,
            .OUTPUT => {
                for (0..op.param) |_| {
                    try output.writeByte(memory[ptr]);
                }
            },
            // doesn't matter whether repeated
            .INPUT => {
                try output.flush();
                memory[ptr] = input.takeByte() catch 0;
            },

            .JUMP_IF_ZERO => pos = if (memory[ptr] == 0) op.param - 1 else pos,
            .JUMP_IF_NONZERO => pos = if (memory[ptr] != 0) op.param - 1 else pos,
        }
    }
    // std.debug.print("{any}\n", .{memory[0..30]});
}

pub fn main() !void {
    const allocator = std.heap.smp_allocator;
    const argv = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, argv);

    var stdout_buf: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch {};

    var stdin_buf: [1024]u8 = undefined;
    var stdin_reader = std.fs.File.stdin().reader(&stdin_buf);
    const stdin = &stdin_reader.interface;

    if (argv.len < 2) {
        try stdout.print("Missing arguments!\nUsage: ./brainfsck-zig <filename>\n", .{});
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

    const ops = try parseOps(content, allocator);
    defer allocator.free(ops);

    try interpret(ops, stdout, stdin);
}
