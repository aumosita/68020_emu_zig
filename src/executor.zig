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
                // Simplified MOVE implementation
                // Full implementation would handle all addressing modes
                m68k.pc += 2;
                return 4;
            },
            
            .ADD => {
                // Simplified ADD implementation
                m68k.pc += 2;
                return 4;
            },
            
            .SUB => {
                // Simplified SUB implementation
                m68k.pc += 2;
                return 4;
            },
            
            .CMP => {
                // Simplified CMP implementation
                m68k.pc += 2;
                return 4;
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
