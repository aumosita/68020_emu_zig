const std = @import("std");

pub const Instruction = struct {
    opcode: u16,
    size: u8,
    mnemonic: Mnemonic,
    src: Operand,
    dst: Operand,
    data_size: DataSize,
    control_reg: ?u16 = null,
    extension_word: ?u16 = null,
    is_to_control: bool = false,
    is_extb: bool = false,
    pub fn init() Instruction {
        return .{
            .opcode = 0, .size = 2, .mnemonic = .UNKNOWN,
            .src = .{ .None = {} }, .dst = .{ .None = {} },
            .data_size = .Long, .control_reg = null,
            .extension_word = null,
            .is_to_control = false, .is_extb = false,
        };
    }
};

pub const DataSize = enum { Byte, Word, Long };

pub const Mnemonic = enum {
    MOVE, MOVEA, MOVEM, MOVEP, MOVEQ, LEA, PEA, EXG, SWAP,
    ADD, ADDA, ADDI, ADDQ, ADDX, SUB, SUBA, SUBI, SUBQ, SUBX,
    MULU, MULS, DIVU, DIVS, NEG, NEGX, CLR, EXT, EXTB,
    AND, ANDI, OR, ORI, EOR, EORI, NOT,
    ASL, ASR, LSL, LSR, ROL, ROR, ROXL, ROXR,
    BCHG, BCLR, BSET, BTST, BFCHG,
    ABCD, SBCD, NBCD,
    BFTST, BFSET, BFCLR, BFEXTS, BFEXTU, BFINS, BFFFO,
    CAS, CAS2, PACK, UNPK, CHK2, CMP2, CALLM, RTM, RTD, TRAPcc, BKPT,
    MULS_L, MULU_L, DIVS_L, DIVU_L,
    BRA, BSR, Bcc, DBcc, Scc, JMP, JSR, RTS, RTR, RTE, NOP,
    TRAP, TRAPV, CHK, TAS, ILLEGAL, RESET, STOP, MOVEC, MOVEUSP,
    CMP, CMPA, CMPI, CMPM, TST, LINK, UNLK, LINEA, COPROC, UNKNOWN,
};

pub const IndexReg = struct { reg: u3, is_addr: bool, is_long: bool, scale: u4 };

pub const Operand = union(enum) {
    None: void, DataReg: u3, AddrReg: u3, Immediate8: u8, Immediate16: u16, Immediate32: u32,
    Address: u32, AddrIndirect: u3, AddrPostInc: u3, AddrPreDec: u3,
    AddrDisplace: struct { reg: u3, displacement: i16 },
    BitField: struct { base: u32, offset: i32, width: u5 },
    ComplexEA: struct { base_reg: ?u3, is_pc_relative: bool, index_reg: ?IndexReg, base_disp: i32, outer_disp: i32, is_mem_indirect: bool, is_post_indexed: bool },
};

pub const Decoder = struct {
    pub fn init() Decoder { return .{}; }
    pub fn decode(self: *const Decoder, opcode: u16, pc: u32, read_word: *const fn(u32) u16) !Instruction {
        const h = (opcode >> 12) & 0xF;
        return switch (h) {
            0x0 => try self.decodeGroup0(opcode, pc, read_word),
            0x1, 0x2, 0x3 => try self.decodeMove(opcode, pc, read_word),
            0x4 => try self.decodeGroup4(opcode, pc, read_word),
            0x5 => try self.decodeGroup5(opcode, pc, read_word),
            0x6 => try self.decodeBranch(opcode, pc, read_word),
            0x7 => self.decodeMoveq(opcode, pc),
            0x8 => try self.decodeGroup8(opcode, pc, read_word),
            0x9, 0xD => try self.decodeArithmetic(opcode, pc, read_word, @truncate(h)),
            0xA => self.decodeLineA(opcode, pc),
            0xB => try self.decodeGroupB(opcode, pc, read_word),
            0xC => try self.decodeGroupC(opcode, pc, read_word),
            0xE => try self.decodeShiftRotate(opcode, pc, read_word),
            0xF => self.decodeCoprocessor(opcode, pc),
            else => try self.decodeLegacy(opcode, pc, read_word),
        };
    }
    fn decodeCoprocessor(_: *const Decoder, o: u16, _: u32) Instruction {
        var i = Instruction.init();
        i.opcode = o;
        i.mnemonic = .COPROC;
        i.size = 2;
        return i;
    }
    fn decodeLineA(_: *const Decoder, o: u16, _: u32) Instruction {
        var i = Instruction.init();
        i.opcode = o;
        i.mnemonic = .LINEA;
        i.size = 2;
        return i;
    }
    fn decodeMoveq(_: *const Decoder, o: u16, _: u32) Instruction {
        var i = Instruction.init(); i.opcode = o; i.mnemonic = .MOVEQ; i.dst = .{ .DataReg = @truncate((o >> 9) & 7) }; i.src = .{ .Immediate8 = @truncate(o & 0xFF) }; return i;
    }
    fn decodeBranch(_: *const Decoder, o: u16, pc: u32, rw: *const fn(u32) u16) !Instruction {
        var cpc = pc + 2; var i = Instruction.init(); i.opcode = o; const cond: u8 = @truncate((o >> 8) & 0xF); const d8: i8 = @bitCast(@as(u8, @truncate(o & 0xFF)));
        if (cond == 0) i.mnemonic = .BRA else if (cond == 1) i.mnemonic = .BSR else i.mnemonic = .Bcc;
        if (d8 == 0) { i.src = .{ .Immediate16 = rw(cpc) }; cpc += 2; }
        else if (d8 == -1) { i.src = .{ .Immediate32 = (@as(u32, rw(cpc)) << 16) | rw(cpc + 2) }; cpc += 4; }
        else i.src = .{ .Immediate8 = @bitCast(d8) };
        i.size = @truncate(cpc - pc); return i;
    }
    fn decodeMove(self: *const Decoder, o: u16, pc: u32, rw: *const fn(u32) u16) !Instruction {
        var cpc = pc + 2; var i = Instruction.init(); i.opcode = o; i.mnemonic = .MOVE;
        const h = (o >> 12) & 0xF; i.data_size = if (h == 1) .Byte else if (h == 3) .Word else .Long;
        i.src = try self.decodeEA(@truncate(o & 7), @truncate((o >> 3) & 7), &cpc, rw, i.data_size);
        i.dst = try self.decodeEA(@truncate((o >> 6) & 7), @truncate((o >> 9) & 7), &cpc, rw, i.data_size);
        if (i.dst == .AddrReg) i.mnemonic = .MOVEA;
        i.size = @truncate(cpc - pc); return i;
    }
    fn decodeGroup5(self: *const Decoder, o: u16, pc: u32, rw: *const fn(u32) u16) !Instruction {
        var cpc = pc + 2; var i = Instruction.init(); i.opcode = o;
        const low: u8 = @truncate(o & 0xFF);
        if (low == 0xFA or low == 0xFB or low == 0xFC) {
            i.mnemonic = .TRAPcc;
            if (low == 0xFA) {
                i.src = .{ .Immediate16 = rw(cpc) };
                cpc += 2;
            } else if (low == 0xFB) {
                i.src = .{ .Immediate32 = (@as(u32, rw(cpc)) << 16) | rw(cpc + 2) };
                cpc += 4;
            }
        }
        else if ((o & 0xF8) == 0xC8) { i.mnemonic = .DBcc; i.dst = .{ .DataReg = @truncate(o & 7) }; i.src = .{ .Immediate16 = rw(cpc) }; cpc += 2; }
        else if (((o >> 6) & 3) == 3) { i.mnemonic = .Scc; i.dst = try self.decodeEA(@truncate((o >> 3) & 7), @truncate(o & 7), &cpc, rw, .Byte); i.data_size = .Byte; }
        else { i.mnemonic = if (((o >> 8) & 1) == 1) .SUBQ else .ADDQ; i.data_size = if (((o >> 6) & 3) == 0) .Byte else if (((o >> 6) & 3) == 1) .Word else .Long;
            var d: u8 = @truncate((o >> 9) & 7); if (d == 0) d = 8; i.src = .{ .Immediate8 = d }; i.dst = try self.decodeEA(@truncate((o >> 3) & 7), @truncate(o & 7), &cpc, rw, i.data_size); }
        i.size = @truncate(cpc - pc); return i;
    }
    fn decodeGroup8(self: *const Decoder, o: u16, pc: u32, rw: *const fn(u32) u16) !Instruction {
        var cpc = pc + 2; var i = Instruction.init(); i.opcode = o;
        if ((o & 0x1F0) == 0x140 or (o & 0x1F0) == 0x180) {
            i.mnemonic = if ((o & 0x1F0) == 0x140) .PACK else .UNPK;
            i.data_size = .Byte;
            const rx: u3 = @truncate((o >> 9) & 7);
            const ry: u3 = @truncate(o & 7);
            i.extension_word = rw(cpc);
            cpc += 2;
            if ((o & 8) != 0) {
                i.src = .{ .AddrPreDec = ry };
                i.dst = .{ .AddrPreDec = rx };
            } else {
                i.src = .{ .DataReg = ry };
                i.dst = .{ .DataReg = rx };
            }
        }
        else if ((o & 0x1F0) == 0x100) { i.mnemonic = .SBCD; i.data_size = .Byte; const rx: u3 = @truncate((o >> 9) & 7); const ry: u3 = @truncate(o & 7); if ((o & 8) != 0) { i.src = .{ .AddrPreDec = ry }; i.dst = .{ .AddrPreDec = rx }; } else { i.src = .{ .DataReg = ry }; i.dst = .{ .DataReg = rx }; } }
        else if (((o >> 6) & 7) == 3 or ((o >> 6) & 7) == 7) { i.mnemonic = if (((o >> 6) & 7) == 3) .DIVU else .DIVS; i.dst = .{ .DataReg = @truncate((o >> 9) & 7) }; i.src = try self.decodeEA(@truncate((o >> 3) & 7), @truncate(o & 7), &cpc, rw, .Word); }
        else { i.mnemonic = .OR; i.data_size = if (((o >> 6) & 3) == 0) .Byte else if (((o >> 6) & 3) == 1) .Word else .Long;
            if (((o >> 8) & 1) == 0) { i.src = try self.decodeEA(@truncate((o >> 3) & 7), @truncate(o & 7), &cpc, rw, i.data_size); i.dst = .{ .DataReg = @truncate((o >> 9) & 7) }; }
            else { i.src = .{ .DataReg = @truncate((o >> 9) & 7) }; i.dst = try self.decodeEA(@truncate((o >> 3) & 7), @truncate(o & 7), &cpc, rw, i.data_size); } }
        i.size = @truncate(cpc - pc); return i;
    }
    fn decodeArithmetic(self: *const Decoder, o: u16, pc: u32, rw: *const fn(u32) u16, h: u4) !Instruction {
        var cpc = pc + 2; var i = Instruction.init(); i.opcode = o; const om = (o >> 6) & 7;
        if ((om & 4) != 0) { i.mnemonic = if (h == 0xD) .ADDA else .SUBA; i.data_size = if ((om & 1) == 0) .Word else .Long; i.src = try self.decodeEA(@truncate((o >> 3) & 7), @truncate(o & 7), &cpc, rw, i.data_size); i.dst = .{ .AddrReg = @truncate((o >> 9) & 7) }; }
        else { i.mnemonic = if (h == 0xD) .ADD else .SUB; i.data_size = if ((om & 3) == 0) .Byte else if ((om & 3) == 1) .Word else .Long;
            if (((om >> 2) & 1) == 0) { i.src = try self.decodeEA(@truncate((o >> 3) & 7), @truncate(o & 7), &cpc, rw, i.data_size); i.dst = .{ .DataReg = @truncate((o >> 9) & 7) }; }
            else { i.src = .{ .DataReg = @truncate((o >> 9) & 7) }; i.dst = try self.decodeEA(@truncate((o >> 3) & 7), @truncate(o & 7), &cpc, rw, i.data_size); } }
        i.size = @truncate(cpc - pc); return i;
    }
    fn decodeGroupB(self: *const Decoder, o: u16, pc: u32, rw: *const fn(u32) u16) !Instruction {
        var cpc = pc + 2; var i = Instruction.init(); i.opcode = o; const om = (o >> 6) & 7;
        const size_bits = (o >> 6) & 3;  // Extract only bits 6-7 for size
        if (((o >> 3) & 7) == 1 and ((o >> 8) & 1) == 1 and size_bits <= 2) { i.mnemonic = .CMPM; i.data_size = if (size_bits == 0) .Byte else if (size_bits == 1) .Word else .Long; }
        else if ((om & 4) != 0) { i.mnemonic = .CMPA; i.data_size = if ((om & 1) == 0) .Word else .Long; i.src = try self.decodeEA(@truncate((o >> 3) & 7), @truncate(o & 7), &cpc, rw, i.data_size); i.dst = .{ .AddrReg = @truncate((o >> 9) & 7) }; }
        else if (((om >> 2) & 1) == 1) { i.mnemonic = .EOR; i.data_size = if ((om & 3) == 0) .Byte else if ((om & 3) == 1) .Word else .Long; i.src = .{ .DataReg = @truncate((o >> 9) & 7) }; i.dst = try self.decodeEA(@truncate((o >> 3) & 7), @truncate(o & 7), &cpc, rw, i.data_size); }
        else { i.mnemonic = .CMP; i.data_size = if (om == 0) .Byte else if (om == 1) .Word else .Long; i.src = try self.decodeEA(@truncate((o >> 3) & 7), @truncate(o & 7), &cpc, rw, i.data_size); i.dst = .{ .DataReg = @truncate((o >> 9) & 7) }; }
        i.size = @truncate(cpc - pc); return i;
    }
    fn decodeGroupC(self: *const Decoder, o: u16, pc: u32, rw: *const fn(u32) u16) !Instruction {
        var cpc = pc + 2; var i = Instruction.init(); i.opcode = o; const om = (o >> 6) & 7;
        if ((o & 0x1F0) == 0x100) { i.mnemonic = .ABCD; i.data_size = .Byte; const rx: u3 = @truncate((o >> 9) & 7); const ry: u3 = @truncate(o & 7); if ((o & 8) != 0) { i.src = .{ .AddrPreDec = ry }; i.dst = .{ .AddrPreDec = rx }; } else { i.src = .{ .DataReg = ry }; i.dst = .{ .DataReg = rx }; } }
        else if (om == 3 or om == 7) { i.mnemonic = if (om == 3) .MULU else .MULS; i.dst = .{ .DataReg = @truncate((o >> 9) & 7) }; i.src = try self.decodeEA(@truncate((o >> 3) & 7), @truncate(o & 7), &cpc, rw, .Word); }
        else if (om >= 4 and om <= 6) { i.mnemonic = .EXG; i.data_size = .Long; }
        else { i.mnemonic = .AND; i.data_size = if ((om & 3) == 0) .Byte else if ((om & 3) == 1) .Word else .Long;
            if (((o >> 8) & 1) == 0) { i.src = try self.decodeEA(@truncate((o >> 3) & 7), @truncate(o & 7), &cpc, rw, i.data_size); i.dst = .{ .DataReg = @truncate((o >> 9) & 7) }; }
            else { i.src = .{ .DataReg = @truncate((o >> 9) & 7) }; i.dst = try self.decodeEA(@truncate((o >> 3) & 7), @truncate(o & 7), &cpc, rw, i.data_size); } }
        i.size = @truncate(cpc - pc); return i;
    }
    fn decodeShiftRotate(self: *const Decoder, o: u16, pc: u32, rw: *const fn(u32) u16) !Instruction {
        var cpc = pc + 2; var i = Instruction.init(); i.opcode = o;
        if ((o & 0xF8C0) == 0xE8C0) {
            const bt = (o >> 8) & 7; i.mnemonic = switch (bt) { 0 => .BFTST, 1 => .BFEXTU, 2 => .BFCHG, 3 => .BFEXTS, 4 => .BFCLR, 5 => .BFFFO, 6 => .BFSET, 7 => .BFINS, else => .UNKNOWN };
            i.src = .{ .Immediate16 = rw(cpc) }; cpc += 2; i.dst = try self.decodeEA(@truncate((o >> 3) & 7), @truncate(o & 7), &cpc, rw, .Long); i.size = @truncate(cpc - pc); return i;
        }
        if (((o >> 6) & 3) == 3) {
            const st = (o >> 9) & 3; const dir = (o >> 8) & 1; i.mnemonic = switch (st) { 0 => if (dir == 0) .ASR else .ASL, 1 => if (dir == 0) .LSR else .LSL, 2 => if (dir == 0) .ROXR else .ROXL, 3 => if (dir == 0) .ROR else .ROL, else => .UNKNOWN };
            i.dst = try self.decodeEA(@truncate((o >> 3) & 7), @truncate(o & 7), &cpc, rw, .Word); i.data_size = .Word;
        } else {
            const st = (o >> 3) & 3; const dir = (o >> 8) & 1; i.mnemonic = switch (st) { 0 => if (dir == 0) .ASR else .ASL, 1 => if (dir == 0) .LSR else .LSL, 2 => if (dir == 0) .ROXR else .ROXL, 3 => if (dir == 0) .ROR else .ROL, else => .UNKNOWN };
            i.data_size = if (((o >> 6) & 3) == 0) .Byte else if (((o >> 6) & 3) == 1) .Word else .Long;
            if (((o >> 5) & 1) == 0) { var d: u8 = @truncate((o >> 9) & 7); if (d == 0) d = 8; i.src = .{ .Immediate8 = d }; } else i.src = .{ .DataReg = @truncate((o >> 9) & 7) };
            i.dst = .{ .DataReg = @truncate(o & 7) };
        }
        i.size = @truncate(cpc - pc); return i;
    }
    fn decodeGroup0(self: *const Decoder, o: u16, pc: u32, rw: *const fn(u32) u16) !Instruction {
        var cpc = pc + 2; var i = Instruction.init(); i.opcode = o;
        // 68020 module support instructions.
        if ((o & 0xFFC0) == 0x06C0) {
            const mode: u3 = @truncate((o >> 3) & 7);
            const reg: u3 = @truncate(o & 7);
            if (mode == 0 or mode == 1) {
                i.mnemonic = .RTM;
                i.dst = if (mode == 0) .{ .DataReg = reg } else .{ .AddrReg = reg };
                i.size = @truncate(cpc - pc);
                return i;
            }
            if (mode == 3 or mode == 4) return error.IllegalInstruction;
            if (mode == 7 and reg > 3) return error.IllegalInstruction;
            i.mnemonic = .CALLM;
            i.src = .{ .Immediate8 = @truncate(rw(cpc)) };
            cpc += 2;
            i.dst = try self.decodeEA(mode, reg, &cpc, rw, .Long);
            i.size = @truncate(cpc - pc);
            return i;
        }
        // Immediate operations to CCR/SR special forms.
        if (o == 0x003C or o == 0x023C or o == 0x0A3C) {
            const so = (o >> 9) & 7;
            i.mnemonic = switch (so) { 0 => .ORI, 1 => .ANDI, 5 => .EORI, else => .UNKNOWN };
            i.data_size = .Byte;
            i.src = .{ .Immediate16 = rw(cpc) };
            cpc += 2;
            i.dst = .{ .None = {} };
            i.size = @truncate(cpc - pc);
            return i;
        }
        if (o == 0x007C or o == 0x027C or o == 0x0A7C) {
            const so = (o >> 9) & 7;
            i.mnemonic = switch (so) { 0 => .ORI, 1 => .ANDI, 5 => .EORI, else => .UNKNOWN };
            i.data_size = .Word;
            i.src = .{ .Immediate16 = rw(cpc) };
            cpc += 2;
            i.dst = .{ .None = {} };
            i.size = @truncate(cpc - pc);
            return i;
        }
        if (o == 0x0CFC or o == 0x0EFC) { i.mnemonic = .CAS2; i.data_size = if (o == 0x0CFC) .Word else .Long; i.src = .{ .Immediate16 = rw(cpc) }; cpc += 2; i.dst = .{ .Immediate16 = rw(cpc) }; cpc += 2; i.size = @truncate(cpc - pc); return i; }
        if ((o & 0x01C0) == 0x00C0) {
            const sz = (o >> 9) & 0x3;
            if (sz <= 2) {
                const ext = rw(cpc);
                cpc += 2;
                i.extension_word = ext;
                i.mnemonic = if ((ext & 0x0800) != 0) .CHK2 else .CMP2;
                i.data_size = if (sz == 0) .Byte else if (sz == 1) .Word else .Long;
                i.src = try self.decodeEA(@truncate((o >> 3) & 7), @truncate(o & 7), &cpc, rw, i.data_size);
                i.size = @truncate(cpc - pc);
                return i;
            }
        }
        if ((o & 0x0138) == 0x0108 and ((o >> 6) & 7) >= 4) {
            const size_bits = (o >> 6) & 3;
            i.mnemonic = .MOVEP; i.data_size = if (size_bits == 1) .Word else .Long; const rd: u3 = @truncate((o >> 9) & 7); const ra: u3 = @truncate(o & 7); const d = @as(i16, @bitCast(rw(cpc))); cpc += 2;
            const dir_bit = (o >> 7) & 1;
            if (dir_bit == 0) { i.src = .{ .AddrDisplace = .{ .reg = ra, .displacement = d } }; i.dst = .{ .DataReg = rd }; }
            else { i.src = .{ .DataReg = rd }; i.dst = .{ .AddrDisplace = .{ .reg = ra, .displacement = d } }; }
            i.size = @truncate(cpc - pc); return i;
        }
        if ((o & 0xFFC0) == 0x0AC0 or (o & 0xFFC0) == 0x0CC0 or (o & 0xFFC0) == 0x0EC0) {
            const sz = (o >> 9) & 3; if (sz >= 1) { i.mnemonic = .CAS; i.data_size = if (sz == 1) .Byte else if (sz == 2) .Word else .Long; i.src = .{ .Immediate16 = rw(cpc) }; cpc += 2; i.dst = try self.decodeEA(@truncate((o >> 3) & 7), @truncate(o & 7), &cpc, rw, i.data_size); i.size = @truncate(cpc - pc); return i; }
        }
        if ((o & 0xF1C0) == 0x0100 or (o & 0xF1C0) == 0x0140 or (o & 0xF1C0) == 0x0180 or (o & 0xF1C0) == 0x01C0) {
            const bo = (o >> 6) & 3; i.mnemonic = switch (bo) { 0 => .BTST, 1 => .BCHG, 2 => .BCLR, 3 => .BSET, else => .UNKNOWN }; i.src = .{ .DataReg = @truncate((o >> 9) & 7) }; i.dst = try self.decodeEA(@truncate((o >> 3) & 7), @truncate(o & 7), &cpc, rw, .Long);
        } else if ((o & 0xFFC0) == 0x0800 or (o & 0xFFC0) == 0x0840 or (o & 0xFFC0) == 0x0880 or (o & 0xFFC0) == 0x08C0) {
            const bo = (o >> 6) & 3; i.mnemonic = switch (bo) { 0 => .BTST, 1 => .BCHG, 2 => .BCLR, 3 => .BSET, else => .UNKNOWN }; i.src = .{ .Immediate8 = @truncate(rw(cpc)) }; cpc += 2; i.dst = try self.decodeEA(@truncate((o >> 3) & 7), @truncate(o & 7), &cpc, rw, .Byte);
        } else if ((o & 0xFF00) == 0x0000 or (o & 0xFF00) == 0x0200 or (o & 0xFF00) == 0x0400 or (o & 0xFF00) == 0x0600 or (o & 0xFF00) == 0x0A00 or (o & 0xFF00) == 0x0C00) {
            const so = (o >> 9) & 7; i.mnemonic = switch (so) { 0 => .ORI, 1 => .ANDI, 2 => .SUBI, 3 => .ADDI, 5 => .EORI, 6 => .CMPI, else => .UNKNOWN };
            const sb = (o >> 6) & 3; i.data_size = if (sb == 0) .Byte else if (sb == 1) .Word else .Long; i.src = try self.decodeImmediate(&cpc, rw, i.data_size); i.dst = try self.decodeEA(@truncate((o >> 3) & 7), @truncate(o & 7), &cpc, rw, i.data_size);
        }
        i.size = @truncate(cpc - pc); return i;
    }
    fn decodeGroup4(self: *const Decoder, o: u16, pc: u32, rw: *const fn(u32) u16) !Instruction {
        var cpc = pc + 2; var i = Instruction.init(); i.opcode = o;
        if (o == 0x4E71) i.mnemonic = .NOP else if (o == 0x4E75) i.mnemonic = .RTS else if (o == 0x4E73) i.mnemonic = .RTE else if (o == 0x4E77) i.mnemonic = .RTR
        else if (o == 0x4E70) i.mnemonic = .RESET
        else if (o == 0x4E76) i.mnemonic = .TRAPV
        else if (o == 0x4E72) { i.mnemonic = .STOP; i.src = .{ .Immediate16 = rw(cpc) }; cpc += 2; }
        else if (o == 0x4E74) { i.mnemonic = .RTD; i.src = .{ .Immediate16 = rw(cpc) }; cpc += 2; }
        else if (o == 0x4E7A or o == 0x4E7B) { i.mnemonic = .MOVEC; const ext = rw(cpc); cpc += 2; i.control_reg = ext & 0xFFF; i.is_to_control = (o == 0x4E7B); const rn = @as(u3, @truncate((ext >> 12) & 7)); if (((ext >> 15) & 1) != 0) i.src = .{ .AddrReg = rn } else i.src = .{ .DataReg = rn }; }
        else if ((o & 0xFFF0) == 0x4E60) {
            i.mnemonic = .MOVEUSP;
            const r: u3 = @truncate(o & 7);
            if ((o & 0x8) != 0) {
                // MOVE USP,An
                i.src = .{ .None = {} };
                i.dst = .{ .AddrReg = r };
            } else {
                // MOVE An,USP
                i.src = .{ .AddrReg = r };
                i.dst = .{ .None = {} };
            }
        }
        else if ((o & 0xFFF8) == 0x4848) { i.mnemonic = .BKPT; i.src = .{ .Immediate8 = @truncate(o & 7) }; }
        else if ((o & 0xFFF0) == 0x4E40) { i.mnemonic = .TRAP; i.src = .{ .Immediate8 = @truncate(o & 0xF) }; }
        else if ((o & 0xFFF8) == 0x4E50) { i.mnemonic = .LINK; i.dst = .{ .AddrReg = @truncate(o & 7) }; i.src = .{ .Immediate16 = rw(cpc) }; cpc += 2; }
        else if ((o & 0xFFF8) == 0x4E58) { i.mnemonic = .UNLK; i.dst = .{ .AddrReg = @truncate(o & 7) }; }
        else if ((o & 0xFF00) == 0x4E00) { if ((o & 0xFFC0) == 0x4E80) i.mnemonic = .JSR else if ((o & 0xFFC0) == 0x4EC0) i.mnemonic = .JMP; i.dst = try self.decodeEA(@truncate((o >> 3) & 7), @truncate(o & 7), &cpc, rw, .Long); }
        else if ((o & 0xFFC0) == 0x4C00) {
            const ext = rw(cpc);
            cpc += 2;
            i.extension_word = ext;
            if ((ext & 0x0800) != 0) {
                i.mnemonic = if ((ext & 0x0400) != 0) .MULS_L else .MULU_L;
            } else {
                i.mnemonic = if ((ext & 0x0400) != 0) .DIVS_L else .DIVU_L;
            }
            i.src = try self.decodeEA(@truncate((o >> 3) & 7), @truncate(o & 7), &cpc, rw, .Long);
            i.dst = .{ .DataReg = @truncate(ext & 7) };
        }
        else if ((o & 0xFFC0) == 0x4800) { i.mnemonic = .NBCD; i.data_size = .Byte; i.dst = try self.decodeEA(@truncate((o >> 3) & 7), @truncate(o & 7), &cpc, rw, .Byte); }
        else if ((o & 0xFF00) == 0x4000 or (o & 0xFF00) == 0x4200 or (o & 0xFF00) == 0x4400 or (o & 0xFF00) == 0x4600) { const so = (o >> 9) & 7; i.mnemonic = switch (so) { 0 => .NEGX, 1 => .CLR, 2 => .NEG, 3 => .NOT, else => .UNKNOWN }; const sb = (o >> 6) & 3; i.data_size = if (sb == 0) .Byte else if (sb == 1) .Word else .Long; i.dst = try self.decodeEA(@truncate((o >> 3) & 7), @truncate(o & 7), &cpc, rw, i.data_size); }
        else if (o == 0x4AFC) { i.mnemonic = .ILLEGAL; }
        else if ((o & 0xFF00) == 0x4A00) { if ((o & 0xFFC0) == 0x4AC0) { i.mnemonic = .TAS; i.data_size = .Byte; i.dst = try self.decodeEA(@truncate((o >> 3) & 7), @truncate(o & 7), &cpc, rw, .Byte); } else { i.mnemonic = .TST; const sb = (o >> 6) & 3; i.data_size = if (sb == 0) .Byte else if (sb == 1) .Word else .Long; i.dst = try self.decodeEA(@truncate((o >> 3) & 7), @truncate(o & 7), &cpc, rw, i.data_size); } }
        else if ((o & 0xFB80) == 0x4880) { i.mnemonic = .MOVEM; i.data_size = if ((o & 0x40) != 0) .Long else .Word; i.src = .{ .Immediate16 = rw(cpc) }; cpc += 2; i.dst = try self.decodeEA(@truncate((o >> 3) & 7), @truncate(o & 7), &cpc, rw, i.data_size); }
        else if ((o & 0xFFC0) == 0x4840) { if (((o >> 3) & 7) == 0) { i.mnemonic = .SWAP; i.dst = .{ .DataReg = @truncate(o & 7) }; } else { i.mnemonic = .PEA; i.src = try self.decodeEA(@truncate((o >> 3) & 7), @truncate(o & 7), &cpc, rw, .Long); } }
        else if ((o & 0xFFC0) == 0x4880 or (o & 0xFFC0) == 0x48C0 or (o & 0xFFC0) == 0x49C0) { i.mnemonic = .EXT; i.dst = .{ .DataReg = @truncate(o & 7) }; const om = (o >> 6) & 7; if (om == 7) { i.data_size = .Long; i.is_extb = true; } else if ((o & 0x40) != 0) { i.data_size = .Long; i.is_extb = false; } else { i.data_size = .Word; i.is_extb = false; } }
        else if ((o & 0xF1C0) == 0x4180) { i.mnemonic = .CHK; i.data_size = .Word; i.dst = .{ .DataReg = @truncate((o >> 9) & 7) }; i.src = try self.decodeEA(@truncate((o >> 3) & 7), @truncate(o & 7), &cpc, rw, .Word); }
        i.size = @truncate(cpc - pc); return i;
    }
    fn decodeLegacy(_: *const Decoder, o: u16, _: u32, _: *const fn(u32) u16) !Instruction {
        var i = Instruction.init(); i.opcode = o; i.mnemonic = .UNKNOWN; return i;
    }
    fn decodeEA(self: *const Decoder, mode: u3, reg: u3, pc: *u32, rw: *const fn(u32) u16, size: DataSize) !Operand {
        switch (mode) {
            0 => return .{ .DataReg = reg }, 1 => return .{ .AddrReg = reg }, 2 => return .{ .AddrIndirect = reg }, 3 => return .{ .AddrPostInc = reg }, 4 => return .{ .AddrPreDec = reg },
            5 => { const d = @as(i16, @bitCast(rw(pc.*))); pc.* += 2; return .{ .AddrDisplace = .{ .reg = reg, .displacement = d } }; },
            6 => return try self.decodeFullExtension(reg, false, pc, rw),
            7 => switch (reg) {
                0 => { const a = @as(i16, @bitCast(rw(pc.*))); pc.* += 2; return .{ .Address = @bitCast(@as(i32, a)) }; },
                1 => { const h = rw(pc.*); const l = rw(pc.* + 2); pc.* += 4; return .{ .Address = (@as(u32, h) << 16) | l }; },
                2 => { const d = @as(i16, @bitCast(rw(pc.*))); pc.* += 2; return .{ .ComplexEA = .{ .base_reg = null, .is_pc_relative = true, .index_reg = null, .base_disp = d, .outer_disp = 0, .is_mem_indirect = false, .is_post_indexed = false } }; },
                3 => return try self.decodeFullExtension(0, true, pc, rw), 4 => return try self.decodeImmediate(pc, rw, size), else => return error.IllegalInstruction,
            },
        }
    }
    fn decodeFullExtension(_: *const Decoder, reg: u3, is_pc: bool, pc: *u32, rw: *const fn(u32) u16) !Operand {
        const ext = rw(pc.*); pc.* += 2;
        if ((ext & 0x0100) == 0) {
            const is_addr = (ext & 0x8000) != 0; const idx = @as(u3, @truncate((ext >> 12) & 7)); const is_l = (ext & 0x0800) != 0; const sc = @as(u4, @truncate(@as(u32, 1) << @as(u5, @truncate((ext >> 9) & 3)))); const d = @as(i8, @bitCast(@as(u8, @truncate(ext & 0xFF))));
            return .{ .ComplexEA = .{ .base_reg = if (is_pc) null else reg, .is_pc_relative = is_pc, .index_reg = IndexReg{ .reg = idx, .is_addr = is_addr, .is_long = is_l, .scale = sc }, .base_disp = d, .outer_disp = 0, .is_mem_indirect = false, .is_post_indexed = false } };
        } else {
            const bs = (ext & 0x0080) != 0; const is = (ext & 0x0040) != 0; const bds = (ext >> 4) & 3; const iis = ext & 7; var bd: i32 = 0; if (bds == 2) { bd = @as(i16, @bitCast(rw(pc.*))); pc.* += 2; } else if (bds == 3) { bd = @bitCast((@as(u32, rw(pc.*)) << 16) | rw(pc.* + 2)); pc.* += 4; }
            var ir: ?IndexReg = null; if (!is) { const isa = (ext & 0x8000) != 0; const idx = @as(u3, @truncate((ext >> 12) & 7)); const isl = (ext & 0x0800) != 0; const sc = @as(u4, @truncate(@as(u32, 1) << @as(u5, @truncate((ext >> 9) & 3)))); ir = IndexReg{ .reg = idx, .is_addr = isa, .is_long = isl, .scale = sc }; }
            var od: i32 = 0; const ods = iis & 3; if (ods == 2) { od = @as(i16, @bitCast(rw(pc.*))); pc.* += 2; } else if (ods == 3) { od = @bitCast((@as(u32, rw(pc.*)) << 16) | rw(pc.* + 2)); pc.* += 4; }
            return .{ .ComplexEA = .{ .base_reg = if (bs) null else reg, .is_pc_relative = is_pc, .index_reg = ir, .base_disp = bd, .outer_disp = od, .is_mem_indirect = (iis != 0), .is_post_indexed = (iis & 4) != 0 } };
        }
    }
    fn decodeImmediate(_: *const Decoder, pc: *u32, rw: *const fn(u32) u16, size: DataSize) !Operand {
        switch (size) { .Byte => { const v = rw(pc.*); pc.* += 2; return .{ .Immediate8 = @truncate(v) }; }, .Word => { const v = rw(pc.*); pc.* += 2; return .{ .Immediate16 = v }; }, .Long => { const h = rw(pc.*); const l = rw(pc.* + 2); pc.* += 4; return .{ .Immediate32 = (@as(u32, h) << 16) | l }; } }
    }
};
