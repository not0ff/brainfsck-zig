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
const operations = @import("operations.zig");
const Token = operations.Token;
const OpType = operations.OpType;
const Operation = operations.Operation;

pub const Preprocessor = struct {
    tokens: []Token,
    allocator: std.mem.Allocator,
    operations: std.ArrayList(Operation) = .empty,

    pub fn init(tokens: []Token, allocator: std.mem.Allocator) Preprocessor {
        return Preprocessor{
            .tokens = tokens,
            .allocator = allocator,
        };
    }

    pub fn generateOps(self: *Preprocessor) ![]Operation {
        var i: usize = 0;
        while (i < self.tokens.len) : (i += 1) {
            const token = self.tokens[i];
            var op = getOperation(token);
            switch (op._type) {
                .Inc, .Dec, .MoveRight, .MoveLeft => |t| {
                    var r: u16 = 0;
                    while (i + r < self.tokens.len and self.tokens[i] == self.tokens[i + r]) {
                        if ((r >= 255) and
                            (t == .Dec or t == .Inc)) break;
                        r += 1;
                    }
                    i += r - 1;
                    op.args[0] = r;
                },
                else => {},
            }
            try self.operations.append(self.allocator, op);
        }

        try self.addZeroMem();
        try self.patchLoops();

        return self.operations.toOwnedSlice(self.allocator);
    }

    // fn addCopyLoops(self: *Preprocessor) !void {
    //     const ops = &self.operations.items;

    //     var i: usize = 0;
    //     while (i < ops.len) : (i += 1) {
    //         if (ops.*[i]._type != .LoopStart) continue;

    //         while (i < ops.len) : (i += 1) {
    //             if (ops.*[i]._type != .)
    //         }
    //     }
    // }

    fn addZeroMem(self: *Preprocessor) !void {
        const ops = &self.operations.items;

        var i: usize = 0;
        while (i + 2 < ops.len) : (i += 1) {
            if (ops.*[i]._type == .LoopStart and
                (ops.*[i + 1]._type == .Inc or ops.*[i + 1]._type == .Dec) and
                (ops.*[i + 1].args[0] == 1) and
                ops.*[i + 2]._type == .LoopEnd)
            {
                const zeromem: Operation = .{ ._type = .ZeroMem };
                try self.operations.replaceRange(self.allocator, i, 3, &[_]Operation{zeromem});
            }
        }
    }

    fn patchLoops(self: *Preprocessor) !void {
        var stack: std.ArrayList(usize) = .empty;
        defer stack.deinit(self.allocator);

        const ops = self.operations.items;

        var pos: usize = 0;
        while (pos < self.operations.items.len) : (pos += 1) {
            var op = &ops[pos];

            switch (op._type) {
                .LoopStart => try stack.append(self.allocator, pos),
                .LoopEnd => {
                    if (stack.items.len == 0) return error.UnclosedLoop;
                    if (stack.pop()) |startPos| {
                        var loop_start = &ops[startPos];

                        if (loop_start._type != .LoopStart) unreachable;

                        loop_start.args[0] = @intCast(pos + 1);
                        op.args[0] = @intCast(startPos);
                    }
                },
                else => {},
            }
        }
        if (stack.items.len != 0) {
            return error.UnclosedLoop;
        }
    }

    fn getOperation(token: Token) Operation {
        var op: Operation = .{ ._type = .NoOp };
        switch (token) {
            .MOVE_RIGHT => op._type = .MoveRight,
            .MOVE_LEFT => op._type = .MoveLeft,
            .INC => op._type = .Inc,
            .DEC => op._type = .Dec,
            .OUTPUT => op._type = .Output,
            .INPUT => op._type = .Input,
            .LOOP_START => op._type = .LoopStart,
            .LOOP_END => op._type = .LoopEnd,
        }
        return op;
    }
};
