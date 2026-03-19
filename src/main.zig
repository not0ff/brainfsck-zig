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
    value: usize,
};

fn parseOps(bytes: []u8, allocator: std.mem.Allocator) ![]Op {
    var ops_list: std.ArrayList(Op) = .empty;
    defer ops_list.deinit(allocator);

    var jump_stack: std.ArrayList(usize) = .empty;
    defer jump_stack.deinit(allocator);

    var pos: usize = 0;
    var i: usize = 0;
    while (i < bytes.len) : (i += 1) {
        const cmd = std.enums.fromInt(Cmd, bytes[i]) orelse continue;
        var op: Op = .{ .cmd = cmd, .value = 0 };

        switch (cmd) {
            .JUMP_IF_ZERO => {
                try jump_stack.append(allocator, pos);
            },
            .JUMP_IF_NONZERO => {
                if (jump_stack.items.len == 0) return error.UnclosedLoop;
                const jump = jump_stack.pop().?;

                ops_list.items[jump].value = pos;
                op.value = jump;
            },
            else => {
                var c: usize = 0;
                while (i + c < bytes.len and bytes[i] == bytes[i + c]) {
                    c += 1;
                }
                i += c - 1;
                op.value = c;
            },
        }
        try ops_list.append(allocator, op);
        pos += 1;
    }
    if (jump_stack.items.len != 0) {
        return error.UnclosedLoop;
    }

    return try ops_list.toOwnedSlice(allocator);
}

fn interpret(ops: []Op, output: *std.Io.Writer, input: *std.Io.Reader) !void {
    var memory: [30_000]u8 = undefined;
    @memset(&memory, 0);

    var p: usize = 0;
    var pos: usize = 0;
    while (pos < ops.len) : (pos += 1) {
        const op = ops[pos];
        switch (op.cmd) {
            .INC => memory[p] +%= @intCast(op.value % 256),
            .DEC => memory[p] -%= @intCast(op.value % 256),
            .MOVE_RIGHT => {
                p = (p + op.value) % memory.len;
            },
            .MOVE_LEFT => {
                p = (p + memory.len - (op.value % memory.len)) % memory.len;
            },
            .JUMP_IF_ZERO => {
                if (memory[p] == 0) pos = op.value;
            },
            .JUMP_IF_NONZERO => {
                if (memory[p] != 0) pos = op.value;
            },
            .INPUT => {
                for (0..op.value) |_| {
                    memory[p] = input.takeByte() catch 0;
                }
            },
            .OUTPUT => {
                for (0..op.value) |_| {
                    try output.writeByte(memory[p]);
                }
                try output.flush();
            },
        }
    }
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
