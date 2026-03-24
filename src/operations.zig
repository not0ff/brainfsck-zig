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

// https://esolangs.org/wiki/Brainfuck#Language_overview
pub const Token = enum(u8) {
    MOVE_RIGHT = '>',
    MOVE_LEFT = '<',
    INC = '+',
    DEC = '-',
    OUTPUT = '.',
    INPUT = ',',
    LOOP_START = '[',
    LOOP_END = ']',
};

pub const OpType = enum {
    NoOp,
    MoveRight,
    MoveLeft,
    Inc,
    Dec,
    Output,
    Input,
    LoopStart,
    LoopEnd,
    ZeroMem,
};

pub const Operation = struct {
    _type: OpType,
    args: [3]u16 = undefined,
};
