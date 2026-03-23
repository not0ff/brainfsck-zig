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

pub fn main() !void {
    var arena: std.heap.ArenaAllocator = .init(std.heap.page_allocator);
    defer arena.deinit();

    const allocator = arena.allocator();

    var stdout_buf: [1024]u8 = undefined;
    var stdout_writer = std.fs.File.stdout().writer(&stdout_buf);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch {};

    var stdin_buf: [1024]u8 = undefined;
    var stdin_reader = std.fs.File.stdin().reader(&stdin_buf);
    const stdin = &stdin_reader.interface;

    const argv = try std.process.argsAlloc(allocator);
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

    const parser: Parser = .init(source);
    const tokens = try parser.parseAll(allocator);

    var preprocessor: Preprocessor = .init(tokens);
    const ops = try preprocessor.generateOps(allocator);

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

            const asm_writer: AssemblyWriter = .init(ops, writer);
            try asm_writer.writeAll();
        },
    }
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

fn readFile(path: []const u8, allocator: std.mem.Allocator) ![]u8 {
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

fn interpret(ops: []Operation, output: *std.Io.Writer, input: *std.Io.Reader) !void {
    var memory: [30_000]u8 = undefined;
    @memset(&memory, 0);

    var ptr: usize = 0;
    var pos: usize = 0;
    while (pos < ops.len) : (pos += 1) {
        const op = ops[pos];
        switch (op) {
            .move_right => ptr += op.move_right.len,
            .move_left => ptr -= op.move_left.len,
            .inc => memory[ptr] +%= op.inc.val,
            .dec => memory[ptr] -%= op.dec.val,
            // .ZERO_MEM => memory[ptr] = 0,
            .loop_start => pos = if (memory[ptr] == 0) op.loop_start.pos - 1 else pos,
            .loop_end => pos = if (memory[ptr] != 0) op.loop_end.pos - 1 else pos,
            .output => try output.writeByte(memory[ptr]),
            .input => {
                try output.flush();
                memory[ptr] = input.takeByte() catch 0;
            },
        }
    }
}
