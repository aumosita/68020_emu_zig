const std = @import("std");
const cpu = @import("cpu.zig");
const decoder = @import("decoder.zig");

pub const Executor = struct {
    pub fn init() Executor {
        return .{};
    }
    
    pub fn execute(self: *const Executor, m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
        _ = self;
        
        // Execute instruction and return cycle count
        switch (inst.mnemonic) {
            .NOP => {
                m68k.pc += 2;
                return 4;
            },
            
            .MOVEQ => {
                // MOVEQ #imm, Dn - Move quick immediate to data register
                const reg = switch (inst.dst) {
                    .DataReg => |r| r,
                    else => return error.InvalidOperand,
                };
                
                const value: i8 = switch (inst.src) {
                    .Immediate8 => |v| @bitCast(v),
                    else => return error.InvalidOperand,
                };
                
                // Sign-extend to 32 bits
                m68k.d[reg] = @bitCast(@as(i32, value));
                
                // Set flags
                m68k.setFlags(m68k.d[reg], .Long);
                
                m68k.pc += 2;
                return 4;
            },
            
            .MOVE => {
                // MOVE <src>, <dst> - General data movement
                return try executeMove(m68k, inst);
            },
            
            .ADD => {
                // ADD <src>, Dn - Add to data register
                return try executeAdd(m68k, inst);
            },
            
            .SUB => {
                // SUB <src>, Dn - Subtract from data register
                return try executeSub(m68k, inst);
            },
            
            .CMP => {
                // CMP <src>, Dn - Compare
                return try executeCmp(m68k, inst);
            },
            
            .AND => {
                // AND <src>, <dst> - Logical AND
                return try executeAnd(m68k, inst);
            },
            
            .OR => {
                // OR <src>, <dst> - Logical OR
                return try executeOr(m68k, inst);
            },
            
            .EOR => {
                // EOR Dn, <dst> - Exclusive OR
                return try executeEor(m68k, inst);
            },
            
            .NOT => {
                // NOT <dst> - Logical complement
                const reg = switch (inst.dst) {
                    .DataReg => |r| r,
                    else => return error.InvalidOperand,
                };
                
                m68k.d[reg] = ~m68k.d[reg];
                m68k.setFlags(m68k.d[reg], inst.data_size);
                
                m68k.pc += 2;
                return 6;
            },
            
            .ADDQ => {
                // ADDQ #imm, <ea> - Add quick
                const immediate = switch (inst.src) {
                    .Immediate8 => |v| @as(u32, v),
                    else => return error.InvalidOperand,
                };
                
                switch (inst.dst) {
                    .DataReg => |reg| {
                        const old_value = m68k.d[reg];
                        m68k.d[reg] = old_value +% immediate;
                        m68k.setFlags(m68k.d[reg], inst.data_size);
                    },
                    .AddrReg => |reg| {
                        // Address register, no flags
                        m68k.a[reg] = m68k.a[reg] +% immediate;
                    },
                    else => return error.InvalidOperand,
                }
                
                m68k.pc += 2;
                return 4;
            },
            
            .SUBQ => {
                // SUBQ #imm, <ea> - Subtract quick
                const immediate = switch (inst.src) {
                    .Immediate8 => |v| @as(u32, v),
                    else => return error.InvalidOperand,
                };
                
                switch (inst.dst) {
                    .DataReg => |reg| {
                        const old_value = m68k.d[reg];
                        m68k.d[reg] = old_value -% immediate;
                        m68k.setFlags(m68k.d[reg], inst.data_size);
                    },
                    .AddrReg => |reg| {
                        // Address register, no flags
                        m68k.a[reg] = m68k.a[reg] -% immediate;
                    },
                    else => return error.InvalidOperand,
                }
                
                m68k.pc += 2;
                return 4;
            },
            
            .MULU => {
                // MULU <src>, Dn - Unsigned multiply
                const reg = switch (inst.dst) {
                    .DataReg => |r| r,
                    else => return error.InvalidOperand,
                };
                
                const src_value: u16 = @truncate(try getOperandValue(m68k, inst.src, .Word));
                const dst_value: u16 = @truncate(m68k.d[reg]);
                
                const result: u32 = @as(u32, src_value) * @as(u32, dst_value);
                m68k.d[reg] = result;
                
                m68k.setFlag(cpu.M68k.FLAG_N, (result & 0x80000000) != 0);
                m68k.setFlag(cpu.M68k.FLAG_Z, result == 0);
                m68k.setFlag(cpu.M68k.FLAG_V, false);
                m68k.setFlag(cpu.M68k.FLAG_C, false);
                
                m68k.pc += 2;
                return 38; // Approximate cycle count
            },
            
            .MULS => {
                // MULS <src>, Dn - Signed multiply
                const reg = switch (inst.dst) {
                    .DataReg => |r| r,
                    else => return error.InvalidOperand,
                };
                
                const src_value: i16 = @bitCast(@as(u16, @truncate(try getOperandValue(m68k, inst.src, .Word))));
                const dst_value: i16 = @bitCast(@as(u16, @truncate(m68k.d[reg])));
                
                const result: i32 = @as(i32, src_value) * @as(i32, dst_value);
                m68k.d[reg] = @bitCast(result);
                
                m68k.setFlag(cpu.M68k.FLAG_N, result < 0);
                m68k.setFlag(cpu.M68k.FLAG_Z, result == 0);
                m68k.setFlag(cpu.M68k.FLAG_V, false);
                m68k.setFlag(cpu.M68k.FLAG_C, false);
                
                m68k.pc += 2;
                return 38;
            },
            
            .DIVU => {
                // DIVU <src>, Dn - Unsigned divide
                const reg = switch (inst.dst) {
                    .DataReg => |r| r,
                    else => return error.InvalidOperand,
                };
                
                const divisor: u16 = @truncate(try getOperandValue(m68k, inst.src, .Word));
                if (divisor == 0) {
                    return error.DivideByZero;
                }
                
                const dividend = m68k.d[reg];
                const quotient = dividend / divisor;
                const remainder = dividend % divisor;
                
                if (quotient > 0xFFFF) {
                    m68k.setFlag(cpu.M68k.FLAG_V, true);
                } else {
                    m68k.d[reg] = (remainder << 16) | quotient;
                    m68k.setFlag(cpu.M68k.FLAG_N, (quotient & 0x8000) != 0);
                    m68k.setFlag(cpu.M68k.FLAG_Z, quotient == 0);
                    m68k.setFlag(cpu.M68k.FLAG_V, false);
                }
                m68k.setFlag(cpu.M68k.FLAG_C, false);
                
                m68k.pc += 2;
                return 76;
            },
            
            .DIVS => {
                // DIVS <src>, Dn - Signed divide
                const reg = switch (inst.dst) {
                    .DataReg => |r| r,
                    else => return error.InvalidOperand,
                };
                
                const divisor: i16 = @bitCast(@as(u16, @truncate(try getOperandValue(m68k, inst.src, .Word))));
                if (divisor == 0) {
                    return error.DivideByZero;
                }
                
                const dividend: i32 = @bitCast(m68k.d[reg]);
                const quotient = @divTrunc(dividend, divisor);
                const remainder = @rem(dividend, divisor);
                
                if (quotient < -32768 or quotient > 32767) {
                    m68k.setFlag(cpu.M68k.FLAG_V, true);
                } else {
                    const q: u16 = @bitCast(@as(i16, @truncate(quotient)));
                    const r: u16 = @bitCast(@as(i16, @truncate(remainder)));
                    m68k.d[reg] = (@as(u32, r) << 16) | @as(u32, q);
                    m68k.setFlag(cpu.M68k.FLAG_N, quotient < 0);
                    m68k.setFlag(cpu.M68k.FLAG_Z, quotient == 0);
                    m68k.setFlag(cpu.M68k.FLAG_V, false);
                }
                m68k.setFlag(cpu.M68k.FLAG_C, false);
                
                m68k.pc += 2;
                return 76;
            },
            
            .NEG => {
                // NEG <dst> - Negate
                const reg = switch (inst.dst) {
                    .DataReg => |r| r,
                    else => return error.InvalidOperand,
                };
                
                const old = m68k.d[reg];
                m68k.d[reg] = 0 -% old;
                
                m68k.setFlags(m68k.d[reg], inst.data_size);
                m68k.setFlag(cpu.M68k.FLAG_X, old != 0);
                m68k.setFlag(cpu.M68k.FLAG_C, old != 0);
                
                m68k.pc += 2;
                return 4;
            },
            
            .RTS => {
                // Pop return address from stack
                const sp = m68k.a[7];
                m68k.pc = try m68k.memory.read32(sp);
                m68k.a[7] = sp + 4;
                return 16;
            },
            
            .BRA => {
                // Branch always
                const displacement = @as(i8, @bitCast(@as(u8, @truncate(inst.opcode & 0xFF))));
                if (displacement == 0) {
                    // 16-bit displacement follows
                    const disp16 = try m68k.memory.read16(m68k.pc + 2);
                    m68k.pc = @intCast(@as(i32, @intCast(m68k.pc)) + 2 + @as(i32, @intCast(@as(i16, @bitCast(disp16)))));
                } else {
                    m68k.pc = @intCast(@as(i32, @intCast(m68k.pc)) + 2 + @as(i32, displacement));
                }
                return 10;
            },
            
            .Bcc => {
                // Conditional branch
                const condition: u4 = @truncate((inst.opcode >> 8) & 0xF);
                const branch_taken = evaluateCondition(m68k, condition);
                
                if (branch_taken) {
                    const displacement = @as(i8, @bitCast(@as(u8, @truncate(inst.opcode & 0xFF))));
                    if (displacement == 0) {
                        const disp16 = try m68k.memory.read16(m68k.pc + 2);
                        m68k.pc = @intCast(@as(i32, @intCast(m68k.pc)) + 2 + @as(i32, @intCast(@as(i16, @bitCast(disp16)))));
                    } else {
                        m68k.pc = @intCast(@as(i32, @intCast(m68k.pc)) + 2 + @as(i32, displacement));
                    }
                    return 10;
                } else {
                    m68k.pc += 2;
                    return 8;
                }
            },
            
            .JSR => {
                // Jump to subroutine
                const return_addr = m68k.pc + 2;
                m68k.a[7] -= 4;
                try m68k.memory.write32(m68k.a[7], return_addr);
                // Simplified: would need to decode target address
                m68k.pc += 2;
                return 18;
            },
            
            .CLR => {
                // CLR <ea> - Clear operand
                switch (inst.dst) {
                    .DataReg => |reg| {
                        m68k.d[reg] = 0;
                        m68k.setFlag(cpu.M68k.FLAG_Z, true);
                        m68k.setFlag(cpu.M68k.FLAG_N, false);
                        m68k.setFlag(cpu.M68k.FLAG_V, false);
                        m68k.setFlag(cpu.M68k.FLAG_C, false);
                    },
                    else => return error.InvalidOperand,
                }
                m68k.pc += 2;
                return 4;
            },
            
            .TST => {
                // TST <ea> - Test operand
                switch (inst.dst) {
                    .DataReg => |reg| {
                        m68k.setFlags(m68k.d[reg], inst.data_size);
                    },
                    else => return error.InvalidOperand,
                }
                m68k.pc += 2;
                return 4;
            },
            
            .SWAP => {
                // SWAP Dn - Swap register halves
                const reg = switch (inst.dst) {
                    .DataReg => |r| r,
                    else => return error.InvalidOperand,
                };
                
                const low: u32 = m68k.d[reg] & 0xFFFF;
                const high: u32 = (m68k.d[reg] >> 16) & 0xFFFF;
                m68k.d[reg] = (low << 16) | high;
                
                m68k.setFlags(m68k.d[reg], .Long);
                
                m68k.pc += 2;
                return 4;
            },
            
            .EXT => {
                // EXT Dn - Sign extend
                const reg = switch (inst.dst) {
                    .DataReg => |r| r,
                    else => return error.InvalidOperand,
                };
                
                if (inst.data_size == .Word) {
                    // Extend byte to word
                    const byte_val: i8 = @bitCast(@as(u8, @truncate(m68k.d[reg])));
                    const extended: i16 = byte_val;
                    m68k.d[reg] = (m68k.d[reg] & 0xFFFF0000) | @as(u32, @bitCast(@as(i32, extended) & 0xFFFF));
                } else {
                    // Extend word to long
                    const word_val: i16 = @bitCast(@as(u16, @truncate(m68k.d[reg])));
                    m68k.d[reg] = @bitCast(@as(i32, word_val));
                }
                
                m68k.setFlags(m68k.d[reg], inst.data_size);
                
                m68k.pc += 2;
                return 4;
            },
            
            .LEA => {
                // LEA <ea>, An - Load effective address
                const reg = switch (inst.dst) {
                    .AddrReg => |r| r,
                    else => return error.InvalidOperand,
                };
                
                // Simplified: calculate effective address
                const ea = try calculateEA(m68k, inst.src);
                m68k.a[reg] = ea;
                
                m68k.pc += 2;
                return 4;
            },
            
            .ILLEGAL => {
                return error.IllegalInstruction;
            },
            
            else => {
                // Unimplemented instruction - for now, just skip
                m68k.pc += 2;
                return 4;
            },
        }
    }
};

fn executeMove(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const src_value = try getOperandValue(m68k, inst.src, inst.data_size);
    try setOperandValue(m68k, inst.dst, src_value, inst.data_size);
    
    m68k.setFlags(src_value, inst.data_size);
    
    m68k.pc += 2;
    return 4;
}

fn executeAdd(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const reg = switch (inst.dst) {
        .DataReg => |r| r,
        else => return error.InvalidOperand,
    };
    
    const src_value = try getOperandValue(m68k, inst.src, inst.data_size);
    const dst_value = m68k.d[reg];
    const result = dst_value +% src_value;
    
    m68k.d[reg] = result;
    m68k.setFlags(result, inst.data_size);
    
    // Set carry and overflow flags
    m68k.setFlag(cpu.M68k.FLAG_C, result < dst_value);
    m68k.setFlag(cpu.M68k.FLAG_X, result < dst_value);
    
    m68k.pc += 2;
    return 4;
}

fn executeSub(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const reg = switch (inst.dst) {
        .DataReg => |r| r,
        else => return error.InvalidOperand,
    };
    
    const src_value = try getOperandValue(m68k, inst.src, inst.data_size);
    const dst_value = m68k.d[reg];
    const result = dst_value -% src_value;
    
    m68k.d[reg] = result;
    m68k.setFlags(result, inst.data_size);
    
    // Set carry and overflow flags
    m68k.setFlag(cpu.M68k.FLAG_C, result > dst_value);
    m68k.setFlag(cpu.M68k.FLAG_X, result > dst_value);
    
    m68k.pc += 2;
    return 4;
}

fn executeCmp(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const reg = switch (inst.dst) {
        .DataReg => |r| r,
        else => return error.InvalidOperand,
    };
    
    const src_value = try getOperandValue(m68k, inst.src, inst.data_size);
    const dst_value = m68k.d[reg];
    const result = dst_value -% src_value;
    
    // Set flags but don't store result
    m68k.setFlags(result, inst.data_size);
    m68k.setFlag(cpu.M68k.FLAG_C, result > dst_value);
    
    m68k.pc += 2;
    return 4;
}

fn executeAnd(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const reg = switch (inst.dst) {
        .DataReg => |r| r,
        else => return error.InvalidOperand,
    };
    
    const src_value = try getOperandValue(m68k, inst.src, inst.data_size);
    const result = m68k.d[reg] & src_value;
    
    m68k.d[reg] = result;
    m68k.setFlags(result, inst.data_size);
    
    m68k.pc += 2;
    return 4;
}

fn executeOr(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const reg = switch (inst.dst) {
        .DataReg => |r| r,
        else => return error.InvalidOperand,
    };
    
    const src_value = try getOperandValue(m68k, inst.src, inst.data_size);
    const result = m68k.d[reg] | src_value;
    
    m68k.d[reg] = result;
    m68k.setFlags(result, inst.data_size);
    
    m68k.pc += 2;
    return 4;
}

fn executeEor(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const reg = switch (inst.src) {
        .DataReg => |r| r,
        else => return error.InvalidOperand,
    };
    
    const src_value = m68k.d[reg];
    
    switch (inst.dst) {
        .DataReg => |dst_reg| {
            const result = m68k.d[dst_reg] ^ src_value;
            m68k.d[dst_reg] = result;
            m68k.setFlags(result, inst.data_size);
        },
        else => return error.InvalidOperand,
    }
    
    m68k.pc += 2;
    return 4;
}

fn getOperandValue(m68k: *cpu.M68k, operand: decoder.Operand, size: decoder.DataSize) !u32 {
    return switch (operand) {
        .DataReg => |reg| m68k.d[reg],
        .AddrReg => |reg| m68k.a[reg],
        .Immediate8 => |val| @as(u32, val),
        .Immediate16 => |val| @as(u32, val),
        .Immediate32 => |val| val,
        .AddrIndirect => |reg| {
            const addr = m68k.a[reg];
            return switch (size) {
                .Byte => @as(u32, try m68k.memory.read8(addr)),
                .Word => @as(u32, try m68k.memory.read16(addr)),
                .Long => try m68k.memory.read32(addr),
            };
        },
        else => 0,
    };
}

fn setOperandValue(m68k: *cpu.M68k, operand: decoder.Operand, value: u32, size: decoder.DataSize) !void {
    switch (operand) {
        .DataReg => |reg| {
            m68k.d[reg] = value;
        },
        .AddrReg => |reg| {
            m68k.a[reg] = value;
        },
        .AddrIndirect => |reg| {
            const addr = m68k.a[reg];
            switch (size) {
                .Byte => try m68k.memory.write8(addr, @truncate(value)),
                .Word => try m68k.memory.write16(addr, @truncate(value)),
                .Long => try m68k.memory.write32(addr, value),
            }
        },
        else => {},
    }
}

fn calculateEA(m68k: *cpu.M68k, operand: decoder.Operand) !u32 {
    return switch (operand) {
        .AddrIndirect => |reg| m68k.a[reg],
        .AddrDisplace => |info| m68k.a[info.reg] +% @as(u32, @bitCast(@as(i32, info.displacement))),
        .Address => |addr| addr,
        else => 0,
    };
}

fn evaluateCondition(m68k: *const cpu.M68k, condition: u4) bool {
    const c = m68k.getFlag(cpu.M68k.FLAG_C);
    const v = m68k.getFlag(cpu.M68k.FLAG_V);
    const z = m68k.getFlag(cpu.M68k.FLAG_Z);
    const n = m68k.getFlag(cpu.M68k.FLAG_N);
    
    return switch (condition) {
        0x0 => true,              // T (true)
        0x1 => false,             // F (false)
        0x2 => !c and !z,         // HI (high)
        0x3 => c or z,            // LS (low or same)
        0x4 => !c,                // CC/HS (carry clear)
        0x5 => c,                 // CS/LO (carry set)
        0x6 => !z,                // NE (not equal)
        0x7 => z,                 // EQ (equal)
        0x8 => !v,                // VC (overflow clear)
        0x9 => v,                 // VS (overflow set)
        0xA => !n,                // PL (plus)
        0xB => n,                 // MI (minus)
        0xC => (n and v) or (!n and !v),  // GE (greater or equal)
        0xD => (n and !v) or (!n and v),  // LT (less than)
        0xE => (n and v and !z) or (!n and !v and !z),  // GT (greater than)
        0xF => z or (n and !v) or (!n and v),           // LE (less or equal)
    };
}

test "Executor NOP" {
    const allocator = std.testing.allocator;
    var m68k = cpu.M68k.init(allocator);
    defer m68k.deinit();
    
    const executor = Executor.init();
    var inst = decoder.Instruction.init();
    inst.mnemonic = .NOP;
    
    const initial_pc = m68k.pc;
    const cycles = try executor.execute(&m68k, &inst);
    
    try std.testing.expectEqual(@as(u32, 4), cycles);
    try std.testing.expectEqual(initial_pc + 2, m68k.pc);
}
