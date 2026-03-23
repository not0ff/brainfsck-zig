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
const Operation = operations.Operation;

pub const Preprocessor = struct {
    tokens: []Token,

    pub fn init(tokens: []Token) Preprocessor {
        return Preprocessor{
            .tokens = tokens,
        };
    }

    pub fn generateOps(self: *@This(), allocator: std.mem.Allocator) ![]Operation {
        var list: std.ArrayList(Operation) = .empty;
        defer list.deinit(allocator);

        var i: usize = 0;
        while (i < self.tokens.len) : (i += 1) {
            const token = self.tokens[i];
            var op = getOperation(token);
            switch (token) {
                .INC, .DEC, .MOVE_RIGHT, .MOVE_LEFT => |t| {
                    var r: u8 = 0;
                    while (i + r < self.tokens.len and self.tokens[i] == self.tokens[i + r]) {
                        if ((r >= 255) and
                            (t == .DEC or t == .INC)) break;
                        r += 1;
                    }
                    i += r - 1;
                    switch (t) {
                        .INC => op.inc.val = r,
                        .DEC => op.dec.val = r,
                        .MOVE_RIGHT => op.move_right.len = r,
                        .MOVE_LEFT => op.move_left.len = r,
                        else => unreachable,
                    }
                },
                else => {},
            }
            try list.append(allocator, op);
        }

        const ops = try list.toOwnedSlice(allocator);
        try patchLoops(ops, allocator);

        return ops;
    }

    fn patchLoops(ops: []Operation, allocator: std.mem.Allocator) !void {
        var stack: std.ArrayList(usize) = .empty;
        defer stack.deinit(allocator);

        var pos: usize = 0;
        while (pos < ops.len) : (pos += 1) {
            var op = &ops[pos];

            switch (op.*) {
                .loop_start => try stack.append(allocator, pos),
                .loop_end => {
                    if (stack.items.len == 0) return error.UnclosedLoop;
                    if (stack.pop()) |jump| {
                        var jump_op = &ops[jump];
                        switch (jump_op.*) {
                            .loop_start => {
                                jump_op.loop_start.pos = pos + 1;
                                op.loop_end.pos = jump;
                            },
                            else => unreachable,
                        }
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
        var op: Operation = undefined;
        switch (token) {
            .MOVE_RIGHT => op = .{ .move_right = operations.MoveRight{} },
            .MOVE_LEFT => op = .{ .move_left = operations.MoveLeft{} },
            .INC => op = .{ .inc = operations.Inc{} },
            .DEC => op = .{ .dec = operations.Dec{} },
            .OUTPUT => op = .{ .output = operations.Output{} },
            .INPUT => op = .{ .input = operations.Input{} },
            .LOOP_START => op = .{ .loop_start = operations.LoopStart{} },
            .LOOP_END => op = .{ .loop_end = operations.LoopEnd{} },
        }
        return op;
    }
};
