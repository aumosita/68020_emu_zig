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
            
            .MOVEQ => return try executeMoveq(m68k, inst),
            .MOVE => return try executeMove(m68k, inst),
            .MOVEA => return try executeMovea(m68k, inst),
            
            .ADD => return try executeAdd(m68k, inst),
            .ADDA => return try executeAdda(m68k, inst),
            .ADDI => return try executeAddi(m68k, inst),
            .ADDQ => return try executeAddq(m68k, inst),
            .ADDX => return try executeAddx(m68k, inst),
            
            .SUB => return try executeSub(m68k, inst),
            .SUBA => return try executeSuba(m68k, inst),
            .SUBI => return try executeSubi(m68k, inst),
            .SUBQ => return try executeSubq(m68k, inst),
            .SUBX => return try executeSubx(m68k, inst),
            
            .CMP => return try executeCmp(m68k, inst),
            .CMPA => return try executeCmpa(m68k, inst),
            .CMPI => return try executeCmpi(m68k, inst),
            
            .AND => return try executeAnd(m68k, inst),
            .ANDI => return try executeAndi(m68k, inst),
            .OR => return try executeOr(m68k, inst),
            .ORI => return try executeOri(m68k, inst),
            .EOR => return try executeEor(m68k, inst),
            .EORI => return try executeEori(m68k, inst),
            .NOT => return try executeNot(m68k, inst),
            
            .MULU => return try executeMulu(m68k, inst),
            .MULS => return try executeMuls(m68k, inst),
            .DIVU => return try executeDivu(m68k, inst),
            .DIVS => return try executeDivs(m68k, inst),
            
            .NEG => return try executeNeg(m68k, inst),
            .NEGX => return try executeNegx(m68k, inst),
            .CLR => return try executeClr(m68k, inst),
            .TST => return try executeTst(m68k, inst),
            .SWAP => return try executeSwap(m68k, inst),
            .EXT => return try executeExt(m68k, inst),
            .EXTB => return try executeExt(m68k, inst),  // EXTB uses same function
            .LEA => return try executeLea(m68k, inst),
            
            .RTS => return try executeRts(m68k),
            .RTR => return try executeRtr(m68k),
            .RTE => return try executeRte(m68k),
            .TRAP => return try executeTrap(m68k, inst),
            .BRA => return try executeBra(m68k, inst),
            .Bcc => return try executeBcc(m68k, inst),
            .BSR => return try executeBsr(m68k, inst),
            .JSR => return try executeJsr(m68k, inst),
            .JMP => return try executeJmp(m68k, inst),
            .DBcc => return try executeDbcc(m68k, inst),
            .Scc => return try executeScc(m68k, inst),
            
            .ASL => return try executeAsl(m68k, inst),
            .ASR => return try executeAsr(m68k, inst),
            .LSL => return try executeLsl(m68k, inst),
            .LSR => return try executeLsr(m68k, inst),
            .ROL => return try executeRol(m68k, inst),
            .ROR => return try executeRor(m68k, inst),
            .ROXL => return try executeRoxl(m68k, inst),
            .ROXR => return try executeRoxr(m68k, inst),
            
            .BTST => return try executeBtst(m68k, inst),
            .BSET => return try executeBset(m68k, inst),
            
            .MOVEC => return try executeMovec(m68k, inst),  // 68020
            .BCLR => return try executeBclr(m68k, inst),
            .BCHG => return try executeBchg(m68k, inst),
            
            .LINK => return try executeLink(m68k, inst),
            .UNLK => return try executeUnlk(m68k, inst),
            .PEA => return try executePea(m68k, inst),
            .MOVEM => return try executeMovem(m68k, inst),
            
            .EXG => return try executeExg(m68k, inst),
            .CMPM => return try executeCmpm(m68k, inst),
            .CHK => return try executeChk(m68k, inst),
            .TAS => return try executeTas(m68k, inst),
            .ABCD => return try executeAbcd(m68k, inst),
            .SBCD => return try executeSbcd(m68k, inst),
            .NBCD => return try executeNbcd(m68k, inst),
            .MOVEP => return try executeMovep(m68k, inst),
            
            // 68020 exclusive instructions
            .BFTST => return try executeBftst(m68k, inst),
            .BFSET => return try executeBfset(m68k, inst),
            .BFCLR => return try executeBfclr(m68k, inst),
            .BFEXTS => return try executeBfexts(m68k, inst),
            .BFEXTU => return try executeBfextu(m68k, inst),
            .BFINS => return try executeBfins(m68k, inst),
            .BFFFO => return try executeBfffo(m68k, inst),
            .CAS => return try executeCas(m68k, inst),
            .CAS2 => return try executeCas2(m68k, inst),
            
            // 68020 Phase 2
            .RTD => return try executeRtd(m68k, inst),
            .BKPT => return try executeBkpt(m68k, inst),
            .TRAPcc => return try executeTrapcc(m68k, inst),
            .CHK2 => return try executeChk2(m68k, inst),
            .CMP2 => return try executeCmp2(m68k, inst),
            .PACK => return try executePack(m68k, inst),
            .UNPK => return try executeUnpk(m68k, inst),
            .MULS_L => return try executeMulsL(m68k, inst),
            .MULU_L => return try executeMuluL(m68k, inst),
            .DIVS_L => return try executeDivsL(m68k, inst),
            .DIVU_L => return try executeDivuL(m68k, inst),
            
            .ILLEGAL => return error.IllegalInstruction,
            else => {
                m68k.pc += 2;
                return 4;
            },
        }
    }
};

// ============================================================================
// MOVE family
// ============================================================================

fn executeMoveq(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const reg = switch (inst.dst) {
        .DataReg => |r| r,
        else => return error.InvalidOperand,
    };
    
    const value: i8 = switch (inst.src) {
        .Immediate8 => |v| @bitCast(v),
        else => return error.InvalidOperand,
    };
    
    m68k.d[reg] = @bitCast(@as(i32, value));
    m68k.setFlags(m68k.d[reg], .Long);
    
    m68k.pc += 2;
    return 4;
}

fn executeMove(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    var cycles: u32 = 4; // Base MOVE cycles
    
    // Add EA cycles for source
    cycles += getEACycles(inst.src, inst.data_size, true);
    
    // Get source value
    const src_value = try getOperandValue(m68k, inst.src, inst.data_size);
    
    // Add EA cycles for destination
    cycles += getEACycles(inst.dst, inst.data_size, false);
    
    // Store to destination
    try setOperandValue(m68k, inst.dst, src_value, inst.data_size);
    
    // Set flags based on value moved
    m68k.setFlags(src_value, inst.data_size);
    
    m68k.pc += 2;
    return cycles;
}

fn executeMovea(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const reg = switch (inst.dst) {
        .AddrReg => |r| r,
        else => return error.InvalidOperand,
    };
    
    var cycles: u32 = 4;
    cycles += getEACycles(inst.src, inst.data_size, true);
    
    var value = try getOperandValue(m68k, inst.src, inst.data_size);
    
    // Sign extend if word
    if (inst.data_size == .Word) {
        const signed: i16 = @bitCast(@as(u16, @truncate(value)));
        value = @bitCast(@as(i32, signed));
    }
    
    m68k.a[reg] = value;
    // MOVEA doesn't affect flags
    
    m68k.pc += 2;
    return cycles;
}

// ============================================================================
// ADD family
// ============================================================================

fn executeAdd(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    // ADD can be: ADD <ea>, Dn  or  ADD Dn, <ea>
    // We need to determine direction from opcode
    const opmode = (inst.opcode >> 6) & 0x7;
    const direction = (opmode >> 2) & 1; // 0 = <ea> + Dn -> Dn, 1 = Dn + <ea> -> <ea>
    
    var cycles: u32 = switch (inst.data_size) {
        .Byte, .Word => 4,
        .Long => 6,
    };
    
    if (direction == 0) {
        // ADD <ea>, Dn
        const reg = switch (inst.dst) {
            .DataReg => |r| r,
            else => return error.InvalidOperand,
        };
        
        cycles += getEACycles(inst.src, inst.data_size, true);
        const src_value = try getOperandValue(m68k, inst.src, inst.data_size);
        const dst_value = getRegisterValue(m68k.d[reg], inst.data_size);
        const result = dst_value +% src_value;
        
        setRegisterValue(&m68k.d[reg], result, inst.data_size);
        setArithmeticFlags(m68k, dst_value, src_value, result, inst.data_size, false);
        
        m68k.pc += 2;
        return cycles;
    } else {
        // ADD Dn, <ea>
        const reg = switch (inst.src) {
            .DataReg => |r| r,
            else => return error.InvalidOperand,
        };
        
        cycles += getEACycles(inst.dst, inst.data_size, true);
        cycles += getEACycles(inst.dst, inst.data_size, false); // Write back
        
        const src_value = getRegisterValue(m68k.d[reg], inst.data_size);
        const dst_value = try getOperandValue(m68k, inst.dst, inst.data_size);
        const result = dst_value +% src_value;
        
        try setOperandValue(m68k, inst.dst, result, inst.data_size);
        setArithmeticFlags(m68k, dst_value, src_value, result, inst.data_size, false);
        
        m68k.pc += 2;
        return cycles;
    }
}

fn executeAdda(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const reg = switch (inst.dst) {
        .AddrReg => |r| r,
        else => return error.InvalidOperand,
    };
    
    var cycles: u32 = 8;
    cycles += getEACycles(inst.src, inst.data_size, true);
    
    var value = try getOperandValue(m68k, inst.src, inst.data_size);
    
    // Sign extend if word
    if (inst.data_size == .Word) {
        const signed: i16 = @bitCast(@as(u16, @truncate(value)));
        value = @bitCast(@as(i32, signed));
    }
    
    m68k.a[reg] = m68k.a[reg] +% value;
    // ADDA doesn't affect flags
    
    m68k.pc += 2;
    return cycles;
}

fn executeAddi(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    var cycles: u32 = switch (inst.data_size) {
        .Byte, .Word => 8,
        .Long => 16,
    };
    cycles += getEACycles(inst.dst, inst.data_size, true);
    cycles += getEACycles(inst.dst, inst.data_size, false);
    
    const imm = try getOperandValue(m68k, inst.src, inst.data_size);
    const dst_value = try getOperandValue(m68k, inst.dst, inst.data_size);
    const result = dst_value +% imm;
    
    try setOperandValue(m68k, inst.dst, result, inst.data_size);
    setArithmeticFlags(m68k, dst_value, imm, result, inst.data_size, false);
    
    m68k.pc += 4; // ADDI has extension word
    return cycles;
}

fn executeAddq(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const immediate = switch (inst.src) {
        .Immediate8 => |v| @as(u32, v),
        else => return error.InvalidOperand,
    };
    
    var cycles: u32 = 4;
    
    switch (inst.dst) {
        .DataReg => |reg| {
            const old_value = getRegisterValue(m68k.d[reg], inst.data_size);
            const result = old_value +% immediate;
            setRegisterValue(&m68k.d[reg], result, inst.data_size);
            setArithmeticFlags(m68k, old_value, immediate, result, inst.data_size, false);
        },
        .AddrReg => |reg| {
            m68k.a[reg] = m68k.a[reg] +% immediate;
            // No flags for address register
            cycles = 8; // ADDQ to An takes 8 cycles
        },
        else => {
            cycles += getEACycles(inst.dst, inst.data_size, true);
            cycles += getEACycles(inst.dst, inst.data_size, false);
            
            const old_value = try getOperandValue(m68k, inst.dst, inst.data_size);
            const result = old_value +% immediate;
            try setOperandValue(m68k, inst.dst, result, inst.data_size);
            setArithmeticFlags(m68k, old_value, immediate, result, inst.data_size, false);
        },
    }
    
    m68k.pc += 2;
    return cycles;
}

fn executeAddx(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    var cycles: u32 = switch (inst.data_size) {
        .Byte, .Word => 4,
        .Long => 8,
    };
    cycles += getEACycles(inst.src, inst.data_size, true);
    cycles += getEACycles(inst.dst, inst.data_size, true);
    cycles += getEACycles(inst.dst, inst.data_size, false);
    
    const x_bit: u32 = if (m68k.getFlag(cpu.M68k.FLAG_X)) 1 else 0;
    
    const src_value = try getOperandValue(m68k, inst.src, inst.data_size);
    const dst_value = try getOperandValue(m68k, inst.dst, inst.data_size);
    const result = dst_value +% src_value +% x_bit;
    
    try setOperandValue(m68k, inst.dst, result, inst.data_size);
    setArithmeticFlags(m68k, dst_value, src_value +% x_bit, result, inst.data_size, false);
    
    m68k.pc += 2;
    return cycles;
}

// ============================================================================
// SUB family
// ============================================================================

fn executeSub(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const opmode = (inst.opcode >> 6) & 0x7;
    const direction = (opmode >> 2) & 1;
    
    var cycles: u32 = switch (inst.data_size) {
        .Byte, .Word => 4,
        .Long => 6,
    };
    
    if (direction == 0) {
        // SUB <ea>, Dn
        const reg = switch (inst.dst) {
            .DataReg => |r| r,
            else => return error.InvalidOperand,
        };
        
        cycles += getEACycles(inst.src, inst.data_size, true);
        const src_value = try getOperandValue(m68k, inst.src, inst.data_size);
        const dst_value = getRegisterValue(m68k.d[reg], inst.data_size);
        const result = dst_value -% src_value;
        
        setRegisterValue(&m68k.d[reg], result, inst.data_size);
        setArithmeticFlags(m68k, dst_value, src_value, result, inst.data_size, true);
        
        m68k.pc += 2;
        return cycles;
    } else {
        // SUB Dn, <ea>
        const reg = switch (inst.src) {
            .DataReg => |r| r,
            else => return error.InvalidOperand,
        };
        
        cycles += getEACycles(inst.dst, inst.data_size, true);
        cycles += getEACycles(inst.dst, inst.data_size, false);
        
        const src_value = getRegisterValue(m68k.d[reg], inst.data_size);
        const dst_value = try getOperandValue(m68k, inst.dst, inst.data_size);
        const result = dst_value -% src_value;
        
        try setOperandValue(m68k, inst.dst, result, inst.data_size);
        setArithmeticFlags(m68k, dst_value, src_value, result, inst.data_size, true);
        
        m68k.pc += 2;
        return cycles;
    }
}

fn executeSuba(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const reg = switch (inst.dst) {
        .AddrReg => |r| r,
        else => return error.InvalidOperand,
    };
    
    var cycles: u32 = 8;
    cycles += getEACycles(inst.src, inst.data_size, true);
    
    var value = try getOperandValue(m68k, inst.src, inst.data_size);
    
    if (inst.data_size == .Word) {
        const signed: i16 = @bitCast(@as(u16, @truncate(value)));
        value = @bitCast(@as(i32, signed));
    }
    
    m68k.a[reg] = m68k.a[reg] -% value;
    
    m68k.pc += 2;
    return cycles;
}

fn executeSubi(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    var cycles: u32 = switch (inst.data_size) {
        .Byte, .Word => 8,
        .Long => 16,
    };
    cycles += getEACycles(inst.dst, inst.data_size, true);
    cycles += getEACycles(inst.dst, inst.data_size, false);
    
    const imm = try getOperandValue(m68k, inst.src, inst.data_size);
    const dst_value = try getOperandValue(m68k, inst.dst, inst.data_size);
    const result = dst_value -% imm;
    
    try setOperandValue(m68k, inst.dst, result, inst.data_size);
    setArithmeticFlags(m68k, dst_value, imm, result, inst.data_size, true);
    
    m68k.pc += 4;
    return cycles;
}

fn executeSubq(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const immediate = switch (inst.src) {
        .Immediate8 => |v| @as(u32, v),
        else => return error.InvalidOperand,
    };
    
    var cycles: u32 = 4;
    
    switch (inst.dst) {
        .DataReg => |reg| {
            const old_value = getRegisterValue(m68k.d[reg], inst.data_size);
            const result = old_value -% immediate;
            setRegisterValue(&m68k.d[reg], result, inst.data_size);
            setArithmeticFlags(m68k, old_value, immediate, result, inst.data_size, true);
        },
        .AddrReg => |reg| {
            m68k.a[reg] = m68k.a[reg] -% immediate;
            cycles = 8;
        },
        else => {
            cycles += getEACycles(inst.dst, inst.data_size, true);
            cycles += getEACycles(inst.dst, inst.data_size, false);
            
            const old_value = try getOperandValue(m68k, inst.dst, inst.data_size);
            const result = old_value -% immediate;
            try setOperandValue(m68k, inst.dst, result, inst.data_size);
            setArithmeticFlags(m68k, old_value, immediate, result, inst.data_size, true);
        },
    }
    
    m68k.pc += 2;
    return cycles;
}

fn executeSubx(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    var cycles: u32 = switch (inst.data_size) {
        .Byte, .Word => 4,
        .Long => 8,
    };
    cycles += getEACycles(inst.src, inst.data_size, true);
    cycles += getEACycles(inst.dst, inst.data_size, true);
    cycles += getEACycles(inst.dst, inst.data_size, false);
    
    const x_bit: u32 = if (m68k.getFlag(cpu.M68k.FLAG_X)) 1 else 0;
    
    const src_value = try getOperandValue(m68k, inst.src, inst.data_size);
    const dst_value = try getOperandValue(m68k, inst.dst, inst.data_size);
    const result = dst_value -% src_value -% x_bit;
    
    try setOperandValue(m68k, inst.dst, result, inst.data_size);
    setArithmeticFlags(m68k, dst_value, src_value +% x_bit, result, inst.data_size, true);
    
    m68k.pc += 2;
    return cycles;
}

// ============================================================================
// CMP family
// ============================================================================

fn executeCmp(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const reg = switch (inst.dst) {
        .DataReg => |r| r,
        else => return error.InvalidOperand,
    };
    
    var cycles: u32 = 4;
    cycles += getEACycles(inst.src, inst.data_size, true);
    
    const src_value = try getOperandValue(m68k, inst.src, inst.data_size);
    const dst_value = getRegisterValue(m68k.d[reg], inst.data_size);
    const result = dst_value -% src_value;
    
    setArithmeticFlags(m68k, dst_value, src_value, result, inst.data_size, true);
    
    m68k.pc += 2;
    return cycles;
}

fn executeCmpa(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const reg = switch (inst.dst) {
        .AddrReg => |r| r,
        else => return error.InvalidOperand,
    };
    
    var cycles: u32 = 6;
    cycles += getEACycles(inst.src, inst.data_size, true);
    
    var src_value = try getOperandValue(m68k, inst.src, inst.data_size);
    if (inst.data_size == .Word) {
        const signed: i16 = @bitCast(@as(u16, @truncate(src_value)));
        src_value = @bitCast(@as(i32, signed));
    }
    
    const result = m68k.a[reg] -% src_value;
    setArithmeticFlags(m68k, m68k.a[reg], src_value, result, .Long, true);
    
    m68k.pc += 2;
    return cycles;
}

fn executeCmpi(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    var cycles: u32 = switch (inst.data_size) {
        .Byte, .Word => 8,
        .Long => 14,
    };
    cycles += getEACycles(inst.dst, inst.data_size, true);
    
    const imm = try getOperandValue(m68k, inst.src, inst.data_size);
    const dst_value = try getOperandValue(m68k, inst.dst, inst.data_size);
    const result = dst_value -% imm;
    
    setArithmeticFlags(m68k, dst_value, imm, result, inst.data_size, true);
    
    m68k.pc += 4;
    return cycles;
}

// ============================================================================
// Logical operations
// ============================================================================

fn executeAnd(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const opmode = (inst.opcode >> 6) & 0x7;
    const direction = (opmode >> 2) & 1;
    
    var cycles: u32 = 4;
    
    if (direction == 0) {
        const reg = switch (inst.dst) {
            .DataReg => |r| r,
            else => return error.InvalidOperand,
        };
        
        cycles += getEACycles(inst.src, inst.data_size, true);
        const src_value = try getOperandValue(m68k, inst.src, inst.data_size);
        const dst_value = getRegisterValue(m68k.d[reg], inst.data_size);
        const result = dst_value & src_value;
        
        setRegisterValue(&m68k.d[reg], result, inst.data_size);
        m68k.setFlags(result, inst.data_size);
    } else {
        const reg = switch (inst.src) {
            .DataReg => |r| r,
            else => return error.InvalidOperand,
        };
        
        cycles += getEACycles(inst.dst, inst.data_size, true);
        cycles += getEACycles(inst.dst, inst.data_size, false);
        
        const src_value = getRegisterValue(m68k.d[reg], inst.data_size);
        const dst_value = try getOperandValue(m68k, inst.dst, inst.data_size);
        const result = dst_value & src_value;
        
        try setOperandValue(m68k, inst.dst, result, inst.data_size);
        m68k.setFlags(result, inst.data_size);
    }
    
    m68k.pc += 2;
    return cycles;
}

fn executeAndi(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    var cycles: u32 = switch (inst.data_size) {
        .Byte, .Word => 8,
        .Long => 16,
    };
    cycles += getEACycles(inst.dst, inst.data_size, true);
    cycles += getEACycles(inst.dst, inst.data_size, false);
    
    const imm = try getOperandValue(m68k, inst.src, inst.data_size);
    const dst_value = try getOperandValue(m68k, inst.dst, inst.data_size);
    const result = dst_value & imm;
    
    try setOperandValue(m68k, inst.dst, result, inst.data_size);
    m68k.setFlags(result, inst.data_size);
    
    m68k.pc += 4;
    return cycles;
}

fn executeOr(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const opmode = (inst.opcode >> 6) & 0x7;
    const direction = (opmode >> 2) & 1;
    
    var cycles: u32 = 4;
    
    if (direction == 0) {
        const reg = switch (inst.dst) {
            .DataReg => |r| r,
            else => return error.InvalidOperand,
        };
        
        cycles += getEACycles(inst.src, inst.data_size, true);
        const src_value = try getOperandValue(m68k, inst.src, inst.data_size);
        const dst_value = getRegisterValue(m68k.d[reg], inst.data_size);
        const result = dst_value | src_value;
        
        setRegisterValue(&m68k.d[reg], result, inst.data_size);
        m68k.setFlags(result, inst.data_size);
    } else {
        const reg = switch (inst.src) {
            .DataReg => |r| r,
            else => return error.InvalidOperand,
        };
        
        cycles += getEACycles(inst.dst, inst.data_size, true);
        cycles += getEACycles(inst.dst, inst.data_size, false);
        
        const src_value = getRegisterValue(m68k.d[reg], inst.data_size);
        const dst_value = try getOperandValue(m68k, inst.dst, inst.data_size);
        const result = dst_value | src_value;
        
        try setOperandValue(m68k, inst.dst, result, inst.data_size);
        m68k.setFlags(result, inst.data_size);
    }
    
    m68k.pc += 2;
    return cycles;
}

fn executeOri(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    var cycles: u32 = switch (inst.data_size) {
        .Byte, .Word => 8,
        .Long => 16,
    };
    cycles += getEACycles(inst.dst, inst.data_size, true);
    cycles += getEACycles(inst.dst, inst.data_size, false);
    
    const imm = try getOperandValue(m68k, inst.src, inst.data_size);
    const dst_value = try getOperandValue(m68k, inst.dst, inst.data_size);
    const result = dst_value | imm;
    
    try setOperandValue(m68k, inst.dst, result, inst.data_size);
    m68k.setFlags(result, inst.data_size);
    
    m68k.pc += 4;
    return cycles;
}

fn executeEor(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const reg = switch (inst.src) {
        .DataReg => |r| r,
        else => return error.InvalidOperand,
    };
    
    var cycles: u32 = 4;
    cycles += getEACycles(inst.dst, inst.data_size, true);
    cycles += getEACycles(inst.dst, inst.data_size, false);
    
    const src_value = getRegisterValue(m68k.d[reg], inst.data_size);
    const dst_value = try getOperandValue(m68k, inst.dst, inst.data_size);
    const result = dst_value ^ src_value;
    
    try setOperandValue(m68k, inst.dst, result, inst.data_size);
    m68k.setFlags(result, inst.data_size);
    
    m68k.pc += 2;
    return cycles;
}

fn executeEori(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    var cycles: u32 = switch (inst.data_size) {
        .Byte, .Word => 8,
        .Long => 16,
    };
    cycles += getEACycles(inst.dst, inst.data_size, true);
    cycles += getEACycles(inst.dst, inst.data_size, false);
    
    const imm = try getOperandValue(m68k, inst.src, inst.data_size);
    const dst_value = try getOperandValue(m68k, inst.dst, inst.data_size);
    const result = dst_value ^ imm;
    
    try setOperandValue(m68k, inst.dst, result, inst.data_size);
    m68k.setFlags(result, inst.data_size);
    
    m68k.pc += 4;
    return cycles;
}

fn executeNot(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    var cycles: u32 = if (inst.data_size == .Long) @as(u32, 6) else 4;
    cycles += getEACycles(inst.dst, inst.data_size, true);
    cycles += getEACycles(inst.dst, inst.data_size, false);
    
    const dst_value = try getOperandValue(m68k, inst.dst, inst.data_size);
    const result = ~dst_value;
    
    try setOperandValue(m68k, inst.dst, result, inst.data_size);
    m68k.setFlags(result, inst.data_size);
    
    m68k.pc += 2;
    return cycles;
}

// ============================================================================
// Multiply/Divide
// ============================================================================

fn executeMulu(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const reg = switch (inst.dst) {
        .DataReg => |r| r,
        else => return error.InvalidOperand,
    };
    
    var cycles: u32 = 38; // Base MULU cycles
    cycles += getEACycles(inst.src, .Word, true);
    
    const src_value: u16 = @truncate(try getOperandValue(m68k, inst.src, .Word));
    const dst_value: u16 = @truncate(m68k.d[reg]);
    
    const result: u32 = @as(u32, src_value) * @as(u32, dst_value);
    m68k.d[reg] = result;
    
    m68k.setFlag(cpu.M68k.FLAG_N, (result & 0x80000000) != 0);
    m68k.setFlag(cpu.M68k.FLAG_Z, result == 0);
    m68k.setFlag(cpu.M68k.FLAG_V, false);
    m68k.setFlag(cpu.M68k.FLAG_C, false);
    
    m68k.pc += 2;
    return cycles;
}

fn executeMuls(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const reg = switch (inst.dst) {
        .DataReg => |r| r,
        else => return error.InvalidOperand,
    };
    
    var cycles: u32 = 38;
    cycles += getEACycles(inst.src, .Word, true);
    
    const src_value: i16 = @bitCast(@as(u16, @truncate(try getOperandValue(m68k, inst.src, .Word))));
    const dst_value: i16 = @bitCast(@as(u16, @truncate(m68k.d[reg])));
    
    const result: i32 = @as(i32, src_value) * @as(i32, dst_value);
    m68k.d[reg] = @bitCast(result);
    
    m68k.setFlag(cpu.M68k.FLAG_N, result < 0);
    m68k.setFlag(cpu.M68k.FLAG_Z, result == 0);
    m68k.setFlag(cpu.M68k.FLAG_V, false);
    m68k.setFlag(cpu.M68k.FLAG_C, false);
    
    m68k.pc += 2;
    return cycles;
}

fn executeDivu(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const reg = switch (inst.dst) {
        .DataReg => |r| r,
        else => return error.InvalidOperand,
    };
    
    var cycles: u32 = 76;
    cycles += getEACycles(inst.src, .Word, true);
    
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
    return cycles;
}

fn executeDivs(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const reg = switch (inst.dst) {
        .DataReg => |r| r,
        else => return error.InvalidOperand,
    };
    
    var cycles: u32 = 76;
    cycles += getEACycles(inst.src, .Word, true);
    
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
    return cycles;
}

// ============================================================================
// Other operations
// ============================================================================

fn executeNeg(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    var cycles: u32 = switch (inst.data_size) {
        .Byte, .Word => 4,
        .Long => 6,
    };
    cycles += getEACycles(inst.dst, inst.data_size, true);
    cycles += getEACycles(inst.dst, inst.data_size, false);
    
    const old = try getOperandValue(m68k, inst.dst, inst.data_size);
    const result = 0 -% old;
    
    try setOperandValue(m68k, inst.dst, result, inst.data_size);
    setArithmeticFlags(m68k, 0, old, result, inst.data_size, true);
    
    m68k.pc += 2;
    return cycles;
}

fn executeNegx(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    var cycles: u32 = switch (inst.data_size) {
        .Byte, .Word => 4,
        .Long => 6,
    };
    cycles += getEACycles(inst.dst, inst.data_size, true);
    cycles += getEACycles(inst.dst, inst.data_size, false);
    
    const x_bit: u32 = if (m68k.getFlag(cpu.M68k.FLAG_X)) 1 else 0;
    const old = try getOperandValue(m68k, inst.dst, inst.data_size);
    const result = 0 -% old -% x_bit;
    
    try setOperandValue(m68k, inst.dst, result, inst.data_size);
    setArithmeticFlags(m68k, 0, old +% x_bit, result, inst.data_size, true);
    
    m68k.pc += 2;
    return cycles;
}

fn executeClr(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    var cycles: u32 = if (inst.data_size == .Long) @as(u32, 6) else 4;
    cycles += getEACycles(inst.dst, inst.data_size, false); // Only write
    
    try setOperandValue(m68k, inst.dst, 0, inst.data_size);
    
    m68k.setFlag(cpu.M68k.FLAG_N, false);
    m68k.setFlag(cpu.M68k.FLAG_Z, true);
    m68k.setFlag(cpu.M68k.FLAG_V, false);
    m68k.setFlag(cpu.M68k.FLAG_C, false);
    
    m68k.pc += 2;
    return cycles;
}

fn executeTst(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    var cycles: u32 = 4;
    cycles += getEACycles(inst.dst, inst.data_size, true);
    
    const value = try getOperandValue(m68k, inst.dst, inst.data_size);
    m68k.setFlags(value, inst.data_size);
    
    m68k.pc += 2;
    return cycles;
}

fn executeSwap(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
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
}

fn executeExt(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const reg = switch (inst.dst) {
        .DataReg => |r| r,
        else => return error.InvalidOperand,
    };
    
    if (inst.is_extb) {
        // EXTB.L (68020): byte -> long
        const byte_val: i8 = @bitCast(@as(u8, @truncate(m68k.d[reg])));
        m68k.d[reg] = @bitCast(@as(i32, byte_val));
    } else if (inst.data_size == .Word) {
        // EXT.W: byte -> word
        const byte_val: i8 = @bitCast(@as(u8, @truncate(m68k.d[reg])));
        const extended: i16 = byte_val;
        m68k.d[reg] = (m68k.d[reg] & 0xFFFF0000) | @as(u32, @bitCast(@as(i32, extended) & 0xFFFF));
    } else {
        // EXT.L: word -> long
        const word_val: i16 = @bitCast(@as(u16, @truncate(m68k.d[reg])));
        m68k.d[reg] = @bitCast(@as(i32, word_val));
    }
    
    m68k.setFlags(m68k.d[reg], inst.data_size);
    
    m68k.pc += 2;
    return 4;
}

fn executeLea(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const reg = switch (inst.dst) {
        .AddrReg => |r| r,
        else => return error.InvalidOperand,
    };
    
    var cycles: u32 = 4;
    cycles += getEACycles(inst.src, .Long, true);
    
    const ea = try calculateEA(m68k, inst.src);
    m68k.a[reg] = ea;
    
    m68k.pc += 2;
    return cycles;
}

// ============================================================================
// Program flow
// ============================================================================

fn executeRts(m68k: *cpu.M68k) !u32 {
    const sp = m68k.a[7];
    m68k.pc = try m68k.memory.read32(sp);
    m68k.a[7] = sp + 4;
    return 16;
}

fn executeRtr(m68k: *cpu.M68k) !u32 {
    // RTR: Return and Restore condition codes
    // Stack: [CCR (word)] [PC (long)]
    const sp = m68k.a[7];
    
    // Restore CCR (lower 8 bits)
    const ccr_word = try m68k.memory.read16(sp);
    m68k.sr = (m68k.sr & 0xFF00) | (ccr_word & 0x00FF);
    
    // Restore PC
    m68k.pc = try m68k.memory.read32(sp + 2);
    
    // ?�택 ?�인???�데?�트
    m68k.a[7] = sp + 6;
    
    return 20;
}

fn executeRte(m68k: *cpu.M68k) !u32 {
    // RTE: Return from Exception
    // Stack: [SR (word)] [PC (long)]
    const sp = m68k.a[7];
    
    // SR 복원 (?�체)
    m68k.sr = try m68k.memory.read16(sp);
    
    // Restore PC
    m68k.pc = try m68k.memory.read32(sp + 2);
    
    // ?�택 ?�인???�데?�트
    m68k.a[7] = sp + 6;
    
    return 20;
}

fn executeTrap(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    // TRAP: Software interrupt
    const vector = switch (inst.src) {
        .Immediate8 => |v| v,
        else => return error.InvalidOperand,
    };
    
    // TRAP vector??32-47 (0x80-0xBC)
    const vector_number: u8 = 32 + (vector & 0xF);
    const vector_addr = m68k.getExceptionVector(vector_number);
    
    // ?�재 SR�?PC�??�택???�??
    const sp = m68k.a[7] - 6;
    try m68k.memory.write32(sp + 2, m68k.pc + 2);
    try m68k.memory.write16(sp, m68k.sr);
    m68k.a[7] = sp;
    
    // 벡터 주소�??�프
    m68k.pc = try m68k.memory.read32(vector_addr);
    
    // Supervisor 모드 ?�정
    m68k.sr |= 0x2000;
    
    return 34;
}

fn executeBra(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const displacement = @as(i8, @bitCast(@as(u8, @truncate(inst.opcode & 0xFF))));
    if (displacement == 0) {
        const disp16 = try m68k.memory.read16(m68k.pc + 2);
        m68k.pc = @intCast(@as(i32, @intCast(m68k.pc)) + 2 + @as(i32, @intCast(@as(i16, @bitCast(disp16)))));
    } else {
        m68k.pc = @intCast(@as(i32, @intCast(m68k.pc)) + 2 + @as(i32, displacement));
    }
    return 10;
}

fn executeBcc(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
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
}

fn executeJsr(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    var cycles: u32 = 16; // Base JSR cycles
    cycles += getEACycles(inst.dst, .Long, true);
    
    const return_addr = m68k.pc + 2;
    m68k.a[7] -= 4;
    try m68k.memory.write32(m68k.a[7], return_addr);
    m68k.pc += 2;
    return cycles;
}

fn executeJmp(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    // JMP is like JSR but doesn't push return address
    var cycles: u32 = 8;
    cycles += getEACycles(inst.dst, .Long, true);
    
    const target = try calculateEA(m68k, inst.dst);
    m68k.pc = target;
    return cycles;
}

fn executeBsr(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    // BSR?� BRA + return address push
    const displacement = @as(i8, @bitCast(@as(u8, @truncate(inst.opcode & 0xFF))));
    const return_addr = m68k.pc + 2;
    
    // Return address�??�택??push
    m68k.a[7] -= 4;
    try m68k.memory.write32(m68k.a[7], return_addr);
    
    if (displacement == 0) {
        // 16비트 displacement
        const disp16 = try m68k.memory.read16(m68k.pc + 2);
        m68k.pc = @intCast(@as(i32, @intCast(m68k.pc)) + 2 + @as(i32, @intCast(@as(i16, @bitCast(disp16)))));
    } else {
        // 8비트 displacement
        m68k.pc = @intCast(@as(i32, @intCast(m68k.pc)) + 2 + @as(i32, displacement));
    }
    return 18;
}

fn executeDbcc(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const reg = switch (inst.dst) {
        .DataReg => |r| r,
        else => return error.InvalidOperand,
    };
    
    const condition: u4 = @truncate((inst.opcode >> 8) & 0xF);
    
    // If condition is true
    if (evaluateCondition(m68k, condition)) {
        m68k.pc += 4; // opcode + displacement word
        return 12;
    }
    
    // If condition is false
    const counter: i16 = @bitCast(@as(u16, @truncate(m68k.d[reg])));
    const new_counter = counter -% 1;
    m68k.d[reg] = (m68k.d[reg] & 0xFFFF0000) | @as(u32, @bitCast(@as(i32, new_counter) & 0xFFFF));
    
    // 카운?��? -1?�면 루프 종료
    if (new_counter == -1) {
        m68k.pc += 4;
        return 14;
    }
    
    // 분기 ?�행
    const displacement = try m68k.memory.read16(m68k.pc + 2);
    m68k.pc = @intCast(@as(i32, @intCast(m68k.pc)) + 2 + @as(i32, @intCast(@as(i16, @bitCast(displacement)))));
    return 10;
}

fn executeScc(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const condition: u4 = @truncate((inst.opcode >> 8) & 0xF);
    
    // Evaluate condition
    const condition_true = evaluateCondition(m68k, condition);
    
    var cycles: u32 = if (condition_true) @as(u32, 6) else 4;
    cycles += getEACycles(inst.dst, .Byte, false);
    
    // true = 0xFF, false = 0x00
    const value: u8 = if (condition_true) 0xFF else 0x00;
    
    try setOperandValue(m68k, inst.dst, @as(u32, value), .Byte);
    
    m68k.pc += 2;
    return cycles;
}

// ============================================================================
// ?�프??�?로테?�트 ?�산
// ============================================================================

fn executeAsl(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const shift_count = try getShiftCount(m68k, inst.src);
    var value = try getOperandValue(m68k, inst.dst, inst.data_size);
    
    const mask: u32 = switch (inst.data_size) {
        .Byte => 0xFF,
        .Word => 0xFFFF,
        .Long => 0xFFFFFFFF,
    };
    const sign_bit: u32 = switch (inst.data_size) {
        .Byte => 0x80,
        .Word => 0x8000,
        .Long => 0x80000000,
    };
    
    var last_bit_out: bool = false;
    var overflow = false;
    const original_sign = (value & sign_bit) != 0;
    
    for (0..shift_count) |_| {
        last_bit_out = (value & sign_bit) != 0;
        value = (value << 1) & mask;
        
        // Check if sign changed (overflow)
        const new_sign = (value & sign_bit) != 0;
        if (new_sign != original_sign) {
            overflow = true;
        }
    }
    
    try setOperandValue(m68k, inst.dst, value, inst.data_size);
    
    m68k.setFlag(cpu.M68k.FLAG_N, (value & sign_bit) != 0);
    m68k.setFlag(cpu.M68k.FLAG_Z, value == 0);
    m68k.setFlag(cpu.M68k.FLAG_V, overflow);
    m68k.setFlag(cpu.M68k.FLAG_C, last_bit_out);
    m68k.setFlag(cpu.M68k.FLAG_X, last_bit_out);
    
    m68k.pc += 2;
    return @as(u32, @intCast(6 + 2 * shift_count));
}

fn executeAsr(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const shift_count = try getShiftCount(m68k, inst.src);
    var value = try getOperandValue(m68k, inst.dst, inst.data_size);
    
    const mask: u32 = switch (inst.data_size) {
        .Byte => 0xFF,
        .Word => 0xFFFF,
        .Long => 0xFFFFFFFF,
    };
    const sign_bit: u32 = switch (inst.data_size) {
        .Byte => 0x80,
        .Word => 0x8000,
        .Long => 0x80000000,
    };
    
    var last_bit_out: bool = false;
    const sign_extend = (value & sign_bit) != 0;
    
    for (0..shift_count) |_| {
        last_bit_out = (value & 1) != 0;
        value = (value >> 1) & mask;  // Mask after shift to keep within size
        if (sign_extend) {
            value |= sign_bit;
        }
    }
    
    try setOperandValue(m68k, inst.dst, value, inst.data_size);
    
    m68k.setFlag(cpu.M68k.FLAG_N, (value & sign_bit) != 0);
    m68k.setFlag(cpu.M68k.FLAG_Z, value == 0);
    m68k.setFlag(cpu.M68k.FLAG_V, false);
    m68k.setFlag(cpu.M68k.FLAG_C, last_bit_out);
    m68k.setFlag(cpu.M68k.FLAG_X, last_bit_out);
    
    m68k.pc += 2;
    return @as(u32, @intCast(6 + 2 * shift_count));
}

fn executeLsl(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const shift_count = try getShiftCount(m68k, inst.src);
    var value = try getOperandValue(m68k, inst.dst, inst.data_size);
    
    const mask: u32 = switch (inst.data_size) {
        .Byte => 0xFF,
        .Word => 0xFFFF,
        .Long => 0xFFFFFFFF,
    };
    const sign_bit: u32 = switch (inst.data_size) {
        .Byte => 0x80,
        .Word => 0x8000,
        .Long => 0x80000000,
    };
    
    var last_bit_out: bool = false;
    
    for (0..shift_count) |_| {
        last_bit_out = (value & sign_bit) != 0;
        value = (value << 1) & mask;
    }
    
    try setOperandValue(m68k, inst.dst, value, inst.data_size);
    
    m68k.setFlag(cpu.M68k.FLAG_N, (value & sign_bit) != 0);
    m68k.setFlag(cpu.M68k.FLAG_Z, value == 0);
    m68k.setFlag(cpu.M68k.FLAG_V, false);
    m68k.setFlag(cpu.M68k.FLAG_C, last_bit_out);
    m68k.setFlag(cpu.M68k.FLAG_X, last_bit_out);
    
    m68k.pc += 2;
    return @as(u32, @intCast(6 + 2 * shift_count));
}

fn executeLsr(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const shift_count = try getShiftCount(m68k, inst.src);
    var value = try getOperandValue(m68k, inst.dst, inst.data_size);
    
    const mask: u32 = switch (inst.data_size) {
        .Byte => 0xFF,
        .Word => 0xFFFF,
        .Long => 0xFFFFFFFF,
    };
    const sign_bit: u32 = switch (inst.data_size) {
        .Byte => 0x80,
        .Word => 0x8000,
        .Long => 0x80000000,
    };
    
    var last_bit_out: bool = false;
    
    for (0..shift_count) |_| {
        last_bit_out = (value & 1) != 0;
        value = (value >> 1) & mask;
    }
    
    try setOperandValue(m68k, inst.dst, value, inst.data_size);
    
    m68k.setFlag(cpu.M68k.FLAG_N, (value & sign_bit) != 0);
    m68k.setFlag(cpu.M68k.FLAG_Z, value == 0);
    m68k.setFlag(cpu.M68k.FLAG_V, false);
    m68k.setFlag(cpu.M68k.FLAG_C, last_bit_out);
    m68k.setFlag(cpu.M68k.FLAG_X, last_bit_out);
    
    m68k.pc += 2;
    return @as(u32, @intCast(6 + 2 * shift_count));
}

fn executeRol(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const shift_count = try getShiftCount(m68k, inst.src);
    var value = try getOperandValue(m68k, inst.dst, inst.data_size);
    
    const mask: u32 = switch (inst.data_size) {
        .Byte => 0xFF,
        .Word => 0xFFFF,
        .Long => 0xFFFFFFFF,
    };
    const sign_bit: u32 = switch (inst.data_size) {
        .Byte => 0x80,
        .Word => 0x8000,
        .Long => 0x80000000,
    };
    
    var last_bit_out: bool = false;
    
    for (0..shift_count) |_| {
        const msb = (value & sign_bit) != 0;
        last_bit_out = msb;
        value = (value << 1) & mask;
        if (msb) {
            value |= 1;
        }
    }
    
    try setOperandValue(m68k, inst.dst, value, inst.data_size);
    
    m68k.setFlag(cpu.M68k.FLAG_N, (value & sign_bit) != 0);
    m68k.setFlag(cpu.M68k.FLAG_Z, value == 0);
    m68k.setFlag(cpu.M68k.FLAG_V, false);
    m68k.setFlag(cpu.M68k.FLAG_C, last_bit_out);
    // ROL doesn't affect X flag
    
    m68k.pc += 2;
    return @as(u32, @intCast(6 + 2 * shift_count));
}

fn executeRor(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const shift_count = try getShiftCount(m68k, inst.src);
    var value = try getOperandValue(m68k, inst.dst, inst.data_size);
    
    const mask: u32 = switch (inst.data_size) {
        .Byte => 0xFF,
        .Word => 0xFFFF,
        .Long => 0xFFFFFFFF,
    };
    const sign_bit: u32 = switch (inst.data_size) {
        .Byte => 0x80,
        .Word => 0x8000,
        .Long => 0x80000000,
    };
    
    var last_bit_out: bool = false;
    
    for (0..shift_count) |_| {
        const lsb = (value & 1) != 0;
        last_bit_out = lsb;
        value = (value >> 1) & mask;
        if (lsb) {
            value |= sign_bit;
        }
    }
    
    try setOperandValue(m68k, inst.dst, value, inst.data_size);
    
    m68k.setFlag(cpu.M68k.FLAG_N, (value & sign_bit) != 0);
    m68k.setFlag(cpu.M68k.FLAG_Z, value == 0);
    m68k.setFlag(cpu.M68k.FLAG_V, false);
    m68k.setFlag(cpu.M68k.FLAG_C, last_bit_out);
    // ROR doesn't affect X flag
    
    m68k.pc += 2;
    return @as(u32, @intCast(6 + 2 * shift_count));
}

fn executeRoxl(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const shift_count = try getShiftCount(m68k, inst.src);
    var value = try getOperandValue(m68k, inst.dst, inst.data_size);
    
    const mask: u32 = switch (inst.data_size) {
        .Byte => 0xFF,
        .Word => 0xFFFF,
        .Long => 0xFFFFFFFF,
    };
    const sign_bit: u32 = switch (inst.data_size) {
        .Byte => 0x80,
        .Word => 0x8000,
        .Long => 0x80000000,
    };
    
    var x_flag = m68k.getFlag(cpu.M68k.FLAG_X);
    
    for (0..shift_count) |_| {
        const msb = (value & sign_bit) != 0;
        value = (value << 1) & mask;
        if (x_flag) {
            value |= 1;
        }
        x_flag = msb;
    }
    
    try setOperandValue(m68k, inst.dst, value, inst.data_size);
    
    m68k.setFlag(cpu.M68k.FLAG_N, (value & sign_bit) != 0);
    m68k.setFlag(cpu.M68k.FLAG_Z, value == 0);
    m68k.setFlag(cpu.M68k.FLAG_V, false);
    m68k.setFlag(cpu.M68k.FLAG_C, x_flag);
    m68k.setFlag(cpu.M68k.FLAG_X, x_flag);
    
    m68k.pc += 2;
    return @as(u32, @intCast(6 + 2 * shift_count));
}

fn executeRoxr(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const shift_count = try getShiftCount(m68k, inst.src);
    var value = try getOperandValue(m68k, inst.dst, inst.data_size);
    
    const mask: u32 = switch (inst.data_size) {
        .Byte => 0xFF,
        .Word => 0xFFFF,
        .Long => 0xFFFFFFFF,
    };
    const sign_bit: u32 = switch (inst.data_size) {
        .Byte => 0x80,
        .Word => 0x8000,
        .Long => 0x80000000,
    };
    
    var x_flag = m68k.getFlag(cpu.M68k.FLAG_X);
    
    for (0..shift_count) |_| {
        const lsb = (value & 1) != 0;
        value = (value >> 1) & mask;
        if (x_flag) {
            value |= sign_bit;
        }
        x_flag = lsb;
    }
    
    try setOperandValue(m68k, inst.dst, value, inst.data_size);
    
    m68k.setFlag(cpu.M68k.FLAG_N, (value & sign_bit) != 0);
    m68k.setFlag(cpu.M68k.FLAG_Z, value == 0);
    m68k.setFlag(cpu.M68k.FLAG_V, false);
    m68k.setFlag(cpu.M68k.FLAG_C, x_flag);
    m68k.setFlag(cpu.M68k.FLAG_X, x_flag);
    
    m68k.pc += 2;
    return @as(u32, @intCast(6 + 2 * shift_count));
}

fn getShiftCount(m68k: *cpu.M68k, src: decoder.Operand) !u32 {
    return switch (src) {
        .Immediate8 => |v| @as(u32, v & 0x3F),  // Modulo 64
        .DataReg => |reg| m68k.d[reg] & 0x3F,
        else => 0,
    };
}

// ============================================================================
// Bit operations
// ============================================================================

fn executeBtst(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    var cycles: u32 = 4;
    cycles += getEACycles(inst.dst, .Long, true);
    
    const bit_num = try getBitNumber(m68k, inst.src, inst.dst);
    const value = try getOperandValue(m68k, inst.dst, .Long);
    
    const bit_set = (value & (@as(u32, 1) << @intCast(bit_num))) != 0;
    m68k.setFlag(cpu.M68k.FLAG_Z, !bit_set);
    
    // PC increment depends on whether immediate or register
    const pc_inc: u32 = switch (inst.src) {
        .Immediate8 => 4, // opcode + extension word
        else => 2,
    };
    m68k.pc += pc_inc;
    return cycles;
}

fn executeBset(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    var cycles: u32 = 8;
    cycles += getEACycles(inst.dst, .Long, true);
    cycles += getEACycles(inst.dst, .Long, false);
    
    const bit_num = try getBitNumber(m68k, inst.src, inst.dst);
    var value = try getOperandValue(m68k, inst.dst, .Long);
    
    const bit_set = (value & (@as(u32, 1) << @intCast(bit_num))) != 0;
    m68k.setFlag(cpu.M68k.FLAG_Z, !bit_set);
    
    value |= (@as(u32, 1) << @intCast(bit_num));
    try setOperandValue(m68k, inst.dst, value, .Long);
    
    const pc_inc: u32 = switch (inst.src) {
        .Immediate8 => 4,
        else => 2,
    };
    m68k.pc += pc_inc;
    return cycles;
}

fn executeBclr(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    var cycles: u32 = 8;
    cycles += getEACycles(inst.dst, .Long, true);
    cycles += getEACycles(inst.dst, .Long, false);
    
    const bit_num = try getBitNumber(m68k, inst.src, inst.dst);
    var value = try getOperandValue(m68k, inst.dst, .Long);
    
    const bit_set = (value & (@as(u32, 1) << @intCast(bit_num))) != 0;
    m68k.setFlag(cpu.M68k.FLAG_Z, !bit_set);
    
    value &= ~(@as(u32, 1) << @intCast(bit_num));
    try setOperandValue(m68k, inst.dst, value, .Long);
    
    const pc_inc: u32 = switch (inst.src) {
        .Immediate8 => 4,
        else => 2,
    };
    m68k.pc += pc_inc;
    return cycles;
}

fn executeBchg(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    var cycles: u32 = 8;
    cycles += getEACycles(inst.dst, .Long, true);
    cycles += getEACycles(inst.dst, .Long, false);
    
    const bit_num = try getBitNumber(m68k, inst.src, inst.dst);
    var value = try getOperandValue(m68k, inst.dst, .Long);
    
    const bit_set = (value & (@as(u32, 1) << @intCast(bit_num))) != 0;
    m68k.setFlag(cpu.M68k.FLAG_Z, !bit_set);
    
    value ^= (@as(u32, 1) << @intCast(bit_num));
    try setOperandValue(m68k, inst.dst, value, .Long);
    
    const pc_inc: u32 = switch (inst.src) {
        .Immediate8 => 4,
        else => 2,
    };
    m68k.pc += pc_inc;
    return cycles;
}

fn getBitNumber(m68k: *cpu.M68k, src: decoder.Operand, dst: decoder.Operand) !u32 {
    const bit_num_raw = switch (src) {
        .Immediate8 => blk: {
            // Read extension word for immediate bit number
            const ext_word = try m68k.memory.read16(m68k.pc + 2);
            break :blk @as(u32, ext_word);
        },
        .DataReg => |reg| m68k.d[reg],
        else => return error.InvalidOperand,
    };
    
    // Bit number modulo 32 for registers, modulo 8 for memory
    return switch (dst) {
        .DataReg => bit_num_raw & 31,
        else => bit_num_raw & 7,
    };
}

// ============================================================================
// Stack operations
// ============================================================================

fn executeLink(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const reg = switch (inst.dst) {
        .AddrReg => |r| r,
        else => return error.InvalidOperand,
    };
    
    // Read displacement from extension word
    const displacement_word = try m68k.memory.read16(m68k.pc + 2);
    const displacement: i16 = @bitCast(displacement_word);
    
    // Push An onto stack
    m68k.a[7] -= 4;
    try m68k.memory.write32(m68k.a[7], m68k.a[reg]);
    
    // An = SP
    m68k.a[reg] = m68k.a[7];
    
    // SP = SP + displacement
    m68k.a[7] = @intCast(@as(i32, @intCast(m68k.a[7])) + @as(i32, displacement));
    
    m68k.pc += 4; // opcode + extension word
    return 16;
}

fn executeUnlk(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const reg = switch (inst.dst) {
        .AddrReg => |r| r,
        else => return error.InvalidOperand,
    };
    
    // SP = An
    m68k.a[7] = m68k.a[reg];
    
    // Pop An from stack
    m68k.a[reg] = try m68k.memory.read32(m68k.a[7]);
    m68k.a[7] += 4;
    
    m68k.pc += 2;
    return 12;
}

fn executePea(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    var cycles: u32 = 12;
    cycles += getEACycles(inst.src, .Long, true);
    
    // Calculate effective address
    const ea = try calculateEA(m68k, inst.src);
    
    // Push EA onto stack
    m68k.a[7] -= 4;
    try m68k.memory.write32(m68k.a[7], ea);
    
    m68k.pc += 2;
    return cycles;
}

fn executeMovem(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    // Read register mask from extension word
    const mask = try m68k.memory.read16(m68k.pc + 2);
    
    // Determine direction from opcode
    const direction = (inst.opcode >> 10) & 1;
    
    if (direction == 0) {
        // Registers to memory
        return try executeMovemToMem(m68k, inst, mask);
    } else {
        // Memory to registers
        return try executeMovemFromMem(m68k, inst, mask);
    }
}

fn executeMovemToMem(m68k: *cpu.M68k, inst: *const decoder.Instruction, mask: u16) !u32 {
    // Get starting address
    var addr: u32 = switch (inst.dst) {
        .AddrReg => |reg| m68k.a[reg],
        .AddrIndirect => |reg| m68k.a[reg],
        .AddrPreDec => |reg| m68k.a[reg],
        .AddrPostInc => |reg| m68k.a[reg],
        .AddrDisplace => |info| m68k.a[info.reg] +% @as(u32, @bitCast(@as(i32, info.displacement))),
        .Address => |a| a,
        else => return error.InvalidOperand,
    };
    
    var count: u32 = 0;
    
    // For predecrement mode, registers are stored in reverse order
    const is_predec = switch (inst.dst) {
        .AddrPreDec => true,
        else => false,
    };
    
    if (is_predec) {
        // Store in reverse order: A7 to A0, then D7 to D0
        var bit: i32 = 15;
        while (bit >= 0) : (bit -= 1) {
            if ((mask & (@as(u16, 1) << @intCast(bit))) != 0) {
                const value = if (bit >= 8) m68k.a[@intCast(bit - 8)] else m68k.d[@intCast(bit)];
                
                if (inst.data_size == .Word) {
                    addr -%= 2;
                    try m68k.memory.write16(addr, @truncate(value));
                } else {
                    addr -%= 4;
                    try m68k.memory.write32(addr, value);
                }
                count += 1;
            }
        }
        
        // Update address register if predecrement
        switch (inst.dst) {
            .AddrPreDec => |reg| m68k.a[reg] = addr,
            else => {},
        }
    } else {
        // Normal order: D0 to D7, then A0 to A7
        for (0..16) |i| {
            if ((mask & (@as(u16, 1) << @intCast(i))) != 0) {
                const value = if (i < 8) m68k.d[i] else m68k.a[i - 8];
                
                if (inst.data_size == .Word) {
                    try m68k.memory.write16(addr, @truncate(value));
                    addr += 2;
                } else {
                    try m68k.memory.write32(addr, value);
                    addr += 4;
                }
                count += 1;
            }
        }
    }
    
    m68k.pc += 4; // opcode + extension word
    return 8 + count * (if (inst.data_size == .Word) @as(u32, 4) else 8);
}

fn executeMovemFromMem(m68k: *cpu.M68k, inst: *const decoder.Instruction, mask: u16) !u32 {
    var addr: u32 = switch (inst.dst) {
        .AddrReg => |reg| m68k.a[reg],
        .AddrIndirect => |reg| m68k.a[reg],
        .AddrPreDec => |reg| m68k.a[reg],
        .AddrPostInc => |reg| m68k.a[reg],
        .AddrDisplace => |info| m68k.a[info.reg] +% @as(u32, @bitCast(@as(i32, info.displacement))),
        .Address => |a| a,
        else => return error.InvalidOperand,
    };
    
    var count: u32 = 0;
    
    // Load in order: D0 to D7, then A0 to A7
    for (0..16) |i| {
        if ((mask & (@as(u16, 1) << @intCast(i))) != 0) {
            if (inst.data_size == .Word) {
                const value_word = try m68k.memory.read16(addr);
                const value: u32 = @bitCast(@as(i32, @as(i16, @bitCast(value_word)))); // Sign extend
                if (i < 8) {
                    m68k.d[i] = value;
                } else {
                    m68k.a[i - 8] = value;
                }
                addr += 2;
            } else {
                const value = try m68k.memory.read32(addr);
                if (i < 8) {
                    m68k.d[i] = value;
                } else {
                    m68k.a[i - 8] = value;
                }
                addr += 4;
            }
            count += 1;
        }
    }
    
    // Update address register if postincrement
    switch (inst.dst) {
        .AddrPostInc => |reg| m68k.a[reg] = addr,
        else => {},
    }
    
    m68k.pc += 4; // opcode + extension word
    return 8 + count * (if (inst.data_size == .Word) @as(u32, 4) else 8);
}

// ============================================================================
// Phase 2 Extended Instructions
// ============================================================================

fn executeExg(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    // EXG: Exchange registers
    // Format: 1100 Rx 1 OpMode Ry  
    // OpMode in bits 7-3 (with bit 8 always 1)
    const opcode = inst.opcode;
    const rx = (opcode >> 9) & 0x7;
    const ry = opcode & 0x7;
    const opmode = (opcode >> 3) & 0x1F;
    
    switch (opmode) {
        0x08 => {
            // Data register to data register
            const temp = m68k.d[rx];
            m68k.d[rx] = m68k.d[ry];
            m68k.d[ry] = temp;
        },
        0x09 => {
            // Address register to address register
            const temp = m68k.a[rx];
            m68k.a[rx] = m68k.a[ry];
            m68k.a[ry] = temp;
        },
        0x11 => {
            // Data register to address register
            const temp = m68k.d[rx];
            m68k.d[rx] = m68k.a[ry];
            m68k.a[ry] = temp;
        },
        else => return error.InvalidOpmode,
    }
    
    m68k.pc += 2;
    return 6;
}

fn executeCmpm(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    // CMPM: Compare memory (Ay)+ with (Ax)+
    // Format: 1011 Ax 1 Size 001 Ay
    const opcode = inst.opcode;
    const ax = (opcode >> 9) & 0x7;
    const ay = opcode & 0x7;
    const size = inst.data_size;
    
    const cycles: u32 = switch (size) {
        .Byte, .Word => 12,
        .Long => 20,
    };
    
    const bytes: u32 = switch (size) {
        .Byte => 1,
        .Word => 2,
        .Long => 4,
    };
    
    // Read from (Ay)+
    const src_val = switch (size) {
        .Byte => @as(u32, try m68k.memory.read8(m68k.a[ay])),
        .Word => @as(u32, try m68k.memory.read16(m68k.a[ay])),
        .Long => try m68k.memory.read32(m68k.a[ay]),
    };
    m68k.a[ay] += bytes;
    
    // Read from (Ax)+
    const dst_val = switch (size) {
        .Byte => @as(u32, try m68k.memory.read8(m68k.a[ax])),
        .Word => @as(u32, try m68k.memory.read16(m68k.a[ax])),
        .Long => try m68k.memory.read32(m68k.a[ax]),
    };
    m68k.a[ax] += bytes;
    
    // Perform subtraction (dst - src) for flags (same as CMP)
    const result = dst_val -% src_val;
    setArithmeticFlags(m68k, dst_val, src_val, result, size, true);
    
    m68k.pc += 2;
    return cycles;
}

fn executeChk(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    // CHK: Check register against bounds
    const reg = switch (inst.dst) {
        .DataReg => |r| r,
        else => return error.InvalidOperand,
    };
    
    var cycles: u32 = 10; // Base cycles
    cycles += getEACycles(inst.src, .Word, true);
    
    const bound = try getOperandValue(m68k, inst.src, .Word);
    const value = m68k.d[reg] & 0xFFFF;
    
    // Check if value is negative (bit 15 set) or > bound
    if ((value & 0x8000) != 0 or value > bound) {
        // CHK exception (vector 6)
        const vector_addr = m68k.getExceptionVector(6);
        
        // Save SR and PC
        const sp = m68k.a[7] - 6;
        try m68k.memory.write32(sp + 2, m68k.pc + 2);
        try m68k.memory.write16(sp, m68k.sr);
        m68k.a[7] = sp;
        
        // Set N flag if value < 0, clear if value > bound
        if ((value & 0x8000) != 0) {
            m68k.sr |= 0x08; // N flag
        } else {
            m68k.sr &= ~@as(u16, 0x08);
        }
        
        // Jump to exception handler
        m68k.pc = try m68k.memory.read32(vector_addr);
        m68k.sr |= 0x2000; // Supervisor mode
        
        return cycles + 34; // Exception overhead
    }
    
    m68k.pc += 2;
    return cycles;
}

fn executeTas(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    // TAS: Test and Set
    var cycles: u32 = 14;
    cycles += getEACycles(inst.dst, .Byte, true);
    cycles += getEACycles(inst.dst, .Byte, false);
    
    const addr = try calculateEA(m68k, inst.dst);
    
    // Read byte
    const value = try m68k.memory.read8(addr);
    
    // Test (set flags)
    m68k.setFlags(@as(u32, value), .Byte);
    
    // Set bit 7
    try m68k.memory.write8(addr, value | 0x80);
    
    m68k.pc += 2;
    return cycles;
}

fn executeAbcd(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    // ABCD: Add BCD with extend
    var cycles: u32 = 6;
    cycles += getEACycles(inst.src, .Byte, true);
    cycles += getEACycles(inst.dst, .Byte, true);
    cycles += getEACycles(inst.dst, .Byte, false);
    
    // TODO: Implement BCD addition logic
    m68k.pc += 2;
    return cycles;
}

fn executeSbcd(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    // SBCD: Subtract BCD with extend
    var cycles: u32 = 6;
    cycles += getEACycles(inst.src, .Byte, true);
    cycles += getEACycles(inst.dst, .Byte, true);
    cycles += getEACycles(inst.dst, .Byte, false);
    
    // TODO: Implement BCD subtraction logic
    m68k.pc += 2;
    return cycles;
}

fn executeNbcd(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    // NBCD: Negate BCD with extend
    var cycles: u32 = 6;
    cycles += getEACycles(inst.dst, .Byte, true);
    cycles += getEACycles(inst.dst, .Byte, false);
    
    // TODO: Implement BCD negation logic
    m68k.pc += 2;
    return cycles;
}

fn executeMovep(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    // MOVEP: Move Peripheral Data
    const cycles: u32 = switch (inst.data_size) {
        .Word => 16,
        .Long => 24,
        else => 16,
    };
    
    // TODO: Implement MOVEP logic
    m68k.pc += 2;
    return cycles;
}

// ============================================================================
// Helper functions
// ============================================================================

fn getRegisterValue(reg_value: u32, size: decoder.DataSize) u32 {
    return switch (size) {
        .Byte => reg_value & 0xFF,
        .Word => reg_value & 0xFFFF,
        .Long => reg_value,
    };
}

fn setRegisterValue(reg: *u32, value: u32, size: decoder.DataSize) void {
    switch (size) {
        .Byte => reg.* = (reg.* & 0xFFFFFF00) | (value & 0xFF),
        .Word => reg.* = (reg.* & 0xFFFF0000) | (value & 0xFFFF),
        .Long => reg.* = value,
    }
}

fn getOperandValue(m68k: *cpu.M68k, operand: decoder.Operand, size: decoder.DataSize) !u32 {
    return switch (operand) {
        .DataReg => |reg| getRegisterValue(m68k.d[reg], size),
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
        .AddrPostInc => |reg| {
            const addr = m68k.a[reg];
            const increment: u32 = switch (size) {
                .Byte => if (reg == 7) 2 else 1, // SP must stay even
                .Word => 2,
                .Long => 4,
            };
            m68k.a[reg] +%= increment;
            return switch (size) {
                .Byte => @as(u32, try m68k.memory.read8(addr)),
                .Word => @as(u32, try m68k.memory.read16(addr)),
                .Long => try m68k.memory.read32(addr),
            };
        },
        .AddrPreDec => |reg| {
            const decrement: u32 = switch (size) {
                .Byte => if (reg == 7) 2 else 1,
                .Word => 2,
                .Long => 4,
            };
            m68k.a[reg] -%= decrement;
            const addr = m68k.a[reg];
            return switch (size) {
                .Byte => @as(u32, try m68k.memory.read8(addr)),
                .Word => @as(u32, try m68k.memory.read16(addr)),
                .Long => try m68k.memory.read32(addr),
            };
        },
        .Address, .ComplexEA => {
            const addr = try calculateEA(m68k, operand);
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
            setRegisterValue(&m68k.d[reg], value, size);
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
        .AddrPostInc => |reg| {
            const addr = m68k.a[reg];
            const increment: u32 = switch (size) {
                .Byte => if (reg == 7) 2 else 1,
                .Word => 2,
                .Long => 4,
            };
            switch (size) {
                .Byte => try m68k.memory.write8(addr, @truncate(value)),
                .Word => try m68k.memory.write16(addr, @truncate(value)),
                .Long => try m68k.memory.write32(addr, value),
            }
            m68k.a[reg] +%= increment;
        },
        .AddrPreDec => |reg| {
            const decrement: u32 = switch (size) {
                .Byte => if (reg == 7) 2 else 1,
                .Word => 2,
                .Long => 4,
            };
            m68k.a[reg] -%= decrement;
            const addr = m68k.a[reg];
            switch (size) {
                .Byte => try m68k.memory.write8(addr, @truncate(value)),
                .Word => try m68k.memory.write16(addr, @truncate(value)),
                .Long => try m68k.memory.write32(addr, value),
            }
        },
        .Address, .ComplexEA => {
            const addr = try calculateEA(m68k, operand);
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
        .Address => |addr| addr,
        .ComplexEA => |info| {
            var addr: u32 = 0;
            
            // 1. Base register (An or PC)
            if (info.base_reg) |reg| {
                addr = m68k.a[reg];
            } else if (info.is_pc_relative) {
                // PC relative base (usually current opcode PC + 2)
                // ?�코?�에??bd�?계산?????��? 조정?�었?????�으?? ?�양???�라 처리
                addr = m68k.pc; 
            }
            
            // 2. Base displacement
            addr = addr +% @as(u32, @bitCast(info.base_disp));
            
            if (info.is_mem_indirect) {
                // Memory Indirect
                if (!info.is_post_indexed) {
                    // Pre-indexed: [ bd + An + Xn ] + od
                    if (info.index_reg) |idx| {
                        addr = addr +% try getIndexValue(m68k, idx);
                    }
                    addr = try m68k.memory.read32(addr);
                    addr = addr +% @as(u32, @bitCast(info.outer_disp));
                } else {
                    // Post-indexed: [ bd + An ] + Xn + od
                    addr = try m68k.memory.read32(addr);
                    if (info.index_reg) |idx| {
                        addr = addr +% try getIndexValue(m68k, idx);
                    }
                    addr = addr +% @as(u32, @bitCast(info.outer_disp));
                }
            } else {
                // No indirect: bd + An + Xn
                if (info.index_reg) |idx| {
                    addr = addr +% try getIndexValue(m68k, idx);
                }
            }
            
            return addr;
        },
        else => 0,
    };
}

fn getIndexValue(m68k: *const cpu.M68k, idx: anytype) !u32 {
    var val: u32 = if (idx.is_addr) m68k.a[idx.reg] else m68k.d[idx.reg];
    if (!idx.is_long) {
        val = @as(u32, @bitCast(@as(i32, @as(i16, @bitCast(@as(u16, @truncate(val)))))));
    }
    return val *% idx.scale;
}

fn setArithmeticFlags(m68k: *cpu.M68k, dst: u32, src: u32, result: u32, size: decoder.DataSize, is_sub: bool) void {
    const mask: u32 = switch (size) {
        .Byte => 0xFF,
        .Word => 0xFFFF,
        .Long => 0xFFFFFFFF,
    };
    const sign_bit: u32 = switch (size) {
        .Byte => 0x80,
        .Word => 0x8000,
        .Long => 0x80000000,
    };
    
    const masked_result = result & mask;
    const masked_dst = dst & mask;
    const masked_src = src & mask;
    
    // N and Z flags
    m68k.setFlag(cpu.M68k.FLAG_N, (masked_result & sign_bit) != 0);
    m68k.setFlag(cpu.M68k.FLAG_Z, masked_result == 0);
    
    // Carry and Extend flags
    if (is_sub) {
        m68k.setFlag(cpu.M68k.FLAG_C, masked_result > masked_dst);
        m68k.setFlag(cpu.M68k.FLAG_X, masked_result > masked_dst);
    } else {
        m68k.setFlag(cpu.M68k.FLAG_C, masked_result < masked_dst);
        m68k.setFlag(cpu.M68k.FLAG_X, masked_result < masked_dst);
    }
    
    // Overflow flag
    const dst_sign = (masked_dst & sign_bit) != 0;
    const src_sign = (masked_src & sign_bit) != 0;
    const result_sign = (masked_result & sign_bit) != 0;
    
    if (is_sub) {
        m68k.setFlag(cpu.M68k.FLAG_V, (dst_sign != src_sign) and (result_sign != dst_sign));
    } else {
        m68k.setFlag(cpu.M68k.FLAG_V, (dst_sign == src_sign) and (result_sign != dst_sign));
    }
}

fn evaluateCondition(m68k: *const cpu.M68k, condition: u4) bool {
    const c = m68k.getFlag(cpu.M68k.FLAG_C);
    const v = m68k.getFlag(cpu.M68k.FLAG_V);
    const z = m68k.getFlag(cpu.M68k.FLAG_Z);
    const n = m68k.getFlag(cpu.M68k.FLAG_N);
    
    return switch (condition) {
        0x0 => true,
        0x1 => false,
        0x2 => !c and !z,
        0x3 => c or z,
        0x4 => !c,
        0x5 => c,
        0x6 => !z,
        0x7 => z,
        0x8 => !v,
        0x9 => v,
        0xA => !n,
        0xB => n,
        0xC => (n and v) or (!n and !v),
        0xD => (n and !v) or (!n and v),
        0xE => (n and v and !z) or (!n and !v and !z),
        0xF => z or (n and !v) or (!n and v),
    };
}

// ============================================================================
// MOVEC - Move Control Register (68020)
// ============================================================================
fn executeMovec(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const control_reg = inst.control_reg orelse return error.InvalidInstruction;
    
    if (inst.is_to_control) {
        // Rc ??Rn (?��??�터 ??컨트�??��??�터)
        const value = switch (inst.src) {
            .DataReg => |reg| m68k.d[reg],
            .AddrReg => |reg| m68k.a[reg],
            else => return error.InvalidOperand,
        };
        
        switch (control_reg) {
            0x000 => {},  // SFC (Source Function Code) - 미구??
            0x001 => {},  // DFC (Destination Function Code) - 미구??
            0x002 => m68k.cacr = value,  // CACR (Cache Control Register)
            0x800 => {},  // USP (User Stack Pointer) - 미구??
            0x801 => m68k.vbr = value,   // VBR (Vector Base Register)
            0x802 => m68k.caar = value,  // CAAR (Cache Address Register)
            else => return error.InvalidControlRegister,
        }
    } else {
        // Rn ??Rc (컨트�??��??�터 ???��??�터)
        const value: u32 = switch (control_reg) {
            0x000 => 0,  // SFC
            0x001 => 0,  // DFC
            0x002 => m68k.cacr,  // CACR
            0x800 => 0,  // USP
            0x801 => m68k.vbr,   // VBR
            0x802 => m68k.caar,  // CAAR
            else => return error.InvalidControlRegister,
        };
        
        switch (inst.src) {
            .DataReg => |reg| m68k.d[reg] = value,
            .AddrReg => |reg| m68k.a[reg] = value,
            else => return error.InvalidOperand,
        }
    }
    
    m68k.pc += inst.size;
    return 12;  // 68020: 12 ?�이??
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

// ============================================================================
// Cycle-Accurate Helpers
// ============================================================================

// EA (Effective Address) calculation cycle costs
fn getEACycles(operand: decoder.Operand, size: decoder.DataSize, is_read: bool) u32 {
    _ = is_read; // For future use (read vs write may have different costs)
    
    return switch (operand) {
        // Register direct: 0 cycles (already in register)
        .DataReg, .AddrReg => 0,
        
        // Immediate: 4 cycles (word), 8 cycles (long)
        .Immediate8, .Immediate16 => 4,
        .Immediate32 => 8,
        
        // Simple memory access
        .AddrIndirect => 4,              // (An)
        .AddrPostInc => 4,               // (An)+
        .AddrPreDec => 6,                // -(An) - 2 extra for predec
        
        // With displacement
        .AddrDisplace => 8,              // d16(An)
        
        // Absolute
        .Address => if (size == .Long) 12 else 8,  // xxx.W or xxx.L
        
        // Bit field (68020)
        .BitField => 8,
        
        // Complex EA (68020)
        .ComplexEA => |info| blk: {
            var cycles: u32 = 8; // Base cost
            
            // Index register adds cycles
            if (info.index_reg != null) cycles += 2;
            
            // Memory indirect adds cycles
            if (info.is_mem_indirect) cycles += 4;
            
            // Post-indexed adds extra cycle
            if (info.is_post_indexed) cycles += 2;
            
            break :blk cycles;
        },
        
        .None => 0,
    };
}

// Base instruction cycle table (68000)
// These are minimum execution cycles, not including EA calculation
const InstructionCycles = struct {
    pub fn get(mnemonic: decoder.Mnemonic, size: decoder.DataSize, has_mem_dst: bool) u32 {
        return switch (mnemonic) {
            // Data movement (4-12 cycles)
            .MOVE => if (has_mem_dst) 8 else 4,
            .MOVEA => 4,
            .MOVEQ => 4,
            .LEA => 4,
            .PEA => 12,
            
            // Arithmetic (4-12 cycles base)
            .ADD, .SUB => switch (size) {
                .Byte, .Word => if (has_mem_dst) 8 else 4,
                .Long => if (has_mem_dst) 12 else 6,
            },
            .ADDA, .SUBA => if (size == .Long) 8 else 8,
            .ADDI, .SUBI => switch (size) {
                .Byte, .Word => if (has_mem_dst) 12 else 8,
                .Long => if (has_mem_dst) 20 else 16,
            },
            .ADDQ, .SUBQ => if (has_mem_dst) 8 else 4,
            .ADDX, .SUBX => switch (size) {
                .Byte, .Word => 4,
                .Long => 8,
            },
            
            // Multiply/Divide (heavy operations)
            .MULU => 38,  // + (2 * number of ones in multiplier)
            .MULS => 38,  // + (2 * number of ones in multiplier)
            .DIVU => 76,  // Worst case: 140 cycles
            .DIVS => 76,  // Worst case: 158 cycles
            
            // Logical (4-8 cycles)
            .AND, .OR, .EOR => if (has_mem_dst) 8 else 4,
            .ANDI, .ORI, .EORI => if (has_mem_dst) 12 else 8,
            .NOT => if (size == .Long) 6 else 4,
            
            // Compare (4-6 cycles)
            .CMP => 4,
            .CMPA => 6,
            .CMPI => if (size == .Long) 14 else 8,
            .CMPM => if (size == .Long) 20 else 12,
            .TST => 4,
            
            // Shift/Rotate (6 + 2*count cycles)
            .ASL, .ASR, .LSL, .LSR, .ROL, .ROR, .ROXL, .ROXR => 6,
            
            // Bit operations (4-12 cycles)
            .BTST => 4,
            .BSET, .BCLR, .BCHG => if (has_mem_dst) 8 else 8,
            
            // Negation (4-12 cycles)
            .NEG, .NEGX => switch (size) {
                .Byte, .Word => if (has_mem_dst) 8 else 4,
                .Long => if (has_mem_dst) 12 else 6,
            },
            .CLR => if (size == .Long) 6 else 4,
            
            // Extension
            .EXT => 4,
            .EXTB => 4,  // 68020: byte to long extension
            .SWAP => 4,
            
            // Program control
            .BRA => 10,
            .Bcc => 10,  // Taken: 10, Not taken: 8
            .BSR => 18,
            .JMP => 8,   // + EA cycles
            .JSR => 16,  // + EA cycles
            .RTS => 16,
            .RTR => 20,
            .RTE => 20,
            .DBcc => 10, // Not expired: 10, Expired: 14
            .Scc => 4,   // True: 6, False: 4
            
            // Trap/Exception
            .TRAP => 38,
            .TRAPV => 4, // No trap: 4, Trap: 38
            .CHK => 10,  // No trap: 10, Trap: 44+
            
            // Stack
            .LINK => 16,
            .UNLK => 12,
            
            // Special
            .TAS => 14,
            .NOP => 4,
            .ILLEGAL => 38,
            
            // BCD (18 cycles register, 30 cycles memory)
            .ABCD, .SBCD => if (has_mem_dst) 30 else 18,
            .NBCD => 8,
            
            // Data transfer
            .MOVEM => 12, // Base + 4/8 per register
            .EXG => 6,
            
            // 68020 exclusive
            .BFTST => 10,
            .BFSET, .BFCLR => 12,
            .BFEXTS, .BFEXTU => 10,
            .BFINS => 12,
            .BFFFO => 10,
            .CAS => 16,
            .CAS2 => 24,
            
            // 68020 Phase 2
            .RTD => 16,
            .BKPT => 10,
            .TRAPcc => 4,
            .CHK2 => 18,
            .CMP2 => 14,
            .PACK => 6,
            .UNPK => 8,
            .MULS_L => 43,
            .MULU_L => 43,
            .DIVS_L => 90,
            .DIVU_L => 90,
            
            .MOVEP => 16,
            else => 4, // Default fallback
        };
    }
};



// ============================================================================
// 68020 Exclusive Instructions
// ============================================================================

fn executeBftst(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    // BFTST <ea>{offset:width}
    // Test bit field and set Z flag
    const ext_word = try m68k.memory.read16(m68k.pc + 2);
    
    const offset = @as(u6, @truncate((ext_word >> 6) & 0x1F));
    var width = @as(u6, @truncate(ext_word & 0x1F));
    if (width == 0) width = 32; // width 0 means 32
    
    // Get EA value
    const value = try getOperandValue(m68k, inst.dst, .Long);
    
    // Extract bit field
    const mask = (@as(u32, 1) << width) - 1;
    const field = (value >> (32 - @as(u32, offset) - @as(u32, width))) & mask;
    
    // Set flags
    m68k.setFlag(cpu.M68k.FLAG_Z, field == 0);
    m68k.setFlag(cpu.M68k.FLAG_N, (field & (@as(u32, 1) << (width - 1))) != 0);
    m68k.setFlag(cpu.M68k.FLAG_V, false);
    m68k.setFlag(cpu.M68k.FLAG_C, false);
    
    m68k.pc += 4;
    return 10;
}

fn executeBfextu(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    // BFEXTU <ea>{offset:width}, Dn
    // Extract unsigned bit field to data register
    const ext_word = try m68k.memory.read16(m68k.pc + 2);
    
    const dn = @as(u3, @truncate((ext_word >> 12) & 0x7));
    const offset = @as(u6, @truncate((ext_word >> 6) & 0x1F));
    var width = @as(u6, @truncate(ext_word & 0x1F));
    if (width == 0) width = 32;
    
    // Get EA value
    const value = try getOperandValue(m68k, inst.src, .Long);
    
    // Extract bit field (unsigned)
    const mask = (@as(u32, 1) << width) - 1;
    const field = (value >> (32 - @as(u32, offset) - @as(u32, width))) & mask;
    
    // Store in Dn
    m68k.d[dn] = field;
    
    // Set flags
    m68k.setFlag(cpu.M68k.FLAG_Z, field == 0);
    m68k.setFlag(cpu.M68k.FLAG_N, false); // Unsigned, so always positive
    m68k.setFlag(cpu.M68k.FLAG_V, false);
    m68k.setFlag(cpu.M68k.FLAG_C, false);
    
    m68k.pc += 4;
    return 10;
}

fn executeBfexts(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    // BFEXTS <ea>{offset:width}, Dn
    // Extract signed bit field to data register
    const ext_word = try m68k.memory.read16(m68k.pc + 2);
    
    const dn = @as(u3, @truncate((ext_word >> 12) & 0x7));
    const offset = @as(u6, @truncate((ext_word >> 6) & 0x1F));
    var width = @as(u6, @truncate(ext_word & 0x1F));
    if (width == 0) width = 32;
    
    // Get EA value
    const value = try getOperandValue(m68k, inst.src, .Long);
    
    // Extract bit field
    const mask = (@as(u32, 1) << width) - 1;
    const field = (value >> (32 - @as(u32, offset) - @as(u32, width))) & mask;
    
    // Sign extend
    const sign_bit = @as(u32, 1) << (width - 1);
    const extended = if ((field & sign_bit) != 0)
        field | (~mask)  // Extend with 1s
    else
        field;  // Already positive
    
    // Store in Dn
    m68k.d[dn] = extended;
    
    // Set flags
    m68k.setFlag(cpu.M68k.FLAG_Z, field == 0);
    m68k.setFlag(cpu.M68k.FLAG_N, (field & sign_bit) != 0);
    m68k.setFlag(cpu.M68k.FLAG_V, false);
    m68k.setFlag(cpu.M68k.FLAG_C, false);
    
    m68k.pc += 4;
    return 10;
}

fn executeBfset(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    // BFSET <ea>{offset:width}
    // Set all bits in bit field to 1
    const ext_word = try m68k.memory.read16(m68k.pc + 2);
    
    const offset = @as(u6, @truncate((ext_word >> 6) & 0x1F));
    var width = @as(u6, @truncate(ext_word & 0x1F));
    if (width == 0) width = 32;
    
    // Get EA value
    const value = try getOperandValue(m68k, inst.dst, .Long);
    
    // Create mask for bit field
    const mask = (@as(u32, 1) << width) - 1;
    const shift = 32 - offset - width;
    const field_mask = mask << shift;
    
    // Set bits
    const new_value = value | field_mask;
    try setOperandValue(m68k, inst.dst, new_value, .Long);
    
    // Set flags (based on OLD value)
    const field = (value >> shift) & mask;
    m68k.setFlag(cpu.M68k.FLAG_Z, field == 0);
    m68k.setFlag(cpu.M68k.FLAG_N, (field & (@as(u32, 1) << (width - 1))) != 0);
    m68k.setFlag(cpu.M68k.FLAG_V, false);
    m68k.setFlag(cpu.M68k.FLAG_C, false);
    
    m68k.pc += 4;
    return 12;
}

fn executeBfclr(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    // BFCLR <ea>{offset:width}
    // Clear all bits in bit field to 0
    const ext_word = try m68k.memory.read16(m68k.pc + 2);
    
    const offset = @as(u6, @truncate((ext_word >> 6) & 0x1F));
    var width = @as(u6, @truncate(ext_word & 0x1F));
    if (width == 0) width = 32;
    
    // Get EA value
    const value = try getOperandValue(m68k, inst.dst, .Long);
    
    // Create mask for bit field
    const mask = (@as(u32, 1) << width) - 1;
    const shift = 32 - offset - width;
    const field_mask = mask << shift;
    
    // Clear bits
    const new_value = value & ~field_mask;
    try setOperandValue(m68k, inst.dst, new_value, .Long);
    
    // Set flags (based on OLD value)
    const field = (value >> shift) & mask;
    m68k.setFlag(cpu.M68k.FLAG_Z, field == 0);
    m68k.setFlag(cpu.M68k.FLAG_N, (field & (@as(u32, 1) << (width - 1))) != 0);
    m68k.setFlag(cpu.M68k.FLAG_V, false);
    m68k.setFlag(cpu.M68k.FLAG_C, false);
    
    m68k.pc += 4;
    return 12;
}

fn executeBfins(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    // BFINS Dn, <ea>{offset:width}
    // Insert low bits of Dn into bit field
    const ext_word = try m68k.memory.read16(m68k.pc + 2);
    
    const dn = @as(u3, @truncate((ext_word >> 12) & 0x7));
    const offset = @as(u6, @truncate((ext_word >> 6) & 0x1F));
    var width = @as(u6, @truncate(ext_word & 0x1F));
    if (width == 0) width = 32;
    
    // Get source value from Dn
    const src = m68k.d[dn];
    
    // Get EA value
    const value = try getOperandValue(m68k, inst.dst, .Long);
    
    // Create masks
    const mask = (@as(u32, 1) << width) - 1;
    const shift = 32 - offset - width;
    const field_mask = mask << shift;
    
    // Insert bits
    const new_value = (value & ~field_mask) | ((src & mask) << shift);
    try setOperandValue(m68k, inst.dst, new_value, .Long);
    
    // Set flags (based on inserted value)
    const field = src & mask;
    m68k.setFlag(cpu.M68k.FLAG_Z, field == 0);
    m68k.setFlag(cpu.M68k.FLAG_N, (field & (@as(u32, 1) << (width - 1))) != 0);
    m68k.setFlag(cpu.M68k.FLAG_V, false);
    m68k.setFlag(cpu.M68k.FLAG_C, false);
    
    m68k.pc += 4;
    return 12;
}

fn executeBfffo(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    // BFFFO <ea>{offset:width}, Dn
    // Find first one in bit field
    const ext_word = try m68k.memory.read16(m68k.pc + 2);
    
    const dn = @as(u3, @truncate((ext_word >> 12) & 0x7));
    const offset = @as(u6, @truncate((ext_word >> 6) & 0x1F));
    var width = @as(u6, @truncate(ext_word & 0x1F));
    if (width == 0) width = 32;
    
    // Get EA value
    const value = try getOperandValue(m68k, inst.src, .Long);
    
    // Extract bit field
    const mask = (@as(u32, 1) << width) - 1;
    const shift = 32 - offset - width;
    const field = (value >> shift) & mask;
    
    // Find first one
    var first_one: u32 = offset + width;  // Default: not found
    var i: u5 = 0;
    while (i < width) : (i += 1) {
        if ((field & (@as(u32, 1) << (width - 1 - i))) != 0) {
            first_one = offset + i;
            break;
        }
    }
    
    // Store result in Dn
    m68k.d[dn] = first_one;
    
    // Set flags
    m68k.setFlag(cpu.M68k.FLAG_Z, field == 0);
    m68k.setFlag(cpu.M68k.FLAG_N, (field & (@as(u32, 1) << (width - 1))) != 0);
    m68k.setFlag(cpu.M68k.FLAG_V, false);
    m68k.setFlag(cpu.M68k.FLAG_C, false);
    
    m68k.pc += 4;
    return 10;
}

fn executeCas(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    // CAS Dc, Du, <ea>
    // Compare and Swap (atomic)
    const ext_word = try m68k.memory.read16(m68k.pc + 2);
    
    const dc = @as(u3, @truncate(ext_word & 0x7));  // Compare register
    const du = @as(u3, @truncate((ext_word >> 6) & 0x7));  // Update register
    
    // Get operand value from memory
    const mem_value = try getOperandValue(m68k, inst.dst, inst.data_size);
    const compare_value = getRegisterValue(m68k.d[dc], inst.data_size);
    
    // Compare
    if (mem_value == compare_value) {
        // Equal: write Du to memory
        const update_value = getRegisterValue(m68k.d[du], inst.data_size);
        try setOperandValue(m68k, inst.dst, update_value, inst.data_size);
        m68k.setFlag(cpu.M68k.FLAG_Z, true);
    } else {
        // Not equal: load memory to Dc
        setRegisterValue(&m68k.d[dc], mem_value, inst.data_size);
        m68k.setFlag(cpu.M68k.FLAG_Z, false);
    }
    
    // Set other flags
    const result = mem_value -% compare_value;
    setArithmeticFlags(m68k, mem_value, compare_value, result, inst.data_size, true);
    
    m68k.pc += 4;
    return 16;
}

fn executeCas2(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    // CAS2 Dc1:Dc2, Du1:Du2, (Rn1):(Rn2)
    // Dual Compare and Swap
    // This is very complex - stub implementation
    _ = inst;
    
    m68k.pc += 6;  // opcode + 2 extension words
    return 24;
}


// RTD - Return and Deallocate
fn executeRtd(m68k: *cpu.M68k, _: *const decoder.Instruction) !u32 {
    // RTD #displacement
    // Pop return address, then add displacement to SP
    
    // Read displacement from extension word
    const displacement = try m68k.memory.read16(m68k.pc + 2);
    const disp_signed: i16 = @bitCast(displacement);
    
    // Pop return address from stack
    const sp = m68k.a[7];
    m68k.pc = try m68k.memory.read32(sp);
    
    // Deallocate stack: SP = SP + 4 + displacement
    m68k.a[7] = @intCast(@as(i32, @intCast(sp)) + 4 + @as(i32, disp_signed));
    
    return 16; // RTD takes 16 cycles
}

// BKPT - Breakpoint
fn executeBkpt(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    // BKPT #vector
    // Breakpoint for debugging
    
    const vector = inst.opcode & 0x7; // 3-bit vector (0-7)
    
    // In a real implementation, this would trigger a breakpoint exception
    // For now, we'll treat it as a special trap
    
    // Save PC and SR
    const sp = m68k.a[7] - 6;
    try m68k.memory.write32(sp + 2, m68k.pc + 2);
    try m68k.memory.write16(sp, m68k.sr);
    m68k.a[7] = sp;
    
    // Jump to exception vector (offset 12 + vector)
    const vector_addr = m68k.getExceptionVector(@intCast(12 + vector));
    m68k.pc = try m68k.memory.read32(vector_addr);
    
    m68k.sr |= 0x2000; // Supervisor mode
    
    return 10; // BKPT base cycles
}

// TRAPcc - Trap on Condition
fn executeTrapcc(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    // TRAPcc / TRAPcc.W #data / TRAPcc.L #data
    
    const condition: u4 = @truncate((inst.opcode >> 8) & 0xF);
    const opmode = inst.opcode & 0x7; // 010=word, 011=long, 100=no operand
    
    var cycles: u32 = 4;
    var pc_inc: u32 = 2;
    
    // Read immediate data if present
    if (opmode == 2) { // .W
        pc_inc = 4;
        cycles += 2;
    } else if (opmode == 3) { // .L
        pc_inc = 6;
        cycles += 4;
    }
    
    // Evaluate condition
    if (evaluateCondition(m68k, condition)) {
        // Condition true - take trap
        const sp = m68k.a[7] - 6;
        try m68k.memory.write32(sp + 2, m68k.pc + pc_inc);
        try m68k.memory.write16(sp, m68k.sr);
        m68k.a[7] = sp;
        
        // TRAPcc uses vector 7
        const vector_addr = m68k.getExceptionVector(7);
        m68k.pc = try m68k.memory.read32(vector_addr);
        m68k.sr |= 0x2000; // Supervisor mode
        
        return cycles + 30; // Exception overhead
    }
    
    // Condition false - no trap
    m68k.pc += pc_inc;
    return cycles;
}

// CHK2 - Check Register Against Bounds (Range Check)
fn executeChk2(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    // CHK2 <ea>, Rn
    // Check if Rn is within bounds [lower, upper]
    
    var cycles: u32 = 18;
    cycles += getEACycles(inst.src, inst.data_size, true);
    
    const ext_word = try m68k.memory.read16(m68k.pc + 2);
    const rn = @as(u3, @truncate((ext_word >> 12) & 0x7));
    const is_addr = (ext_word & 0x8000) != 0;
    
    // Get register value
    const reg_value = if (is_addr) m68k.a[rn] else m68k.d[rn];
    
    // Get bounds from memory (two consecutive values)
    const ea_addr = try calculateEA(m68k, inst.src);
    
    const lower = switch (inst.data_size) {
        .Byte => @as(u32, try m68k.memory.read8(ea_addr)),
        .Word => @as(u32, try m68k.memory.read16(ea_addr)),
        .Long => try m68k.memory.read32(ea_addr),
    };
    
    const upper = switch (inst.data_size) {
        .Byte => @as(u32, try m68k.memory.read8(ea_addr + 1)),
        .Word => @as(u32, try m68k.memory.read16(ea_addr + 2)),
        .Long => try m68k.memory.read32(ea_addr + 4),
    };
    
    // Check bounds
    const masked_value = switch (inst.data_size) {
        .Byte => reg_value & 0xFF,
        .Word => reg_value & 0xFFFF,
        .Long => reg_value,
    };
    
    if (masked_value < lower or masked_value > upper) {
        // Out of bounds - CHK exception
        const sp = m68k.a[7] - 6;
        try m68k.memory.write32(sp + 2, m68k.pc + 4);
        try m68k.memory.write16(sp, m68k.sr);
        m68k.a[7] = sp;
        
        const vector_addr = m68k.getExceptionVector(6);
        m68k.pc = try m68k.memory.read32(vector_addr);
        m68k.sr |= 0x2000;
        
        return cycles + 30;
    }
    
    // Set C flag if value == lower or upper
    m68k.setFlag(cpu.M68k.FLAG_C, masked_value == lower or masked_value == upper);
    
    m68k.pc += 4;
    return cycles;
}

// CMP2 - Compare Register Against Bounds
fn executeCmp2(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    // CMP2 <ea>, Rn
    // Similar to CHK2 but doesn't trap, just sets flags
    
    var cycles: u32 = 14;
    cycles += getEACycles(inst.src, inst.data_size, true);
    
    const ext_word = try m68k.memory.read16(m68k.pc + 2);
    const rn = @as(u3, @truncate((ext_word >> 12) & 0x7));
    const is_addr = (ext_word & 0x8000) != 0;
    
    const reg_value = if (is_addr) m68k.a[rn] else m68k.d[rn];
    
    const ea_addr = try calculateEA(m68k, inst.src);
    
    const lower = switch (inst.data_size) {
        .Byte => @as(u32, try m68k.memory.read8(ea_addr)),
        .Word => @as(u32, try m68k.memory.read16(ea_addr)),
        .Long => try m68k.memory.read32(ea_addr),
    };
    
    const upper = switch (inst.data_size) {
        .Byte => @as(u32, try m68k.memory.read8(ea_addr + 1)),
        .Word => @as(u32, try m68k.memory.read16(ea_addr + 2)),
        .Long => try m68k.memory.read32(ea_addr + 4),
    };
    
    const masked_value = switch (inst.data_size) {
        .Byte => reg_value & 0xFF,
        .Word => reg_value & 0xFFFF,
        .Long => reg_value,
    };
    
    // Set flags
    const in_bounds = masked_value >= lower and masked_value <= upper;
    m68k.setFlag(cpu.M68k.FLAG_Z, in_bounds);
    m68k.setFlag(cpu.M68k.FLAG_C, masked_value == lower or masked_value == upper);
    
    m68k.pc += 4;
    return cycles;
}

// PACK - Pack BCD
fn executePack(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    // PACK -(Ax), -(Ay), #adjustment
    // or PACK Dx, Dy, #adjustment
    
    const adjustment = try m68k.memory.read16(m68k.pc + 2);
    
    const src_reg = switch (inst.src) {
        .DataReg => |r| r,
        .AddrPreDec => |r| r,
        else => return error.InvalidOperand,
    };
    
    const dst_reg = switch (inst.dst) {
        .DataReg => |r| r,
        .AddrPreDec => |r| r,
        else => return error.InvalidOperand,
    };
    
    var cycles: u32 = 6;
    
    switch (inst.src) {
        .DataReg => {
            // Register to register
            const src_value = m68k.d[src_reg] & 0xFFFF;
            const adjusted = src_value +% adjustment;
            
            // Pack: take low nibble and high nibble
            const low_nibble = adjusted & 0x0F;
            const high_nibble = (adjusted >> 8) & 0x0F;
            const packed_value = (high_nibble << 4) | low_nibble;
            
            m68k.d[dst_reg] = (m68k.d[dst_reg] & 0xFFFFFF00) | packed_value;
        },
        .AddrPreDec => {
            // Memory to memory
            cycles += 8;
            
            // Read source (2 bytes)
            m68k.a[src_reg] -= 2;
            const src_value = try m68k.memory.read16(m68k.a[src_reg]);
            const adjusted = src_value +% adjustment;
            
            // Pack
            const low_nibble = adjusted & 0x0F;
            const high_nibble = (adjusted >> 8) & 0x0F;
            const packed_value: u8 = @truncate((high_nibble << 4) | low_nibble);
            
            // Write destination (1 byte)
            m68k.a[dst_reg] -= 1;
            try m68k.memory.write8(m68k.a[dst_reg], packed_value);
        },
        else => return error.InvalidOperand,
    }
    
    m68k.pc += 4;
    return cycles;
}

// UNPK - Unpack BCD
fn executeUnpk(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    // UNPK -(Ax), -(Ay), #adjustment
    // or UNPK Dx, Dy, #adjustment
    
    const adjustment = try m68k.memory.read16(m68k.pc + 2);
    
    const src_reg = switch (inst.src) {
        .DataReg => |r| r,
        .AddrPreDec => |r| r,
        else => return error.InvalidOperand,
    };
    
    const dst_reg = switch (inst.dst) {
        .DataReg => |r| r,
        .AddrPreDec => |r| r,
        else => return error.InvalidOperand,
    };
    
    var cycles: u32 = 8;
    
    switch (inst.src) {
        .DataReg => {
            // Register to register
            const packed_value = m68k.d[src_reg] & 0xFF;
            
            // Unpack: split nibbles
            const low_nibble = packed_value & 0x0F;
            const high_nibble = (packed_value >> 4) & 0x0F;
            const unpacked: u16 = @intCast((high_nibble << 8) | low_nibble);
            
            const result = unpacked +% adjustment;
            m68k.d[dst_reg] = (m68k.d[dst_reg] & 0xFFFF0000) | result;
        },
        .AddrPreDec => {
            // Memory to memory
            cycles += 5;
            
            // Read source (1 byte)
            m68k.a[src_reg] -= 1;
            const packed_value = try m68k.memory.read8(m68k.a[src_reg]);
            
            // Unpack
            const low_nibble = packed_value & 0x0F;
            const high_nibble = (packed_value >> 4) & 0x0F;
            const unpacked: u16 = @intCast((high_nibble << 8) | low_nibble);
            
            const result = unpacked +% adjustment;
            
            // Write destination (2 bytes)
            m68k.a[dst_reg] -= 2;
            try m68k.memory.write16(m68k.a[dst_reg], result);
        },
        else => return error.InvalidOperand,
    }
    
    m68k.pc += 4;
    return cycles;
}


// MULS.L - Multiply Signed 32x32 -> 64
fn executeMulsL(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    // MULS.L <ea>, Dl (32x32->32)
    // MULS.L <ea>, Dh:Dl (32x32->64)
    
    var cycles: u32 = 43;
    cycles += getEACycles(inst.src, .Long, true);
    
    const ext_word = try m68k.memory.read16(m68k.pc + 2);
    const dl = @as(u3, @truncate(ext_word & 0x7)); // Low result register
    const dh = @as(u3, @truncate((ext_word >> 12) & 0x7)); // High result register
    const is_64bit = (ext_word & 0x0400) != 0; // Dh:Dl format
    
    const src_value: i32 = @bitCast(try getOperandValue(m68k, inst.src, .Long));
    const dst_value: i32 = @bitCast(m68k.d[dl]);
    
    if (is_64bit) {
        // 64-bit result
        const result: i64 = @as(i64, src_value) * @as(i64, dst_value);
        m68k.d[dl] = @bitCast(@as(i32, @truncate(result))); // Low 32 bits
        m68k.d[dh] = @bitCast(@as(i32, @truncate(result >> 32))); // High 32 bits
        
        // Set flags based on 64-bit result
        m68k.setFlag(cpu.M68k.FLAG_N, result < 0);
        m68k.setFlag(cpu.M68k.FLAG_Z, result == 0);
        m68k.setFlag(cpu.M68k.FLAG_V, false);
        m68k.setFlag(cpu.M68k.FLAG_C, false);
    } else {
        // 32-bit result (overflow if doesn't fit)
        const result: i64 = @as(i64, src_value) * @as(i64, dst_value);
        const result32: i32 = @truncate(result);
        m68k.d[dl] = @bitCast(result32);
        
        // Check overflow
        const overflow = (result < -2147483648 or result > 2147483647);
        
        m68k.setFlag(cpu.M68k.FLAG_N, result32 < 0);
        m68k.setFlag(cpu.M68k.FLAG_Z, result32 == 0);
        m68k.setFlag(cpu.M68k.FLAG_V, overflow);
        m68k.setFlag(cpu.M68k.FLAG_C, false);
    }
    
    m68k.pc += 4;
    return cycles;
}

// MULU.L - Multiply Unsigned 32x32 -> 64
fn executeMuluL(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    // MULU.L <ea>, Dl (32x32->32)
    // MULU.L <ea>, Dh:Dl (32x32->64)
    
    var cycles: u32 = 43;
    cycles += getEACycles(inst.src, .Long, true);
    
    const ext_word = try m68k.memory.read16(m68k.pc + 2);
    const dl = @as(u3, @truncate(ext_word & 0x7));
    const dh = @as(u3, @truncate((ext_word >> 12) & 0x7));
    const is_64bit = (ext_word & 0x0400) != 0;
    
    const src_value: u32 = try getOperandValue(m68k, inst.src, .Long);
    const dst_value: u32 = m68k.d[dl];
    
    if (is_64bit) {
        // 64-bit result
        const result: u64 = @as(u64, src_value) * @as(u64, dst_value);
        m68k.d[dl] = @truncate(result); // Low 32 bits
        m68k.d[dh] = @truncate(result >> 32); // High 32 bits
        
        m68k.setFlag(cpu.M68k.FLAG_N, (result & 0x8000000000000000) != 0);
        m68k.setFlag(cpu.M68k.FLAG_Z, result == 0);
        m68k.setFlag(cpu.M68k.FLAG_V, false);
        m68k.setFlag(cpu.M68k.FLAG_C, false);
    } else {
        // 32-bit result
        const result: u64 = @as(u64, src_value) * @as(u64, dst_value);
        const result32: u32 = @truncate(result);
        m68k.d[dl] = result32;
        
        const overflow = (result > 0xFFFFFFFF);
        
        m68k.setFlag(cpu.M68k.FLAG_N, (result32 & 0x80000000) != 0);
        m68k.setFlag(cpu.M68k.FLAG_Z, result32 == 0);
        m68k.setFlag(cpu.M68k.FLAG_V, overflow);
        m68k.setFlag(cpu.M68k.FLAG_C, false);
    }
    
    m68k.pc += 4;
    return cycles;
}

// DIVS.L - Divide Signed 64/32 -> 32q:32r
fn executeDivsL(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    // DIVS.L <ea>, Dq (32/32->32q)
    // DIVS.L <ea>, Dr:Dq (64/32->32q, remainder in Dr)
    
    var cycles: u32 = 90;
    cycles += getEACycles(inst.src, .Long, true);
    
    const ext_word = try m68k.memory.read16(m68k.pc + 2);
    const dq = @as(u3, @truncate(ext_word & 0x7)); // Quotient register
    const dr = @as(u3, @truncate((ext_word >> 12) & 0x7)); // Remainder register
    const is_64bit = (ext_word & 0x0400) != 0;
    
    const divisor: i32 = @bitCast(try getOperandValue(m68k, inst.src, .Long));
    
    if (divisor == 0) {
        return error.DivideByZero;
    }
    
    if (is_64bit) {
        // 64-bit dividend
        const dividend_low: u32 = m68k.d[dq];
        const dividend_high: u32 = m68k.d[dr];
        const dividend: i64 = @bitCast((@as(u64, dividend_high) << 32) | @as(u64, dividend_low));
        
        const quotient: i64 = @divTrunc(dividend, divisor);
        const remainder: i64 = @rem(dividend, divisor);
        
        // Check overflow
        if (quotient < -2147483648 or quotient > 2147483647) {
            m68k.setFlag(cpu.M68k.FLAG_V, true);
            m68k.pc += 4;
            return cycles;
        }
        
        m68k.d[dq] = @bitCast(@as(i32, @truncate(quotient)));
        m68k.d[dr] = @bitCast(@as(i32, @truncate(remainder)));
        
        m68k.setFlag(cpu.M68k.FLAG_N, quotient < 0);
        m68k.setFlag(cpu.M68k.FLAG_Z, quotient == 0);
        m68k.setFlag(cpu.M68k.FLAG_V, false);
        m68k.setFlag(cpu.M68k.FLAG_C, false);
    } else {
        // 32-bit dividend
        const dividend: i32 = @bitCast(m68k.d[dq]);
        const quotient: i32 = @divTrunc(dividend, divisor);
        _ = @rem(dividend, divisor); // remainder not stored in 32-bit mode
        
        m68k.d[dq] = @bitCast(quotient);
        
        m68k.setFlag(cpu.M68k.FLAG_N, quotient < 0);
        m68k.setFlag(cpu.M68k.FLAG_Z, quotient == 0);
        m68k.setFlag(cpu.M68k.FLAG_V, false);
        m68k.setFlag(cpu.M68k.FLAG_C, false);
    }
    
    m68k.pc += 4;
    return cycles;
}

// DIVU.L - Divide Unsigned 64/32 -> 32q:32r
fn executeDivuL(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    // DIVU.L <ea>, Dq (32/32->32q)
    // DIVU.L <ea>, Dr:Dq (64/32->32q, remainder in Dr)
    
    var cycles: u32 = 90;
    cycles += getEACycles(inst.src, .Long, true);
    
    const ext_word = try m68k.memory.read16(m68k.pc + 2);
    const dq = @as(u3, @truncate(ext_word & 0x7));
    const dr = @as(u3, @truncate((ext_word >> 12) & 0x7));
    const is_64bit = (ext_word & 0x0400) != 0;
    
    const divisor: u32 = try getOperandValue(m68k, inst.src, .Long);
    
    if (divisor == 0) {
        return error.DivideByZero;
    }
    
    if (is_64bit) {
        // 64-bit dividend
        const dividend_low: u32 = m68k.d[dq];
        const dividend_high: u32 = m68k.d[dr];
        const dividend: u64 = (@as(u64, dividend_high) << 32) | @as(u64, dividend_low);
        
        const quotient: u64 = dividend / divisor;
        const remainder: u64 = dividend % divisor;
        
        // Check overflow
        if (quotient > 0xFFFFFFFF) {
            m68k.setFlag(cpu.M68k.FLAG_V, true);
            m68k.pc += 4;
            return cycles;
        }
        
        m68k.d[dq] = @truncate(quotient);
        m68k.d[dr] = @truncate(remainder);
        
        m68k.setFlag(cpu.M68k.FLAG_N, (quotient & 0x80000000) != 0);
        m68k.setFlag(cpu.M68k.FLAG_Z, quotient == 0);
        m68k.setFlag(cpu.M68k.FLAG_V, false);
        m68k.setFlag(cpu.M68k.FLAG_C, false);
    } else {
        // 32-bit dividend
        const dividend: u32 = m68k.d[dq];
        const quotient: u32 = dividend / divisor;
        _ = dividend % divisor; // remainder not stored in 32-bit mode
        
        m68k.d[dq] = quotient;
        
        m68k.setFlag(cpu.M68k.FLAG_N, (quotient & 0x80000000) != 0);
        m68k.setFlag(cpu.M68k.FLAG_Z, quotient == 0);
        m68k.setFlag(cpu.M68k.FLAG_V, false);
        m68k.setFlag(cpu.M68k.FLAG_C, false);
    }
    
    m68k.pc += 4;
    return cycles;
}
