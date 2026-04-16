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
const Operation = @import("operations.zig").Operation;

pub const AssemblyWriter = struct {
    operations: []Operation,
    writer: *std.Io.Writer,

    pub fn init(ops: []Operation, writer: *std.Io.Writer) AssemblyWriter {
        return AssemblyWriter{ .operations = ops, .writer = writer };
    }

    pub fn writeAll(self: AssemblyWriter) !void {
        try self.writer.writeAll(
            \\format ELF64 executable
            \\entry _start
            \\
        );
        try self.writer.writeAll(out_macro);
        try self.writer.writeAll(in_macro);

        try self.writer.writeAll(
            \\segment readable writeable
            \\mem: rb 30000
            \\
        );
        try self.writer.writeAll(
            \\segment executable
            \\_start:
            \\mov rbx, mem
            \\
        );

        try self.writeOperations();
        try self.writer.writeAll(exit_call);
    }

    pub fn writeOperations(self: AssemblyWriter) !void {
        var w = self.writer;
        for (self.operations, 0..) |op, pos| {
            const arg0 = op.args[0];
            switch (op._type) {
                .MoveRight => try w.print("add rbx, {}\n", .{arg0}),
                .MoveLeft => try w.print("sub rbx, {}\n", .{arg0}),
                .Inc => try w.print("add byte[rbx], {}\n", .{arg0}),
                .Dec => try w.print("sub byte[rbx], {}\n", .{arg0}),
                .ZeroMem => try w.writeAll("mov byte[rbx], 0\n"),
                .Output => try w.writeAll("out rbx\n"),
                .Input => try w.writeAll("in rbx\n"),
                .LoopStart => try w.print(
                    \\loop_start_{}:
                    \\cmp byte [rbx], 0
                    \\jz loop_end_{}
                    \\
                , .{ pos, pos }),
                .LoopEnd => try w.print(
                    \\loop_end_{}:
                    \\cmp byte [rbx], 0
                    \\jnz loop_start_{}
                    \\
                , .{ arg0, arg0 }),
                .NoOp => try w.writeAll("nop\n"),
            }
        }
    }

    const out_macro =
        \\macro out ptr {
        \\  mov rax, 1
        \\  mov rsi, ptr
        \\  mov rdi, 1
        \\  mov rdx, 1
        \\  syscall
        \\}
        \\
    ;
    const in_macro =
        \\macro in ptr {
        \\  mov rax, 0
        \\  mov rsi, ptr
        \\  mov rdi, 0
        \\  mov rdx, 1
        \\  syscall
        \\}
        \\
    ;

    const exit_call =
        \\mov rax, 60
        \\mov rdi, 0
        \\syscall
        \\
    ;
};
