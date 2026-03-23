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
pub const Token = enum {
    MOVE_RIGHT,
    MOVE_LEFT,
    INC,
    DEC,
    OUTPUT,
    INPUT,
    LOOP_START,
    LOOP_END,
};

pub const Operation = union(enum) {
    move_right: MoveRight,
    move_left: MoveLeft,
    inc: Inc,
    dec: Dec,
    output: Output,
    input: Input,
    loop_start: LoopStart,
    loop_end: LoopEnd,
};

pub const MoveRight = struct {
    len: u16 = undefined,
};

pub const MoveLeft = struct {
    len: u16 = undefined,
};

pub const Inc = struct {
    val: u8 = undefined,
};

pub const Dec = struct {
    val: u8 = undefined,
};

pub const Output = struct {};

pub const Input = struct {};

pub const LoopStart = struct {
    pos: usize = undefined,
};

pub const LoopEnd = struct {
    pos: usize = undefined,
};
