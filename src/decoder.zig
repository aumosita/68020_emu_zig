const std = @import("std");

pub const Instruction = struct {
    opcode: u16,
    size: u8,  // Instruction size in bytes (including extension words)
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
    // Data movement
    MOVE, MOVEA, MOVEM, MOVEP, MOVEQ,
    LEA, PEA,
    EXG, SWAP,
    
    // Arithmetic
    ADD, ADDA, ADDI, ADDQ, ADDX,
    SUB, SUBA, SUBI, SUBQ, SUBX,
    MULU, MULS,
    DIVU, DIVS,
    NEG, NEGX,
    CLR,
    EXT, EXTB,
    
    // Logical
    AND, ANDI, OR, ORI, EOR, EORI,
    NOT,
    
    // Shift and rotate
    ASL, ASR, LSL, LSR,
    ROL, ROR, ROXL, ROXR,
    
    // Bit manipulation
    BCHG, BCLR, BSET, BTST,
    
    // BCD
    ABCD, SBCD, NBCD,
    
    // Program control
    BRA, BSR,
    Bcc,
    DBcc,
    Scc,
    JMP, JSR,
    RTS, RTR, RTE,
    NOP,
    
    // System control
    TRAP, TRAPV,
    CHK,
    ILLEGAL,
    RESET, STOP,
    
    // Comparison
    CMP, CMPA, CMPI, CMPM,
    TST,
    
    // Stack operations
    LINK, UNLK,
    
    UNKNOWN,
};

pub const Operand = union(enum) {
    None: void,
    DataReg: u3,           // D0-D7
    AddrReg: u3,           // A0-A7
    Immediate8: u8,
    Immediate16: u16,
    Immediate32: u32,
    Address: u32,          // Absolute address
    AddrIndirect: u3,      // (An)
    AddrPostInc: u3,       // (An)+
    AddrPreDec: u3,        // -(An)
    AddrDisplace: struct {  // d16(An)
        reg: u3,
        displacement: i16,
    },
    PCDisplace: i16,       // d16(PC)
};

pub const Decoder = struct {
    pub fn init() Decoder {
        return .{};
    }
    
    pub fn decode(self: *const Decoder, opcode: u16, pc: u32, read_word: *const fn(u32) u16) !Instruction {
        _ = self;
        _ = pc;
        _ = read_word;
        
        var inst = Instruction.init();
        inst.opcode = opcode;
        
        // Get major opcode groups
        const high4 = (opcode >> 12) & 0xF;
        
        switch (high4) {
            0x0 => {
                // Bit manipulation, MOVEP, immediate operations
                const bits_8_6 = (opcode >> 6) & 0x7;
                
                if (bits_8_6 == 0x1) {
                    // Bit operations
                    const bit_op = (opcode >> 6) & 0x3;
                    inst.mnemonic = switch (bit_op) {
                        0 => .BTST,
                        1 => .BCHG,
                        2 => .BCLR,
                        3 => .BSET,
                        else => .UNKNOWN,
                    };
                } else if ((opcode & 0xFF00) == 0x0000) {
                    // ORI, ANDI, SUBI, ADDI, EORI, CMPI to various destinations
                    const subop = (opcode >> 9) & 0x7;
                    inst.mnemonic = switch (subop) {
                        0 => .ORI,
                        1 => .ANDI,
                        2 => .SUBI,
                        3 => .ADDI,
                        5 => .EORI,
                        6 => .CMPI,
                        else => .UNKNOWN,
                    };
                } else {
                    inst.mnemonic = .UNKNOWN;
                }
            },
            
            0x1, 0x2, 0x3 => {
                // MOVE instructions
                inst.mnemonic = .MOVE;
                inst.data_size = switch (high4) {
                    0x1 => .Byte,
                    0x3 => .Word,
                    0x2 => .Long,
                    else => .Long,
                };
                
                // Decode destination (bits 11-6)
                const dst_mode = (opcode >> 6) & 0x7;
                const dst_reg = (opcode >> 9) & 0x7;
                inst.dst = decodeEA(dst_mode, dst_reg);
                
                // Decode source (bits 5-0)
                const src_mode = opcode & 0x7;
                const src_reg = (opcode >> 0) & 0x7;
                inst.src = decodeEA(src_mode, src_reg);
            },
            
            0x4 => {
                // Miscellaneous instructions
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
                } else if ((opcode & 0xFF00) == 0x4E00) {
                    // JSR, JMP
                    const ea_mode = (opcode >> 3) & 0x7;
                    const ea_reg = opcode & 0x7;
                    if ((opcode & 0xFFC0) == 0x4E80) {
                        inst.mnemonic = .JSR;
                    } else if ((opcode & 0xFFC0) == 0x4EC0) {
                        inst.mnemonic = .JMP;
                    }
                    inst.dst = decodeEA(ea_mode, ea_reg);
                } else if ((opcode & 0xFF00) == 0x4000 or (opcode & 0xFF00) == 0x4200 or (opcode & 0xFF00) == 0x4400 or (opcode & 0xFF00) == 0x4600) {
                    // NEGX, CLR, NEG, NOT
                    const subop = (opcode >> 9) & 0x7;
                    inst.mnemonic = switch (subop) {
                        0 => .NEGX,
                        1 => .CLR,
                        2 => .NEG,
                        3 => .NOT,
                        else => .UNKNOWN,
                    };
                    const ea_mode = (opcode >> 3) & 0x7;
                    const ea_reg = opcode & 0x7;
                    inst.dst = decodeEA(ea_mode, @truncate(ea_reg));
                    const size_bits = (opcode >> 6) & 0x3;
                    inst.data_size = switch (size_bits) {
                        0 => .Byte,
                        1 => .Word,
                        2 => .Long,
                        else => .Long,
                    };
                } else if ((opcode & 0xFF00) == 0x4A00) {
                    // TST
                    inst.mnemonic = .TST;
                    const ea_mode = (opcode >> 3) & 0x7;
                    const ea_reg = opcode & 0x7;
                    inst.dst = decodeEA(ea_mode, @truncate(ea_reg));
                    const size_bits = (opcode >> 6) & 0x3;
                    inst.data_size = switch (size_bits) {
                        0 => .Byte,
                        1 => .Word,
                        2 => .Long,
                        else => .Long,
                    };
                } else if ((opcode & 0xFFC0) == 0x4840) {
                    // SWAP
                    inst.mnemonic = .SWAP;
                    inst.dst = .{ .DataReg = @truncate(opcode & 0x7) };
                } else if ((opcode & 0xFFC0) == 0x4880 or (opcode & 0xFFC0) == 0x48C0) {
                    // EXT.W or EXT.L
                    inst.mnemonic = .EXT;
                    inst.dst = .{ .DataReg = @truncate(opcode & 0x7) };
                    // Bit 6 determines size: 0=word (byte->word), 1=long (word->long)
                    inst.data_size = if ((opcode & 0x40) != 0) .Long else .Word;
                } else {
                    inst.mnemonic = .UNKNOWN;
                }
            },
            
            0x5 => {
                // ADDQ, SUBQ, Scc, DBcc
                const mode = (opcode >> 3) & 0x7;
                const reg = opcode & 0x7;
                
                if (mode == 0x1) {
                    // DBcc
                    inst.mnemonic = .DBcc;
                    inst.dst = .{ .DataReg = @truncate(reg) };
                } else {
                    const is_sub = ((opcode >> 8) & 1) == 1;
                    inst.mnemonic = if (is_sub) .SUBQ else .ADDQ;
                    
                    // Immediate data (3 bits, 0 means 8)
                    var data: u8 = @truncate((opcode >> 9) & 0x7);
                    if (data == 0) data = 8;
                    inst.src = .{ .Immediate8 = data };
                    inst.dst = decodeEA(mode, @truncate(reg));
                }
            },
            
            0x6 => {
                // Bcc, BSR, BRA
                const condition: u8 = @truncate((opcode >> 8) & 0xF);
                const displacement: i8 = @bitCast(@as(u8, @truncate(opcode & 0xFF)));
                
                if (condition == 0x0) {
                    inst.mnemonic = .BRA;
                } else if (condition == 0x1) {
                    inst.mnemonic = .BSR;
                } else {
                    inst.mnemonic = .Bcc;
                }
                
                if (displacement == 0) {
                    // 16-bit displacement follows
                    inst.size = 4;
                } else {
                    inst.src = .{ .Immediate8 = @bitCast(displacement) };
                }
            },
            
            0x7 => {
                // MOVEQ
                inst.mnemonic = .MOVEQ;
                inst.dst = .{ .DataReg = @truncate((opcode >> 9) & 0x7) };
                inst.src = .{ .Immediate8 = @truncate(opcode & 0xFF) };
            },
            
            0x8 => {
                // OR, DIVU, DIVS, SBCD
                if ((opcode & 0x1F0) == 0x100) {
                    inst.mnemonic = .SBCD;
                } else if ((opcode & 0x1C0) == 0x1C0) {
                    inst.mnemonic = if (((opcode >> 8) & 1) == 0) .DIVU else .DIVS;
                } else {
                    inst.mnemonic = .OR;
                }
            },
            
            0x9, 0xD => {
                // SUB/SUBX, ADD/ADDX
                const is_add = high4 == 0xD;
                const opmode = (opcode >> 6) & 0x7;
                
                if ((opmode & 0x4) != 0) {
                    // ADDA/SUBA
                    inst.mnemonic = if (is_add) .ADDA else .SUBA;
                } else if ((opmode & 0x3) == 0x0 and ((opcode >> 3) & 0x7) == 0x1) {
                    // ADDX/SUBX
                    inst.mnemonic = if (is_add) .ADDX else .SUBX;
                } else {
                    inst.mnemonic = if (is_add) .ADD else .SUB;
                }
            },
            
            0xB => {
                // CMP, EOR
                const opmode = (opcode >> 6) & 0x7;
                if ((opmode & 0x4) != 0) {
                    inst.mnemonic = .CMPA;
                } else if ((opmode & 0x3) == 0x1 and ((opcode >> 3) & 0x7) == 0x1) {
                    inst.mnemonic = .CMPM;
                } else if (opmode >= 0x4) {
                    inst.mnemonic = .EOR;
                } else {
                    inst.mnemonic = .CMP;
                }
            },
            
            0xC => {
                // AND, MULU, MULS, ABCD, EXG
                if ((opcode & 0x1F0) == 0x100) {
                    inst.mnemonic = .ABCD;
                } else if ((opcode & 0x1C0) == 0x1C0) {
                    inst.mnemonic = if (((opcode >> 8) & 1) == 0) .MULU else .MULS;
                } else if ((opcode & 0x1F0) == 0x140 or (opcode & 0x1F0) == 0x148 or (opcode & 0x1F0) == 0x188) {
                    inst.mnemonic = .EXG;
                } else {
                    inst.mnemonic = .AND;
                }
            },
            
            0xE => {
                // Shift/rotate
                const direction = (opcode >> 8) & 1;  // 0=right, 1=left
                const shift_type = (opcode >> 3) & 0x3;
                
                inst.mnemonic = switch (shift_type) {
                    0 => if (direction == 1) .ASL else .ASR,
                    1 => if (direction == 1) .LSL else .LSR,
                    2 => if (direction == 1) .ROXL else .ROXR,
                    3 => if (direction == 1) .ROL else .ROR,
                    else => .UNKNOWN,
                };
            },
            
            0xA, 0xF => {
                // A-line and F-line are illegal/emulator instructions
                inst.mnemonic = .ILLEGAL;
            },
            
            else => {
                inst.mnemonic = .UNKNOWN;
            },
        }
        
        return inst;
    }
    
    fn decodeEA(mode: u16, reg: u16) Operand {
        return switch (mode) {
            0 => .{ .DataReg = @truncate(reg) },
            1 => .{ .AddrReg = @truncate(reg) },
            2 => .{ .AddrIndirect = @truncate(reg) },
            3 => .{ .AddrPostInc = @truncate(reg) },
            4 => .{ .AddrPreDec = @truncate(reg) },
            5 => .{ .AddrDisplace = .{ .reg = @truncate(reg), .displacement = 0 } },  // Will be read later
            7 => {
                // Absolute or immediate
                if (reg == 4) {
                    return .{ .Immediate16 = 0 };  // Will be read later
                } else {
                    return .{ .Address = 0 };  // Will be read later
                }
            },
            else => .{ .None = {} },
        };
    }
};

test "Decoder NOP" {
    const decoder = Decoder.init();
    const dummy_read = struct {
        fn read(_: u32) u16 { return 0; }
    }.read;
    
    const inst = try decoder.decode(0x4E71, 0, &dummy_read);
    try std.testing.expectEqual(Mnemonic.NOP, inst.mnemonic);
}

test "Decoder MOVEQ" {
    const decoder = Decoder.init();
    const dummy_read = struct {
        fn read(_: u32) u16 { return 0; }
    }.read;
    
    const inst = try decoder.decode(0x702A, 0, &dummy_read);  // MOVEQ #42, D0
    try std.testing.expectEqual(Mnemonic.MOVEQ, inst.mnemonic);
}
