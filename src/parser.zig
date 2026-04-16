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
const Token = @import("operations.zig").Token;

pub const Parser = struct {
    bytes: []u8,
    index: usize = 0,

    pub fn init(bytes: []u8) Parser {
        return Parser{ .bytes = bytes };
    }

    pub fn next(self: *Parser) Token {
        while (self.index <= self.bytes.len) : (self.index += 1) {
            if (parseToken(self.bytes[self.index])) |t| {
                return t;
            }
        }
    }

    pub fn parseAll(self: Parser, allocator: std.mem.Allocator) ![]Token {
        var list: std.ArrayList(Token) = .empty;
        defer list.deinit(allocator);

        for (self.bytes) |b| {
            if (parseToken(b)) |t|
                try list.append(allocator, t);
        }

        return list.toOwnedSlice(allocator);
    }

    fn parseToken(char: u8) ?Token {
        return std.enums.fromInt(Token, char);
    }
};
