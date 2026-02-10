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
            .LEA => return try executeLea(m68k, inst),
            
            .RTS => return try executeRts(m68k),
            .BRA => return try executeBra(m68k, inst),
            .Bcc => return try executeBcc(m68k, inst),
            .JSR => return try executeJsr(m68k, inst),
            
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
    // Get source value
    const src_value = try getOperandValue(m68k, inst.src, inst.data_size);
    
    // Store to destination
    try setOperandValue(m68k, inst.dst, src_value, inst.data_size);
    
    // Set flags based on value moved
    m68k.setFlags(src_value, inst.data_size);
    
    m68k.pc += 2;
    return 4;
}

fn executeMovea(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const reg = switch (inst.dst) {
        .AddrReg => |r| r,
        else => return error.InvalidOperand,
    };
    
    var value = try getOperandValue(m68k, inst.src, inst.data_size);
    
    // Sign extend if word
    if (inst.data_size == .Word) {
        const signed: i16 = @bitCast(@as(u16, @truncate(value)));
        value = @bitCast(@as(i32, signed));
    }
    
    m68k.a[reg] = value;
    // MOVEA doesn't affect flags
    
    m68k.pc += 2;
    return 4;
}

// ============================================================================
// ADD family
// ============================================================================

fn executeAdd(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    // ADD can be: ADD <ea>, Dn  or  ADD Dn, <ea>
    // We need to determine direction from opcode
    const opmode = (inst.opcode >> 6) & 0x7;
    const direction = (opmode >> 2) & 1; // 0 = <ea> + Dn -> Dn, 1 = Dn + <ea> -> <ea>
    
    if (direction == 0) {
        // ADD <ea>, Dn
        const reg = switch (inst.dst) {
            .DataReg => |r| r,
            else => return error.InvalidOperand,
        };
        
        const src_value = try getOperandValue(m68k, inst.src, inst.data_size);
        const dst_value = getRegisterValue(m68k.d[reg], inst.data_size);
        const result = dst_value +% src_value;
        
        setRegisterValue(&m68k.d[reg], result, inst.data_size);
        setArithmeticFlags(m68k, dst_value, src_value, result, inst.data_size, false);
        
        m68k.pc += 2;
        return 4;
    } else {
        // ADD Dn, <ea>
        const reg = switch (inst.src) {
            .DataReg => |r| r,
            else => return error.InvalidOperand,
        };
        
        const src_value = getRegisterValue(m68k.d[reg], inst.data_size);
        const dst_value = try getOperandValue(m68k, inst.dst, inst.data_size);
        const result = dst_value +% src_value;
        
        try setOperandValue(m68k, inst.dst, result, inst.data_size);
        setArithmeticFlags(m68k, dst_value, src_value, result, inst.data_size, false);
        
        m68k.pc += 2;
        return 8;
    }
}

fn executeAdda(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const reg = switch (inst.dst) {
        .AddrReg => |r| r,
        else => return error.InvalidOperand,
    };
    
    var value = try getOperandValue(m68k, inst.src, inst.data_size);
    
    // Sign extend if word
    if (inst.data_size == .Word) {
        const signed: i16 = @bitCast(@as(u16, @truncate(value)));
        value = @bitCast(@as(i32, signed));
    }
    
    m68k.a[reg] = m68k.a[reg] +% value;
    // ADDA doesn't affect flags
    
    m68k.pc += 2;
    return 8;
}

fn executeAddi(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const imm = try getOperandValue(m68k, inst.src, inst.data_size);
    const dst_value = try getOperandValue(m68k, inst.dst, inst.data_size);
    const result = dst_value +% imm;
    
    try setOperandValue(m68k, inst.dst, result, inst.data_size);
    setArithmeticFlags(m68k, dst_value, imm, result, inst.data_size, false);
    
    m68k.pc += 4; // ADDI has extension word
    return 8;
}

fn executeAddq(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const immediate = switch (inst.src) {
        .Immediate8 => |v| @as(u32, v),
        else => return error.InvalidOperand,
    };
    
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
        },
        else => {
            const old_value = try getOperandValue(m68k, inst.dst, inst.data_size);
            const result = old_value +% immediate;
            try setOperandValue(m68k, inst.dst, result, inst.data_size);
            setArithmeticFlags(m68k, old_value, immediate, result, inst.data_size, false);
        },
    }
    
    m68k.pc += 2;
    return 4;
}

fn executeAddx(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const x_bit: u32 = if (m68k.getFlag(cpu.M68k.FLAG_X)) 1 else 0;
    
    const src_value = try getOperandValue(m68k, inst.src, inst.data_size);
    const dst_value = try getOperandValue(m68k, inst.dst, inst.data_size);
    const result = dst_value +% src_value +% x_bit;
    
    try setOperandValue(m68k, inst.dst, result, inst.data_size);
    setArithmeticFlags(m68k, dst_value, src_value +% x_bit, result, inst.data_size, false);
    
    m68k.pc += 2;
    return 4;
}

// ============================================================================
// SUB family
// ============================================================================

fn executeSub(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const opmode = (inst.opcode >> 6) & 0x7;
    const direction = (opmode >> 2) & 1;
    
    if (direction == 0) {
        // SUB <ea>, Dn
        const reg = switch (inst.dst) {
            .DataReg => |r| r,
            else => return error.InvalidOperand,
        };
        
        const src_value = try getOperandValue(m68k, inst.src, inst.data_size);
        const dst_value = getRegisterValue(m68k.d[reg], inst.data_size);
        const result = dst_value -% src_value;
        
        setRegisterValue(&m68k.d[reg], result, inst.data_size);
        setArithmeticFlags(m68k, dst_value, src_value, result, inst.data_size, true);
        
        m68k.pc += 2;
        return 4;
    } else {
        // SUB Dn, <ea>
        const reg = switch (inst.src) {
            .DataReg => |r| r,
            else => return error.InvalidOperand,
        };
        
        const src_value = getRegisterValue(m68k.d[reg], inst.data_size);
        const dst_value = try getOperandValue(m68k, inst.dst, inst.data_size);
        const result = dst_value -% src_value;
        
        try setOperandValue(m68k, inst.dst, result, inst.data_size);
        setArithmeticFlags(m68k, dst_value, src_value, result, inst.data_size, true);
        
        m68k.pc += 2;
        return 8;
    }
}

fn executeSuba(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const reg = switch (inst.dst) {
        .AddrReg => |r| r,
        else => return error.InvalidOperand,
    };
    
    var value = try getOperandValue(m68k, inst.src, inst.data_size);
    
    if (inst.data_size == .Word) {
        const signed: i16 = @bitCast(@as(u16, @truncate(value)));
        value = @bitCast(@as(i32, signed));
    }
    
    m68k.a[reg] = m68k.a[reg] -% value;
    
    m68k.pc += 2;
    return 8;
}

fn executeSubi(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const imm = try getOperandValue(m68k, inst.src, inst.data_size);
    const dst_value = try getOperandValue(m68k, inst.dst, inst.data_size);
    const result = dst_value -% imm;
    
    try setOperandValue(m68k, inst.dst, result, inst.data_size);
    setArithmeticFlags(m68k, dst_value, imm, result, inst.data_size, true);
    
    m68k.pc += 4;
    return 8;
}

fn executeSubq(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const immediate = switch (inst.src) {
        .Immediate8 => |v| @as(u32, v),
        else => return error.InvalidOperand,
    };
    
    switch (inst.dst) {
        .DataReg => |reg| {
            const old_value = getRegisterValue(m68k.d[reg], inst.data_size);
            const result = old_value -% immediate;
            setRegisterValue(&m68k.d[reg], result, inst.data_size);
            setArithmeticFlags(m68k, old_value, immediate, result, inst.data_size, true);
        },
        .AddrReg => |reg| {
            m68k.a[reg] = m68k.a[reg] -% immediate;
        },
        else => {
            const old_value = try getOperandValue(m68k, inst.dst, inst.data_size);
            const result = old_value -% immediate;
            try setOperandValue(m68k, inst.dst, result, inst.data_size);
            setArithmeticFlags(m68k, old_value, immediate, result, inst.data_size, true);
        },
    }
    
    m68k.pc += 2;
    return 4;
}

fn executeSubx(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const x_bit: u32 = if (m68k.getFlag(cpu.M68k.FLAG_X)) 1 else 0;
    
    const src_value = try getOperandValue(m68k, inst.src, inst.data_size);
    const dst_value = try getOperandValue(m68k, inst.dst, inst.data_size);
    const result = dst_value -% src_value -% x_bit;
    
    try setOperandValue(m68k, inst.dst, result, inst.data_size);
    setArithmeticFlags(m68k, dst_value, src_value +% x_bit, result, inst.data_size, true);
    
    m68k.pc += 2;
    return 4;
}

// ============================================================================
// CMP family
// ============================================================================

fn executeCmp(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const reg = switch (inst.dst) {
        .DataReg => |r| r,
        else => return error.InvalidOperand,
    };
    
    const src_value = try getOperandValue(m68k, inst.src, inst.data_size);
    const dst_value = getRegisterValue(m68k.d[reg], inst.data_size);
    const result = dst_value -% src_value;
    
    setArithmeticFlags(m68k, dst_value, src_value, result, inst.data_size, true);
    
    m68k.pc += 2;
    return 4;
}

fn executeCmpa(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const reg = switch (inst.dst) {
        .AddrReg => |r| r,
        else => return error.InvalidOperand,
    };
    
    var src_value = try getOperandValue(m68k, inst.src, inst.data_size);
    if (inst.data_size == .Word) {
        const signed: i16 = @bitCast(@as(u16, @truncate(src_value)));
        src_value = @bitCast(@as(i32, signed));
    }
    
    const result = m68k.a[reg] -% src_value;
    setArithmeticFlags(m68k, m68k.a[reg], src_value, result, .Long, true);
    
    m68k.pc += 2;
    return 6;
}

fn executeCmpi(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const imm = try getOperandValue(m68k, inst.src, inst.data_size);
    const dst_value = try getOperandValue(m68k, inst.dst, inst.data_size);
    const result = dst_value -% imm;
    
    setArithmeticFlags(m68k, dst_value, imm, result, inst.data_size, true);
    
    m68k.pc += 4;
    return 8;
}

// ============================================================================
// Logical operations
// ============================================================================

fn executeAnd(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const opmode = (inst.opcode >> 6) & 0x7;
    const direction = (opmode >> 2) & 1;
    
    if (direction == 0) {
        const reg = switch (inst.dst) {
            .DataReg => |r| r,
            else => return error.InvalidOperand,
        };
        
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
        
        const src_value = getRegisterValue(m68k.d[reg], inst.data_size);
        const dst_value = try getOperandValue(m68k, inst.dst, inst.data_size);
        const result = dst_value & src_value;
        
        try setOperandValue(m68k, inst.dst, result, inst.data_size);
        m68k.setFlags(result, inst.data_size);
    }
    
    m68k.pc += 2;
    return 4;
}

fn executeAndi(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const imm = try getOperandValue(m68k, inst.src, inst.data_size);
    const dst_value = try getOperandValue(m68k, inst.dst, inst.data_size);
    const result = dst_value & imm;
    
    try setOperandValue(m68k, inst.dst, result, inst.data_size);
    m68k.setFlags(result, inst.data_size);
    
    m68k.pc += 4;
    return 8;
}

fn executeOr(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const opmode = (inst.opcode >> 6) & 0x7;
    const direction = (opmode >> 2) & 1;
    
    if (direction == 0) {
        const reg = switch (inst.dst) {
            .DataReg => |r| r,
            else => return error.InvalidOperand,
        };
        
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
        
        const src_value = getRegisterValue(m68k.d[reg], inst.data_size);
        const dst_value = try getOperandValue(m68k, inst.dst, inst.data_size);
        const result = dst_value | src_value;
        
        try setOperandValue(m68k, inst.dst, result, inst.data_size);
        m68k.setFlags(result, inst.data_size);
    }
    
    m68k.pc += 2;
    return 4;
}

fn executeOri(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const imm = try getOperandValue(m68k, inst.src, inst.data_size);
    const dst_value = try getOperandValue(m68k, inst.dst, inst.data_size);
    const result = dst_value | imm;
    
    try setOperandValue(m68k, inst.dst, result, inst.data_size);
    m68k.setFlags(result, inst.data_size);
    
    m68k.pc += 4;
    return 8;
}

fn executeEor(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const reg = switch (inst.src) {
        .DataReg => |r| r,
        else => return error.InvalidOperand,
    };
    
    const src_value = getRegisterValue(m68k.d[reg], inst.data_size);
    const dst_value = try getOperandValue(m68k, inst.dst, inst.data_size);
    const result = dst_value ^ src_value;
    
    try setOperandValue(m68k, inst.dst, result, inst.data_size);
    m68k.setFlags(result, inst.data_size);
    
    m68k.pc += 2;
    return 4;
}

fn executeEori(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const imm = try getOperandValue(m68k, inst.src, inst.data_size);
    const dst_value = try getOperandValue(m68k, inst.dst, inst.data_size);
    const result = dst_value ^ imm;
    
    try setOperandValue(m68k, inst.dst, result, inst.data_size);
    m68k.setFlags(result, inst.data_size);
    
    m68k.pc += 4;
    return 8;
}

fn executeNot(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const dst_value = try getOperandValue(m68k, inst.dst, inst.data_size);
    const result = ~dst_value;
    
    try setOperandValue(m68k, inst.dst, result, inst.data_size);
    m68k.setFlags(result, inst.data_size);
    
    m68k.pc += 2;
    return 4;
}

// ============================================================================
// Multiply/Divide
// ============================================================================

fn executeMulu(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
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
    return 38;
}

fn executeMuls(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
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
}

fn executeDivu(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
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
}

fn executeDivs(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
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
}

// ============================================================================
// Other operations
// ============================================================================

fn executeNeg(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const old = try getOperandValue(m68k, inst.dst, inst.data_size);
    const result = 0 -% old;
    
    try setOperandValue(m68k, inst.dst, result, inst.data_size);
    setArithmeticFlags(m68k, 0, old, result, inst.data_size, true);
    
    m68k.pc += 2;
    return 4;
}

fn executeNegx(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const x_bit: u32 = if (m68k.getFlag(cpu.M68k.FLAG_X)) 1 else 0;
    const old = try getOperandValue(m68k, inst.dst, inst.data_size);
    const result = 0 -% old -% x_bit;
    
    try setOperandValue(m68k, inst.dst, result, inst.data_size);
    setArithmeticFlags(m68k, 0, old +% x_bit, result, inst.data_size, true);
    
    m68k.pc += 2;
    return 4;
}

fn executeClr(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    try setOperandValue(m68k, inst.dst, 0, inst.data_size);
    
    m68k.setFlag(cpu.M68k.FLAG_N, false);
    m68k.setFlag(cpu.M68k.FLAG_Z, true);
    m68k.setFlag(cpu.M68k.FLAG_V, false);
    m68k.setFlag(cpu.M68k.FLAG_C, false);
    
    m68k.pc += 2;
    return 4;
}

fn executeTst(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const value = try getOperandValue(m68k, inst.dst, inst.data_size);
    m68k.setFlags(value, inst.data_size);
    
    m68k.pc += 2;
    return 4;
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
    
    if (inst.data_size == .Word) {
        const byte_val: i8 = @bitCast(@as(u8, @truncate(m68k.d[reg])));
        const extended: i16 = byte_val;
        m68k.d[reg] = (m68k.d[reg] & 0xFFFF0000) | @as(u32, @bitCast(@as(i32, extended) & 0xFFFF));
    } else {
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
    
    const ea = try calculateEA(m68k, inst.src);
    m68k.a[reg] = ea;
    
    m68k.pc += 2;
    return 4;
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
    _ = inst;
    const return_addr = m68k.pc + 2;
    m68k.a[7] -= 4;
    try m68k.memory.write32(m68k.a[7], return_addr);
    m68k.pc += 2;
    return 18;
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
        .AddrDisplace => |info| {
            const addr = m68k.a[info.reg] +% @as(u32, @bitCast(@as(i32, info.displacement)));
            return switch (size) {
                .Byte => @as(u32, try m68k.memory.read8(addr)),
                .Word => @as(u32, try m68k.memory.read16(addr)),
                .Long => try m68k.memory.read32(addr),
            };
        },
        .Address => |addr| {
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
        .AddrDisplace => |info| {
            const addr = m68k.a[info.reg] +% @as(u32, @bitCast(@as(i32, info.displacement)));
            switch (size) {
                .Byte => try m68k.memory.write8(addr, @truncate(value)),
                .Word => try m68k.memory.write16(addr, @truncate(value)),
                .Long => try m68k.memory.write32(addr, value),
            }
        },
        .Address => |addr| {
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
