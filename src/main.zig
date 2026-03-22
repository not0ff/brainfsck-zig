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
const Allocator = std.mem.Allocator;
const build_options = @import("build_options");

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
    param: Param = 0,
};

fn parseOps(source: []const u8, allocator: std.mem.Allocator) ![]Op {
    var ops: std.ArrayList(Op) = .empty;
    defer ops.deinit(allocator);

    // populate ops list initially
    var i: usize = 0;
    while (i < source.len) : (i += 1) {
        const cmd = getCmd(source[i]) orelse continue;
        var op: Op = .{ .cmd = cmd };
        switch (cmd) {
            .INC, .DEC, .MOVE_LEFT, .MOVE_RIGHT => {
                var streak: Param = 0;
                while (i + streak < source.len and source[i] == source[i + streak]) {
                    // limit + and - ops to 255 for add and sub assembly instructions
                    if ((cmd == .DEC or cmd == .INC) and streak >= 255) break;
                    streak += 1;
                }
                i += streak - 1;
                op.param = streak;
            },
            else => {},
        }
        try ops.append(allocator, op);
    }

    // convert [-] and [+] ops to zero_mem
    i = 0;
    while (i + 3 <= ops.items.len) : (i += 1) {
        if ((ops.items[i].cmd == .JUMP_IF_ZERO) and
            (ops.items[i + 1].cmd == .DEC or ops.items[i + 1].cmd == .INC) and
            (ops.items[i + 2].cmd == .JUMP_IF_NONZERO))
        {
            const zero_op: Op = .{ .cmd = .ZERO_MEM };
            try ops.replaceRange(allocator, i, 3, &[_]Op{zero_op});
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
        switch (op.cmd) {
            .MOVE_RIGHT => ptr += op.param,
            .MOVE_LEFT => ptr -= op.param,
            .INC => memory[ptr] +%= @intCast(op.param % 256),
            .DEC => memory[ptr] -%= @intCast(op.param % 256),
            .ZERO_MEM => memory[ptr] = 0,
            .JUMP_IF_ZERO => pos = if (memory[ptr] == 0) op.param - 1 else pos,
            .JUMP_IF_NONZERO => pos = if (memory[ptr] != 0) op.param - 1 else pos,
            .OUTPUT => try output.writeByte(memory[ptr]),
            .INPUT => {
                try output.flush();
                memory[ptr] = input.takeByte() catch 0;
            },
        }
    }
}

const asm_header =
    \\format ELF64 executable
    \\entry _start
    \\
    \\macro out ptr {
    \\  mov rax, 1
    \\  mov rsi, ptr
    \\  mov rdi, 1
    \\  mov rdx, 1
    \\  syscall
    \\}
    \\
    \\macro in ptr {
    \\  mov rax, 0
    \\  mov rsi, ptr
    \\  mov rdi, 0
    \\  mov rdx, 1
    \\  syscall
    \\}
    \\
    \\segment readable writeable
    \\mem: rb 30000
    \\
    \\segment executable
    \\_start:
    \\mov rbx, mem
    \\
;

const asm_exit =
    \\mov rax, 60
    \\mov rdi, 0
    \\syscall
    \\
;

fn compile(ops: []Op, w: *std.Io.Writer) !void {
    try w.writeAll(asm_header);
    for (ops, 0..) |op, i| {
        switch (op.cmd) {
            .MOVE_RIGHT => try w.print("add rbx, {}\n", .{op.param}),
            .MOVE_LEFT => try w.print("sub rbx, {}\n", .{op.param}),
            .INC => try w.print("add byte[rbx],{}\n", .{op.param}),
            .DEC => try w.print("sub byte[rbx], {}\n", .{op.param}),
            .ZERO_MEM => try w.writeAll("mov byte[rbx], 0\n"),
            .OUTPUT => try w.writeAll("out rbx\n"),
            .INPUT => try w.writeAll("in rbx\n"),
            .JUMP_IF_ZERO => try w.print(
                \\loop_start_{}:
                \\cmp byte [rbx], 0 
                \\jz loop_end_{}
                \\
            , .{ i, i }),
            .JUMP_IF_NONZERO => try w.print(
                \\loop_end_{}:
                \\cmp byte [rbx], 0 
                \\jnz loop_start_{}
                \\
            , .{ op.param, op.param }),
        }
    }
    try w.writeAll(asm_exit);
}

fn readFile(path: []const u8, allocator: Allocator) ![]u8 {
    const file = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
    defer file.close();

    var file_buf: [1024]u8 = undefined;
    var file_reader = file.reader(&file_buf);
    const reader = &file_reader.interface;

    const stat = try file.stat();
    return reader.readAlloc(allocator, stat.size);
}

fn filenameWithExt(path: []const u8, ext: []const u8) ![]const u8 {
    var buf: [128]u8 = undefined;
    var name = std.fs.path.basename(path);
    if (std.mem.lastIndexOfScalar(u8, name, '.')) |i|
        name = name[0..i];
    return std.fmt.bufPrint(&buf, "{s}{s}", .{ name, ext });
}

const Args = struct {
    mode: enum { Interpret, Compile } = undefined,
    filepath: [:0]u8 = undefined,

    const ArgParseError = error{ MissingArgs, InvalidArgs };
    fn parse(self: *Args, argv: [][:0]u8) ArgParseError!void {
        if (argv.len < 3)
            return error.MissingArgs;
        if (std.mem.eql(u8, argv[1], "interpret")) {
            self.mode = .Interpret;
        } else if (std.mem.eql(u8, argv[1], "compile")) {
            self.mode = .Compile;
        } else {
            return error.InvalidArgs;
        }
        self.filepath = argv[2];
    }
};

pub fn main() !void {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const argv = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, argv);

    var stdout_buf: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch {};

    var stdin_buf: [1024]u8 = undefined;
    var stdin_reader = std.fs.File.stdin().reader(&stdin_buf);
    const stdin = &stdin_reader.interface;

    var args: Args = .{};
    args.parse(argv) catch |err| {
        switch (err) {
            error.InvalidArgs => std.log.err("invalid arguments provided!", .{}),
            error.MissingArgs => std.log.err("missing arguments!", .{}),
        }
        try stdout.print("Usage: ./{s} <compile|interpret> <filepath>\n", .{build_options.exe_name});
        return;
    };

    const source = try readFile(args.filepath, allocator);
    defer allocator.free(source);

    const ops = try parseOps(source, allocator);
    defer allocator.free(ops);

    switch (args.mode) {
        .Interpret => {
            try interpret(ops, stdout, stdin);
        },
        .Compile => {
            const filename = try filenameWithExt(args.filepath, ".asm");
            const file = try std.fs.cwd().createFile(filename, .{});
            defer file.close();

            var file_buf: [1024]u8 = undefined;
            var file_writer = file.writer(&file_buf);
            const writer = &file_writer.interface;
            defer writer.flush() catch {};

            try compile(ops, writer);
        },
    }
}
