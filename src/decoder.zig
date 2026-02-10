const std = @import("std");

pub const Instruction = struct {
    opcode: u16,
    size: u8,  // 명령어 크기 (바이트 단위, 확장 워드 포함)
    mnemonic: Mnemonic,
    src: Operand,
    dst: Operand,
    data_size: DataSize,
    
    pub fn init() Instruction {
        return .{
            .opcode = 0,
            .size = 2,
            .mnemonic = .NOP,
            .src = .{ .None = {} },
            .dst = .{ .None = {} },
            .data_size = .Long,
        };
    }
};

pub const DataSize = enum {
    Byte,
    Word,
    Long,
};

pub const Mnemonic = enum {
    // 데이터 이동
    MOVE, MOVEA, MOVEM, MOVEP, MOVEQ,
    LEA, PEA,
    EXG, SWAP,
    
    // 산술 연산
    ADD, ADDA, ADDI, ADDQ, ADDX,
    SUB, SUBA, SUBI, SUBQ, SUBX,
    MULU, MULS,
    DIVU, DIVS,
    NEG, NEGX,
    CLR,
    EXT, EXTB,
    
    // 논리 연산
    AND, ANDI, OR, ORI, EOR, EORI,
    NOT,
    
    // 시프트 및 로테이트
    ASL, ASR, LSL, LSR,
    ROL, ROR, ROXL, ROXR,
    
    // 비트 조작
    BCHG, BCLR, BSET, BTST,
    
    // BCD (Binary Coded Decimal)
    ABCD, SBCD, NBCD,
    
    // 프로그램 제어
    BRA, BSR,
    Bcc,
    DBcc,
    Scc,
    JMP, JSR,
    RTS, RTR, RTE,
    NOP,
    
    // 시스템 제어
    TRAP, TRAPV,
    CHK,
    ILLEGAL,
    RESET, STOP,
    
    // 비교
    CMP, CMPA, CMPI, CMPM,
    TST,
    
    // 스택 연산
    LINK, UNLK,
    
    // 비트 필드 (68020)
    BFCHG, BFCLR, BFEXTS, BFEXTU, BFFFO, BFINS, BFSET, BFTST,
    
    UNKNOWN,
};

// 68020 인덱스 레지스터 타입 (명명된 타입으로 추출)
pub const IndexReg = struct {
    reg: u3,
    is_addr: bool,      // Dn (false) or An (true)
    is_long: bool,      // Word (false) or Long (true)
    scale: u4,          // 1, 2, 4, 8
};

pub const Operand = union(enum) {
    None: void,
    DataReg: u3,           // D0-D7
    AddrReg: u3,           // A0-A7
    Immediate8: u8,
    Immediate16: u16,
    Immediate32: u32,
    Address: u32,          // 절대 주소 (xxx.W 또는 xxx.L)
    AddrIndirect: u3,      // (An)
    AddrPostInc: u3,       // (An)+
    AddrPreDec: u3,        // -(An)
    AddrDisplace: struct { // d16(An) - 68000 기본 변위 모드
        reg: u3,
        displacement: i16,
    },
    
    // 비트 필드 사양 (68020)
    BitField: struct {
        base: u32, // placeholder
        offset: i32,
        width: u5,
    },
    
    // 68020 통합 어드레싱 모드 (Brief & Full Extension Format)
    ComplexEA: struct {
        base_reg: ?u3,          // An (null이면 suppressed)
        is_pc_relative: bool,   // PC relative?
        index_reg: ?IndexReg,   // 명명된 타입 사용
        base_disp: i32,         // bd
        outer_disp: i32,        // od
        is_mem_indirect: bool,  // Memory indirect?
        is_post_indexed: bool,  // Post-indexed (true) or Pre-indexed (false)
    },
};

pub const Decoder = struct {
    pub fn init() Decoder {
        return .{};
    }
    
    pub fn decode(self: *const Decoder, opcode: u16, pc: u32, read_word: *const fn(u32) u16) !Instruction {
        var current_pc = pc + 2;
        var inst = Instruction.init();
        inst.opcode = opcode;
        
        const high4 = (opcode >> 12) & 0xF;
        
        switch (high4) {
            0x0 => {
                if ((opcode & 0xF1C0) == 0x0100 or (opcode & 0xF1C0) == 0x0140 or (opcode & 0xF1C0) == 0x0180 or (opcode & 0xF1C0) == 0x01C0) {
                    const bit_op = (opcode >> 6) & 0x3;
                    inst.mnemonic = switch (bit_op) {
                        0 => .BTST, 1 => .BCHG, 2 => .BCLR, 3 => .BSET,
                        else => .UNKNOWN,
                    };
                    inst.src = .{ .DataReg = @truncate((opcode >> 9) & 0x7) };
                    const ea_mode = (opcode >> 3) & 0x7;
                    const ea_reg = opcode & 0x7;
                    inst.dst = try self.decodeEA(@truncate(ea_mode), @truncate(ea_reg), &current_pc, read_word, .Long);
                } else if ((opcode & 0xFFC0) == 0x0800 or (opcode & 0xFFC0) == 0x0840 or (opcode & 0xFFC0) == 0x0880 or (opcode & 0xFFC0) == 0x08C0) {
                    const bit_op = (opcode >> 6) & 0x3;
                    inst.mnemonic = switch (bit_op) {
                        0 => .BTST, 1 => .BCHG, 2 => .BCLR, 3 => .BSET,
                        else => .UNKNOWN,
                    };
                    const ext = read_word(current_pc);
                    current_pc += 2;
                    inst.src = .{ .Immediate8 = @truncate(ext) };
                    const ea_mode = (opcode >> 3) & 0x7;
                    const ea_reg = opcode & 0x7;
                    inst.dst = try self.decodeEA(@truncate(ea_mode), @truncate(ea_reg), &current_pc, read_word, .Byte);
                } else if ((opcode & 0xFF00) == 0x0000 or (opcode & 0xFF00) == 0x0200 or (opcode & 0xFF00) == 0x0400 or (opcode & 0xFF00) == 0x0600 or (opcode & 0xFF00) == 0x0A00 or (opcode & 0xFF00) == 0x0C00) {
                    const subop = (opcode >> 9) & 0x7;
                    inst.mnemonic = switch (subop) {
                        0 => .ORI, 1 => .ANDI, 2 => .SUBI, 3 => .ADDI, 5 => .EORI, 6 => .CMPI,
                        else => .UNKNOWN,
                    };
                    const size_bits = (opcode >> 6) & 0x3;
                    inst.data_size = switch (size_bits) {
                        0 => .Byte, 1 => .Word, 2 => .Long, else => .Long,
                    };
                    inst.src = try self.decodeImmediate(&current_pc, read_word, inst.data_size);
                    const ea_mode = (opcode >> 3) & 0x7;
                    const ea_reg = opcode & 0x7;
                    inst.dst = try self.decodeEA(@truncate(ea_mode), @truncate(ea_reg), &current_pc, read_word, inst.data_size);
                } else {
                    inst.mnemonic = .UNKNOWN;
                }
            },
            
            0x1, 0x2, 0x3 => {
                inst.mnemonic = .MOVE;
                inst.data_size = switch (high4) {
                    0x1 => .Byte, 0x3 => .Word, 0x2 => .Long,
                    else => .Long,
                };
                const src_mode = opcode & 0x7;
                const src_reg = (opcode >> 3) & 0x7;
                inst.src = try self.decodeEA(@truncate(src_mode), @truncate(src_reg), &current_pc, read_word, inst.data_size);
                
                const dst_mode = (opcode >> 6) & 0x7;
                const dst_reg = (opcode >> 9) & 0x7;
                inst.dst = try self.decodeEA(@truncate(dst_mode), @truncate(dst_reg), &current_pc, read_word, inst.data_size);
            },
            
            0x4 => {
                if (opcode == 0x4E71) {
                    inst.mnemonic = .NOP;
                } else if (opcode == 0x4E75) {
                    inst.mnemonic = .RTS;
                } else if (opcode == 0x4E73) {
                    inst.mnemonic = .RTE;
                } else if (opcode == 0x4E77) {
                    inst.mnemonic = .RTR;
                } else if ((opcode & 0xFFF0) == 0x4E40) {
                    inst.mnemonic = .TRAP;
                    inst.src = .{ .Immediate8 = @truncate(opcode & 0xF) };
                } else if ((opcode & 0xFFF8) == 0x4E50) {
                    inst.mnemonic = .LINK;
                    inst.dst = .{ .AddrReg = @truncate(opcode & 0x7) };
                    const disp = @as(i16, @bitCast(read_word(current_pc)));
                    current_pc += 2;
                    inst.src = .{ .Immediate16 = @bitCast(disp) };
                } else if ((opcode & 0xFFF8) == 0x4E58) {
                    inst.mnemonic = .UNLK;
                    inst.dst = .{ .AddrReg = @truncate(opcode & 0x7) };
                } else if ((opcode & 0xFF00) == 0x4E00) {
                    const ea_mode = (opcode >> 3) & 0x7;
                    const ea_reg = opcode & 0x7;
                    if ((opcode & 0xFFC0) == 0x4E80) {
                        inst.mnemonic = .JSR;
                    } else if ((opcode & 0xFFC0) == 0x4EC0) {
                        inst.mnemonic = .JMP;
                    }
                    inst.dst = try self.decodeEA(@truncate(ea_mode), @truncate(ea_reg), &current_pc, read_word, .Long);
                } else if ((opcode & 0xFFC0) == 0x4C00) {
                    const ext = read_word(current_pc);
                    current_pc += 2;
                    const is_mul = (ext & 0x0800) != 0;
                    const is_signed = (ext & 0x0400) != 0;
                    if (is_mul) { inst.mnemonic = if (is_signed) .MULS else .MULU; }
                    else { inst.mnemonic = if (is_signed) .DIVS else .DIVU; }
                    const ea_mode = (opcode >> 3) & 0x7;
                    const ea_reg = opcode & 0x7;
                    inst.src = try self.decodeEA(@truncate(ea_mode), @truncate(ea_reg), &current_pc, read_word, .Long);
                    inst.dst = .{ .DataReg = @truncate(ext & 0x7) };
                } else if ((opcode & 0xFF00) == 0x4000 or (opcode & 0xFF00) == 0x4200 or (opcode & 0xFF00) == 0x4400 or (opcode & 0xFF00) == 0x4600) {
                    const subop = (opcode >> 9) & 0x7;
                    inst.mnemonic = switch (subop) {
                        0 => .NEGX, 1 => .CLR, 2 => .NEG, 3 => .NOT,
                        else => .UNKNOWN,
                    };
                    const size_bits = (opcode >> 6) & 0x3;
                    inst.data_size = switch (size_bits) {
                        0 => .Byte, 1 => .Word, 2 => .Long, else => .Long,
                    };
                    const ea_mode = (opcode >> 3) & 0x7;
                    const ea_reg = opcode & 0x7;
                    inst.dst = try self.decodeEA(@truncate(ea_mode), @truncate(ea_reg), &current_pc, read_word, inst.data_size);
                } else if ((opcode & 0xFF00) == 0x4A00) {
                    inst.mnemonic = .TST;
                    const size_bits = (opcode >> 6) & 0x3;
                    inst.data_size = switch (size_bits) {
                        0 => .Byte, 1 => .Word, 2 => .Long, else => .Long,
                    };
                    const ea_mode = (opcode >> 3) & 0x7;
                    const ea_reg = opcode & 0x7;
                    inst.dst = try self.decodeEA(@truncate(ea_mode), @truncate(ea_reg), &current_pc, read_word, inst.data_size);
                } else if ((opcode & 0xFB80) == 0x4880) {
                    inst.mnemonic = .MOVEM;
                    inst.data_size = if ((opcode & 0x40) != 0) .Long else .Word;
                    const mask = read_word(current_pc);
                    current_pc += 2;
                    inst.src = .{ .Immediate16 = mask };
                    const ea_mode = (opcode >> 3) & 0x7;
                    const ea_reg = opcode & 0x7;
                    inst.dst = try self.decodeEA(@truncate(ea_mode), @truncate(ea_reg), &current_pc, read_word, inst.data_size);
                } else if ((opcode & 0xFFC0) == 0x4840) {
                    const ea_mode = (opcode >> 3) & 0x7;
                    const ea_reg = opcode & 0x7;
                    if (ea_mode == 0) {
                        inst.mnemonic = .SWAP;
                        inst.dst = .{ .DataReg = @truncate(ea_reg) };
                    } else {
                        inst.mnemonic = .PEA;
                        inst.src = try self.decodeEA(@truncate(ea_mode), @truncate(ea_reg), &current_pc, read_word, .Long);
                    }
                } else if ((opcode & 0xFFC0) == 0x4880 or (opcode & 0xFFC0) == 0x48C0) {
                    inst.mnemonic = .EXT;
                    inst.dst = .{ .DataReg = @truncate(opcode & 0x7) };
                    inst.data_size = if ((opcode & 0x40) != 0) .Long else .Word;
                } else {
                    inst.mnemonic = .UNKNOWN;
                }
            },
            
            0x5 => {
                const mode = (opcode >> 3) & 0x7;
                const reg = opcode & 0x7;
                const size_bits = (opcode >> 6) & 0x3;
                if ((opcode & 0x00F8) == 0x00C8) {
                    inst.mnemonic = .DBcc;
                    inst.dst = .{ .DataReg = @truncate(reg) };
                    const disp = @as(i16, @bitCast(read_word(current_pc)));
                    current_pc += 2;
                    inst.src = .{ .Immediate16 = @bitCast(disp) };
                } else if (size_bits == 0x3) {
                    inst.mnemonic = .Scc;
                    inst.dst = try self.decodeEA(@truncate(mode), @truncate(reg), &current_pc, read_word, .Byte);
                    inst.data_size = .Byte;
                } else {
                    const is_sub = ((opcode >> 8) & 1) == 1;
                    inst.mnemonic = if (is_sub) .SUBQ else .ADDQ;
                    inst.data_size = switch (size_bits) {
                        0 => .Byte, 1 => .Word, 2 => .Long, else => .Long,
                    };
                    var data: u8 = @truncate((opcode >> 9) & 0x7);
                    if (data == 0) data = 8;
                    inst.src = .{ .Immediate8 = data };
                    inst.dst = try self.decodeEA(@truncate(mode), @truncate(reg), &current_pc, read_word, inst.data_size);
                }
            },
            
            0x6 => {
                const condition: u8 = @truncate((opcode >> 8) & 0xF);
                const disp8: i8 = @bitCast(@as(u8, @truncate(opcode & 0xFF)));
                if (condition == 0x0) { inst.mnemonic = .BRA; }
                else if (condition == 0x1) { inst.mnemonic = .BSR; }
                else { inst.mnemonic = .Bcc; }
                
                if (disp8 == 0) {
                    const disp16 = @as(i16, @bitCast(read_word(current_pc)));
                    current_pc += 2;
                    inst.src = .{ .Immediate16 = @bitCast(disp16) };
                } else if (disp8 == -1) {
                    const high = read_word(current_pc);
                    const low = read_word(current_pc + 2);
                    current_pc += 4;
                    inst.src = .{ .Immediate32 = (@as(u32, high) << 16) | low };
                } else {
                    inst.src = .{ .Immediate8 = @bitCast(disp8) };
                }
            },
            
            0x7 => {
                inst.mnemonic = .MOVEQ;
                inst.dst = .{ .DataReg = @truncate((opcode >> 9) & 0x7) };
                inst.src = .{ .Immediate8 = @truncate(opcode & 0xFF) };
            },
            
            0x8 => {
                const opmode = (opcode >> 6) & 0x7;
                if ((opcode & 0x1F0) == 0x100) {
                    inst.mnemonic = .SBCD;
                } else if (opmode == 0x3 or opmode == 0x7) {
                    inst.mnemonic = if (opmode == 0x3) .DIVU else .DIVS;
                    inst.dst = .{ .DataReg = @truncate((opcode >> 9) & 0x7) };
                    const ea_mode = (opcode >> 3) & 0x7;
                    const ea_reg = opcode & 0x7;
                    inst.src = try self.decodeEA(@truncate(ea_mode), @truncate(ea_reg), &current_pc, read_word, .Word);
                } else {
                    inst.mnemonic = .OR;
                    const size_bits = (opcode >> 6) & 0x3;
                    inst.data_size = switch (size_bits) {
                        0 => .Byte, 1 => .Word, 2 => .Long, else => .Long,
                    };
                    const direction = (opcode >> 8) & 1;
                    const reg = (opcode >> 9) & 0x7;
                    const ea_mode = (opcode >> 3) & 0x7;
                    const ea_reg = opcode & 0x7;
                    if (direction == 0) {
                        inst.src = try self.decodeEA(@truncate(ea_mode), @truncate(ea_reg), &current_pc, read_word, inst.data_size);
                        inst.dst = .{ .DataReg = @truncate(reg) };
                    } else {
                        inst.src = .{ .DataReg = @truncate(reg) };
                        inst.dst = try self.decodeEA(@truncate(ea_mode), @truncate(ea_reg), &current_pc, read_word, inst.data_size);
                    }
                }
            },
            
            0x9, 0xD => {
                const is_add = high4 == 0xD;
                const opmode = (opcode >> 6) & 0x7;
                const reg = (opcode >> 9) & 0x7;
                const ea_mode = (opcode >> 3) & 0x7;
                const ea_reg = opcode & 0x7;
                if ((opmode & 0x4) != 0) {
                    inst.mnemonic = if (is_add) .ADDA else .SUBA;
                    inst.data_size = if ((opmode & 1) == 0) .Word else .Long;
                    inst.src = try self.decodeEA(@truncate(ea_mode), @truncate(ea_reg), &current_pc, read_word, inst.data_size);
                    inst.dst = .{ .AddrReg = @truncate(reg) };
                } else {
                    inst.mnemonic = if (is_add) .ADD else .SUB;
                    inst.data_size = switch (opmode & 0x3) {
                        0 => .Byte, 1 => .Word, 2 => .Long, else => .Long,
                    };
                    const direction = (opmode >> 2) & 1;
                    if (direction == 0) {
                        inst.src = try self.decodeEA(@truncate(ea_mode), @truncate(ea_reg), &current_pc, read_word, inst.data_size);
                        inst.dst = .{ .DataReg = @truncate(reg) };
                    } else {
                        inst.src = .{ .DataReg = @truncate(reg) };
                        inst.dst = try self.decodeEA(@truncate(ea_mode), @truncate(ea_reg), &current_pc, read_word, inst.data_size);
                    }
                }
            },
            
            0xB => {
                const opmode = (opcode >> 6) & 0x7;
                const reg = (opcode >> 9) & 0x7;
                const ea_mode = (opcode >> 3) & 0x7;
                const ea_reg = opcode & 0x7;
                if ((opmode & 0x4) != 0) {
                    inst.mnemonic = .CMPA;
                    inst.data_size = if ((opmode & 1) == 0) .Word else .Long;
                    inst.src = try self.decodeEA(@truncate(ea_mode), @truncate(ea_reg), &current_pc, read_word, inst.data_size);
                    inst.dst = .{ .AddrReg = @truncate(reg) };
                } else if (opmode >= 0x4) {
                    inst.mnemonic = .EOR;
                    inst.data_size = switch (opmode & 0x3) {
                        0 => .Byte, 1 => .Word, 2 => .Long, else => .Long,
                    };
                    inst.src = .{ .DataReg = @truncate(reg) };
                    inst.dst = try self.decodeEA(@truncate(ea_mode), @truncate(ea_reg), &current_pc, read_word, inst.data_size);
                } else {
                    inst.mnemonic = .CMP;
                    inst.data_size = switch (opmode & 0x3) {
                        0 => .Byte, 1 => .Word, 2 => .Long, else => .Long,
                    };
                    inst.src = try self.decodeEA(@truncate(ea_mode), @truncate(ea_reg), &current_pc, read_word, inst.data_size);
                    inst.dst = .{ .DataReg = @truncate(reg) };
                }
            },
            
            0xC => {
                const opmode = (opcode >> 6) & 0x7;
                const reg = (opcode >> 9) & 0x7;
                const ea_mode = (opcode >> 3) & 0x7;
                const ea_reg = opcode & 0x7;
                if ((opcode & 0x1F0) == 0x100) { inst.mnemonic = .ABCD; }
                else if (opmode == 0x3 or opmode == 0x7) {
                    inst.mnemonic = if (opmode == 0x3) .MULU else .MULS;
                    inst.dst = .{ .DataReg = @truncate(reg) };
                    inst.src = try self.decodeEA(@truncate(ea_mode), @truncate(ea_reg), &current_pc, read_word, .Word);
                } else if ((opcode & 0x1F0) == 0x140 or (opcode & 0x1F0) == 0x148 or (opcode & 0x1F0) == 0x188) { inst.mnemonic = .EXG; }
                else {
                    inst.mnemonic = .AND;
                    inst.data_size = switch (opmode & 0x3) {
                        0 => .Byte, 1 => .Word, 2 => .Long, else => .Long,
                    };
                    const direction = (opmode >> 2) & 1;
                    if (direction == 0) {
                        inst.src = try self.decodeEA(@truncate(ea_mode), @truncate(ea_reg), &current_pc, read_word, inst.data_size);
                        inst.dst = .{ .DataReg = @truncate(reg) };
                    } else {
                        inst.src = .{ .DataReg = @truncate(reg) };
                        inst.dst = try self.decodeEA(@truncate(ea_mode), @truncate(ea_reg), &current_pc, read_word, inst.data_size);
                    }
                }
            },
            
            0xE => {
                if ((opcode & 0xFFC0) == 0xEC00 or (opcode & 0xFFC0) == 0xE800 or (opcode & 0xFFC0) == 0xE400 or (opcode & 0xFFC0) == 0xE000) {
                    const subop = (opcode >> 8) & 0x7;
                    inst.mnemonic = switch (subop) {
                        0 => .BFTST, 1 => .BFEXTU, 2 => .BFCHG, 3 => .BFEXTS,
                        4 => .BFCLR, 5 => .BFFFO, 6 => .BFSET, 7 => .BFINS,
                        else => .UNKNOWN,
                    };
                    const ea_mode = (opcode >> 3) & 0x7;
                    const ea_reg = opcode & 0x7;
                    const ext = read_word(current_pc);
                    current_pc += 2;
                    _ = ext;
                    inst.dst = try self.decodeEA(@truncate(ea_mode), @truncate(ea_reg), &current_pc, read_word, .Long);
                } else {
                    const ir = (opcode >> 5) & 1;
                    const size_bits = (opcode >> 6) & 0x3;
                    if (size_bits == 0x3) {
                        const direction = (opcode >> 8) & 1;
                        const shift_type = (opcode >> 9) & 0x3;
                        inst.mnemonic = switch (shift_type) {
                            0 => if (direction == 1) .ASL else .ASR,
                            1 => if (direction == 1) .LSL else .LSR,
                            2 => if (direction == 1) .ROXL else .ROXR,
                            3 => if (direction == 1) .ROL else .ROR,
                            else => .UNKNOWN,
                        };
                        inst.data_size = .Word;
                        const ea_mode = (opcode >> 3) & 0x7;
                        const ea_reg = opcode & 0x7;
                        inst.dst = try self.decodeEA(@truncate(ea_mode), @truncate(ea_reg), &current_pc, read_word, .Word);
                        inst.src = .{ .Immediate8 = 1 };
                    } else {
                        const direction = (opcode >> 8) & 1;
                        const shift_type = (opcode >> 3) & 0x3;
                        inst.mnemonic = switch (shift_type) {
                            0 => if (direction == 1) .ASL else .ASR,
                            1 => if (direction == 1) .LSL else .LSR,
                            2 => if (direction == 1) .ROXL else .ROXR,
                            3 => if (direction == 1) .ROL else .ROR,
                            else => .UNKNOWN,
                        };
                        inst.data_size = switch (size_bits) {
                            0 => .Byte, 1 => .Word, 2 => .Long, else => .Long,
                        };
                        inst.dst = .{ .DataReg = @truncate(opcode & 0x7) };
                        if (ir == 0) {
                            var count: u8 = @truncate((opcode >> 9) & 0x7);
                            if (count == 0) count = 8;
                            inst.src = .{ .Immediate8 = count };
                        } else {
                            inst.src = .{ .DataReg = @truncate((opcode >> 9) & 0x7) };
                        }
                    }
                }
            },
            else => inst.mnemonic = .UNKNOWN,
        }
        inst.size = @truncate(current_pc - pc);
        return inst;
    }

    fn decodeEA(self: *const Decoder, mode: u3, reg: u3, pc: *u32, read_word: *const fn(u32) u16, size: DataSize) !Operand {
        switch (mode) {
            0 => return .{ .DataReg = reg },
            1 => return .{ .AddrReg = reg },
            2 => return .{ .AddrIndirect = reg },
            3 => return .{ .AddrPostInc = reg },
            4 => return .{ .AddrPreDec = reg },
            5 => {
                // d16(An) - 68000 기본 변위 모드
                const d16 = @as(i16, @bitCast(read_word(pc.*)));
                pc.* += 2;
                return .{ .AddrDisplace = .{ .reg = reg, .displacement = d16 } };
            },
            6 => return try self.decodeFullExtension(reg, false, pc, read_word),
            7 => switch (reg) {
                0 => {
                    const addr = @as(i16, @bitCast(read_word(pc.*)));
                    pc.* += 2;
                    return .{ .Address = @bitCast(@as(i32, addr)) };
                },
                1 => {
                    const high = read_word(pc.*);
                    const low = read_word(pc.* + 2);
                    pc.* += 4;
                    return .{ .Address = (@as(u32, high) << 16) | low };
                },
                2 => {
                    const d16 = @as(i16, @bitCast(read_word(pc.*)));
                    pc.* += 2;
                    return .{ .ComplexEA = .{
                        .base_reg = null, .is_pc_relative = true, .index_reg = null,
                        .base_disp = d16, .outer_disp = 0, .is_mem_indirect = false, .is_post_indexed = false,
                    }};
                },
                3 => return try self.decodeFullExtension(0, true, pc, read_word),
                4 => return try self.decodeImmediate(pc, read_word, size),
                else => return error.IllegalInstruction,
            },
        }
    }

    fn decodeFullExtension(self: *const Decoder, reg: u3, is_pc: bool, pc: *u32, read_word: *const fn(u32) u16) !Operand {
        _ = self;
        const ext = read_word(pc.*);
        pc.* += 2;
        if ((ext & 0x0100) == 0) {
            // Brief Extension Format
            const is_addr = (ext & 0x8000) != 0;
            const idx_reg = @as(u3, @truncate((ext >> 12) & 0x7));
            const is_long = (ext & 0x0800) != 0;
            const scale = @as(u4, @truncate(@as(u32, 1) << @as(u5, @truncate((ext >> 9) & 0x3))));
            const disp = @as(i8, @bitCast(@as(u8, @truncate(ext & 0xFF))));
            return .{ .ComplexEA = .{
                .base_reg = if (is_pc) null else reg,
                .is_pc_relative = is_pc,
                .index_reg = IndexReg{ .reg = idx_reg, .is_addr = is_addr, .is_long = is_long, .scale = scale },
                .base_disp = disp,
                .outer_disp = 0,
                .is_mem_indirect = false,
                .is_post_indexed = false,
            }};
        } else {
            const base_suppress = (ext & 0x0080) != 0;
            const index_suppress = (ext & 0x0040) != 0;
            const bd_size = (ext >> 4) & 0x3;
            const i_is = ext & 0x7;
            var base_disp: i32 = 0;
            if (bd_size == 2) { base_disp = @as(i16, @bitCast(read_word(pc.*))); pc.* += 2; }
            else if (bd_size == 3) { const high = read_word(pc.*); const low = read_word(pc.* + 2); base_disp = @bitCast((@as(u32, high) << 16) | low); pc.* += 4; }
            var index_reg: ?IndexReg = null;
            if (!index_suppress) {
                const is_addr = (ext & 0x8000) != 0;
                const idx_reg = @as(u3, @truncate((ext >> 12) & 0x7));
                const is_long = (ext & 0x0800) != 0;
                const scale = @as(u4, @truncate(@as(u32, 1) << @as(u5, @truncate((ext >> 9) & 0x3))));
                index_reg = IndexReg{ .reg = idx_reg, .is_addr = is_addr, .is_long = is_long, .scale = scale };
            }
            var outer_disp: i32 = 0;
            const od_size = i_is & 0x3;
            if (od_size == 2) { outer_disp = @as(i16, @bitCast(read_word(pc.*))); pc.* += 2; }
            else if (od_size == 3) { const high = read_word(pc.*); const low = read_word(pc.* + 2); outer_disp = @bitCast((@as(u32, high) << 16) | low); pc.* += 4; }
            return .{ .ComplexEA = .{
                .base_reg = if (base_suppress) null else reg, .is_pc_relative = is_pc,
                .index_reg = index_reg, .base_disp = base_disp, .outer_disp = outer_disp,
                .is_mem_indirect = (i_is != 0), .is_post_indexed = (i_is & 0x4) != 0,
            }};
        }
    }

    fn decodeImmediate(_: *const Decoder, pc: *u32, read_word: *const fn(u32) u16, size: DataSize) !Operand {
        switch (size) {
            .Byte => { const val = read_word(pc.*); pc.* += 2; return .{ .Immediate8 = @truncate(val) }; },
            .Word => { const val = read_word(pc.*); pc.* += 2; return .{ .Immediate16 = val }; },
            .Long => { const high = read_word(pc.*); const low = read_word(pc.* + 2); pc.* += 4; return .{ .Immediate32 = (@as(u32, high) << 16) | low }; },
        }
    }
};

test "Decoder NOP" {
    const decoder = Decoder.init();
    const dummy_read = struct { fn read(_: u32) u16 { return 0; } }.read;
    const inst = try decoder.decode(0x4E71, 0, &dummy_read);
    try std.testing.expectEqual(Mnemonic.NOP, inst.mnemonic);
}

test "Decoder MOVEQ" {
    const decoder = Decoder.init();
    const dummy_read = struct { fn read(_: u32) u16 { return 0; } }.read;
    const inst = try decoder.decode(0x702A, 0, &dummy_read);
    try std.testing.expectEqual(Mnemonic.MOVEQ, inst.mnemonic);
}
