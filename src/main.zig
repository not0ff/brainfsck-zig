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

const OpPos = usize;

const JumpOp = struct {
    cmd: Cmd,
    dest: OpPos,
};

const GenOp = struct {
    cmd: Cmd,
    repeat: usize,
};

const Op = struct {
    op: union(enum) {
        gen: GenOp,
        jump: JumpOp,
    },
};

fn parseOps(bytes: []u8, allocator: std.mem.Allocator) ![]Op {
    var ops: std.ArrayList(Op) = .empty;
    defer ops.deinit(allocator);

    var jump_stack: std.ArrayList(OpPos) = .empty;
    defer jump_stack.deinit(allocator);

    var pos: OpPos = 0;
    var i: usize = 0;
    while (i < bytes.len) : (i += 1) {
        const cmd = std.enums.fromInt(Cmd, bytes[i]) orelse continue;
        var op: Op = undefined;
        switch (cmd) {
            .JUMP_IF_ZERO => {
                try jump_stack.append(allocator, pos);
                op = .{ .op = .{ .jump = JumpOp{ .cmd = .JUMP_IF_ZERO, .dest = 0 } } };
            },
            .JUMP_IF_NONZERO => {
                if (jump_stack.items.len == 0) return error.UnclosedLoop;
                if (jump_stack.pop()) |jump| {
                    switch (ops.items[jump].op) {
                        .jump => |*j| {
                            j.dest = pos;
                            op = .{ .op = .{ .jump = JumpOp{ .cmd = .JUMP_IF_NONZERO, .dest = jump } } };
                        },
                        .gen => unreachable,
                    }
                }
            },
            else => {
                var rep: usize = 0;
                while (i + rep < bytes.len and bytes[i] == bytes[i + rep]) {
                    rep += 1;
                }
                i += rep - 1;
                op = .{ .op = .{ .gen = .{ .cmd = cmd, .repeat = rep } } };
            },
        }
        try ops.append(allocator, op);
        pos += 1;
    }

    if (jump_stack.items.len != 0) {
        return error.UnclosedLoop;
    }

    return ops.toOwnedSlice(allocator);
}

fn interpret(ops: []Op, output: *std.Io.Writer, input: *std.Io.Reader) !void {
    var memory: [30_000]u8 = undefined;
    @memset(&memory, 0);

    var ptr: usize = 0;
    var pos: OpPos = 0;
    while (pos < ops.len) : (pos += 1) {
        switch (ops[pos].op) {
            .gen => |op| switch (op.cmd) {
                .MOVE_RIGHT => ptr = (ptr + op.repeat) % memory.len,
                .MOVE_LEFT => ptr = (ptr + memory.len - (op.repeat % memory.len)) % memory.len,
                .INC => memory[ptr] +%= @intCast(op.repeat % 256),
                .DEC => memory[ptr] -%= @intCast(op.repeat % 256),
                .OUTPUT => {
                    for (0..op.repeat) |_| {
                        try output.writeByte(memory[ptr]);
                    }
                    try output.flush();
                },
                // doesn't matter whether repeated
                .INPUT => memory[ptr] = input.takeByte() catch 0,

                else => return error.InvalidOp,
            },
            .jump => |op| switch (op.cmd) {
                .JUMP_IF_ZERO => pos = if (memory[ptr] == 0) op.dest else pos,
                .JUMP_IF_NONZERO => pos = if (memory[ptr] != 0) op.dest else pos,
                else => return error.InvalidOp,
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
