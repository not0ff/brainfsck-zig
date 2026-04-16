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
const build_options = @import("build_options");
const Operation = @import("operations.zig").Operation;
const Parser = @import("parser.zig").Parser;
const Preprocessor = @import("preprocessor.zig").Preprocessor;
const AssemblyWriter = @import("assembly_gen.zig").AssemblyWriter;

const Args = struct {
    mode: enum { Interpret, Compile } = undefined,
    filepath: [:0]const u8 = undefined,
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const arena = init.arena;
    const allocator = arena.allocator();

    var stdout_buf: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buf);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch {};

    var stdin_buf: [1024]u8 = undefined;
    var stdin_reader = std.Io.File.stdin().reader(io, &stdin_buf);
    const stdin = &stdin_reader.interface;

    const args = parseArgs(init.minimal.args, allocator) catch |err| {
        switch (err) {
            error.InvalidArgs => std.log.err("invalid arguments provided!", .{}),
            error.MissingArgs => std.log.err("missing arguments!", .{}),
            else => std.log.err("cannot parse arguments: {}", .{err}),
        }
        try stdout.print("Usage: ./{s} <compile|interpret> <filepath>\n", .{build_options.exe_name});
        return;
    };

    const source = try readFile(args.filepath, io, allocator);

    const parser: Parser = .init(source);
    const tokens = try parser.parseAll(allocator);

    var preprocessor: Preprocessor = .init(tokens, allocator);
    const ops = try preprocessor.generateOps();

    switch (args.mode) {
        .Interpret => {
            try interpret(ops, stdout, stdin);
        },
        .Compile => {
            const filename = try filenameWithExt(args.filepath, "asm", allocator);
            var file = try std.Io.Dir.cwd().createFile(io, filename, .{});
            defer file.close(io);

            var file_buf: [1024]u8 = undefined;
            var file_writer = file.writer(io, &file_buf);
            const writer = &file_writer.interface;
            defer writer.flush() catch {};

            const asm_writer: AssemblyWriter = .init(ops, writer);
            try asm_writer.writeAll();
        },
    }
}

const ParseArgsError = error{ MissingArgs, InvalidArgs, OutOfMemory, Unexpected };
fn parseArgs(args: std.process.Args, arena: std.mem.Allocator) ParseArgsError!Args {
    const argv = try args.toSlice(arena);
    var parsed = Args{};

    if (argv.len < 3) return error.MissingArgs;
    if (std.mem.eql(u8, argv[1], "interpret")) {
        parsed.mode = .Interpret;
    } else if (std.mem.eql(u8, argv[1], "compile")) {
        parsed.mode = .Compile;
    } else {
        return error.InvalidArgs;
    }
    parsed.filepath = argv[2];
    return parsed;
}

fn readFile(path: []const u8, io: std.Io, allocator: std.mem.Allocator) ![]u8 {
    const file = try std.Io.Dir.cwd().openFile(io, path, .{ .mode = .read_only });
    defer file.close(io);

    var file_buf: [1024]u8 = undefined;
    var file_reader = file.reader(io, &file_buf);
    const reader = &file_reader.interface;

    const stat = try file.stat(io);
    return reader.readAlloc(allocator, stat.size);
}

fn filenameWithExt(path: []const u8, ext: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    var name = std.fs.path.basename(path);
    if (std.mem.findScalarLast(u8, name, '.')) |i|
        name = name[0..i];
    return try std.fmt.allocPrint(allocator, "{s}.{s}", .{ name, ext });
}

fn interpret(ops: []Operation, output: *std.Io.Writer, input: *std.Io.Reader) !void {
    var memory: [30_000]u8 = undefined;
    @memset(&memory, 0);

    var ptr: usize = 0;
    var pos: usize = 0;
    while (pos < ops.len) : (pos += 1) {
        const op = ops[pos];
        const arg0 = op.args[0];
        switch (op._type) {
            .MoveRight => ptr += arg0,
            .MoveLeft => ptr -= arg0,
            .Inc => memory[ptr] +%= @intCast(arg0),
            .Dec => memory[ptr] -%= @intCast(arg0),
            .ZeroMem => memory[ptr] = 0,
            .LoopStart => pos = if (memory[ptr] == 0) arg0 - 1 else pos,
            .LoopEnd => pos = if (memory[ptr] != 0) arg0 - 1 else pos,
            .Output => try output.writeByte(memory[ptr]),
            .Input => {
                try output.flush();
                memory[ptr] = input.takeByte() catch 0;
            },
            .NoOp => {},
        }
    }
}
