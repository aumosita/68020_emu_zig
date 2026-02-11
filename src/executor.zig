const std = @import("std");
const cpu = @import("cpu.zig");
const decoder = @import("decoder.zig");
const memory = @import("memory.zig");

pub const Executor = struct {
    pub fn init() Executor { return .{}; }
    pub fn execute(self: *const Executor, m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
        _ = self;
        switch (inst.mnemonic) {
            .NOP => { m68k.pc += 2; return 4; },
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
            .CMPM => return try executeCmpm(m68k, inst),
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
            .EXT, .EXTB => return try executeExt(m68k, inst),
            .LEA => return try executeLea(m68k, inst),
            .RTS => return try executeRts(m68k),
            .RTR => return try executeRtr(m68k),
            .RTE => return try executeRte(m68k),
            .TRAP => return try executeTrap(m68k, inst),
            .TRAPV => return try executeTrapv(m68k),
            .STOP => return try executeStop(m68k, inst),
            .RESET => return try executeReset(m68k),
            .BRA => return try executeBra(m68k, inst),
            .Bcc => return try executeBcc(m68k, inst),
            .BSR => return try executeBsr(m68k, inst),
            .JSR => return try executeJsr(m68k, inst),
            .JMP => return try executeJmp(m68k, inst),
            .DBcc => return try executeDbcc(m68k, inst),
            .Scc => return try executeScc(m68k, inst),
            .ASL, .ASR, .LSL, .LSR, .ROL, .ROR, .ROXL, .ROXR => return try executeShift(m68k, inst),
            .BTST => return try executeBtst(m68k, inst),
            .BSET => return try executeBset(m68k, inst),
            .BCLR => return try executeBclr(m68k, inst),
            .BCHG => return try executeBchg(m68k, inst),
            .MOVEC => return try executeMovec(m68k, inst),
            .MOVEUSP => return try executeMoveUsp(m68k, inst),
            .LINK => return try executeLink(m68k, inst),
            .UNLK => return try executeUnlk(m68k, inst),
            .PEA => return try executePea(m68k, inst),
            .MOVEM => return try executeMovem(m68k, inst),
            .EXG => return try executeExg(m68k, inst),
            .CHK => return try executeChk(m68k, inst),
            .TAS => return try executeTas(m68k, inst),
            .ABCD => return try executeAbcd(m68k, inst),
            .SBCD => return try executeSbcd(m68k, inst),
            .NBCD => return try executeNbcd(m68k, inst),
            .MOVEP => return try executeMovep(m68k, inst),
            .BFTST => return try executeBftst(m68k, inst),
            .BFSET => return try executeBfset(m68k, inst),
            .BFCLR => return try executeBfclr(m68k, inst),
            .BFCHG => return try executeBfchg(m68k, inst),
            .BFEXTS => return try executeBfexts(m68k, inst),
            .BFEXTU => return try executeBfextu(m68k, inst),
            .BFINS => return try executeBfins(m68k, inst),
            .BFFFO => return try executeBfffo(m68k, inst),
            .CAS => return try executeCas(m68k, inst),
            .CAS2 => return try executeCas2(m68k, inst),
            .CALLM => return try executeCallm(m68k, inst),
            .RTM => return try executeRtm(m68k, inst),
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
            .LINEA => return try executeLineAEmulator(m68k),
            .COPROC => return try executeCoprocessorDispatch(m68k, inst),
            .ILLEGAL => return try executeIllegalInstruction(m68k),
            .UNKNOWN => return try executeIllegalInstruction(m68k),
        }
    }
};

fn executeMoveq(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const r = switch (i.dst) { .DataReg => |v| v, else => return error.Err };
    const v: i8 = switch (i.src) { .Immediate8 => |w| @bitCast(w), else => 0 };
    m.d[r] = @bitCast(@as(i32, v)); m.setFlags(m.d[r], .Long); m.pc += i.size; return 4;
}
fn executeMove(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const v = try getOperandValue(m, i.src, i.data_size);
    try setOperandValue(m, i.dst, v, i.data_size); m.setFlags(v, i.data_size); m.pc += i.size;
    return 4 + getEACycles(i.src, i.data_size, true) + getEACycles(i.dst, i.data_size, false);
}
fn executeMovea(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const r = switch (i.dst) { .AddrReg => |v| v, else => return error.Err };
    var v = try getOperandValue(m, i.src, i.data_size); if (i.data_size == .Word) v = @bitCast(@as(i32, @as(i16, @bitCast(@as(u16, @truncate(v))))));
    m.a[r] = v; m.pc += i.size; return 4 + getEACycles(i.src, i.data_size, true);
}
fn executeAdd(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const dir = (i.opcode >> 8) & 1;
    if (dir == 0) {
        const r = switch (i.dst) { .DataReg => |v| v, else => 0 };
        const s = try getOperandValue(m, i.src, i.data_size);
        const d = getRegisterValue(m.d[r], i.data_size);
        const res = d +% s; setRegisterValue(&m.d[r], res, i.data_size); setArithmeticFlags(m, d, s, res, i.data_size, false);
    } else {
        const r = switch (i.src) { .DataReg => |v| v, else => 0 };
        const s = getRegisterValue(m.d[r], i.data_size);
        const d = try getOperandValue(m, i.dst, i.data_size);
        const res = d +% s; try setOperandValue(m, i.dst, res, i.data_size); setArithmeticFlags(m, d, s, res, i.data_size, false);
    }
    m.pc += i.size; return 4 + getEACycles(i.src, i.data_size, true) + getEACycles(i.dst, i.data_size, false);
}
fn executeAdda(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const r = switch (i.dst) { .AddrReg => |v| v, else => 0 }; var s = try getOperandValue(m, i.src, i.data_size); if (i.data_size == .Word) s = @bitCast(@as(i32, @as(i16, @bitCast(@as(u16, @truncate(s))))));
    m.a[r] = m.a[r] +% s; m.pc += i.size; return 8 + getEACycles(i.src, i.data_size, true);
}
fn executeAddi(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const s = try getOperandValue(m, i.src, i.data_size); const d = try getOperandValue(m, i.dst, i.data_size); const res = d +% s; try setOperandValue(m, i.dst, res, i.data_size); setArithmeticFlags(m, d, s, res, i.data_size, false);
    m.pc += i.size; return 8 + getEACycles(i.dst, i.data_size, true);
}
fn executeAddq(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const s = switch (i.src) { .Immediate8 => |v| @as(u32, v), else => 1 }; const d = try getOperandValue(m, i.dst, i.data_size); const res = d +% s; try setOperandValue(m, i.dst, res, i.data_size);
    if (i.dst != .AddrReg) setArithmeticFlags(m, d, s, res, i.data_size, false); m.pc += i.size; return 4;
}
fn executeAddx(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const x: u32 = if (m.getFlag(cpu.M68k.FLAG_X)) 1 else 0; const s = try getOperandValue(m, i.src, i.data_size); const d = try getOperandValue(m, i.dst, i.data_size); const res = d +% s +% x;
    try setOperandValue(m, i.dst, res, i.data_size); setArithmeticFlags(m, d, s +% x, res, i.data_size, false); m.pc += i.size; return 4;
}
fn executeSub(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const dir = (i.opcode >> 8) & 1;
    if (dir == 0) { const r = switch (i.dst) { .DataReg => |v| v, else => 0 }; const s = try getOperandValue(m, i.src, i.data_size); const d = getRegisterValue(m.d[r], i.data_size); const res = d -% s; setRegisterValue(&m.d[r], res, i.data_size); setArithmeticFlags(m, d, s, res, i.data_size, true); }
    else { const r = switch (i.src) { .DataReg => |v| v, else => 0 }; const s = getRegisterValue(m.d[r], i.data_size); const d = try getOperandValue(m, i.dst, i.data_size); const res = d -% s; try setOperandValue(m, i.dst, res, i.data_size); setArithmeticFlags(m, d, s, res, i.data_size, true); }
    m.pc += i.size; return 4 + getEACycles(i.src, i.data_size, true) + getEACycles(i.dst, i.data_size, false);
}
fn executeSuba(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const r = switch (i.dst) { .AddrReg => |v| v, else => 0 }; var s = try getOperandValue(m, i.src, i.data_size); if (i.data_size == .Word) s = @bitCast(@as(i32, @as(i16, @bitCast(@as(u16, @truncate(s))))));
    m.a[r] = m.a[r] -% s; m.pc += i.size; return 8 + getEACycles(i.src, i.data_size, true);
}
fn executeSubi(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const s = try getOperandValue(m, i.src, i.data_size); const d = try getOperandValue(m, i.dst, i.data_size); const res = d -% s; try setOperandValue(m, i.dst, res, i.data_size); setArithmeticFlags(m, d, s, res, i.data_size, true);
    m.pc += i.size; return 8 + getEACycles(i.dst, i.data_size, true);
}
fn executeSubq(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const s = switch (i.src) { .Immediate8 => |v| @as(u32, v), else => 1 }; const d = try getOperandValue(m, i.dst, i.data_size); const res = d -% s; try setOperandValue(m, i.dst, res, i.data_size);
    if (i.dst != .AddrReg) setArithmeticFlags(m, d, s, res, i.data_size, true); m.pc += i.size; return 4;
}
fn executeSubx(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const x: u32 = if (m.getFlag(cpu.M68k.FLAG_X)) 1 else 0; const s = try getOperandValue(m, i.src, i.data_size); const d = try getOperandValue(m, i.dst, i.data_size); const res = d -% s -% x;
    try setOperandValue(m, i.dst, res, i.data_size); setArithmeticFlags(m, d, s +% x, res, i.data_size, true); m.pc += i.size; return 4;
}
fn executeCmp(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const r = switch (i.dst) { .DataReg => |v| v, else => 0 }; const s = try getOperandValue(m, i.src, i.data_size); const d = getRegisterValue(m.d[r], i.data_size); setArithmeticFlags(m, d, s, d -% s, i.data_size, true);
    m.pc += i.size; return 4 + getEACycles(i.src, i.data_size, true);
}
fn executeCmpa(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const r = switch (i.dst) { .AddrReg => |v| v, else => 0 }; var s = try getOperandValue(m, i.src, i.data_size); if (i.data_size == .Word) s = @bitCast(@as(i32, @as(i16, @bitCast(@as(u16, @truncate(s))))));
    setArithmeticFlags(m, m.a[r], s, m.a[r] -% s, .Long, true); m.pc += i.size; return 6 + getEACycles(i.src, i.data_size, true);
}
fn executeCmpi(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const s = try getOperandValue(m, i.src, i.data_size); const d = try getOperandValue(m, i.dst, i.data_size); setArithmeticFlags(m, d, s, d -% s, i.data_size, true);
    m.pc += i.size; return 8 + getEACycles(i.dst, i.data_size, true);
}
fn executeCmpm(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const ay: u3 = @truncate(i.opcode & 7); const ax: u3 = @truncate((i.opcode >> 9) & 7);
    const s = try getOperandValue(m, .{ .AddrPostInc = ay }, i.data_size); const d = try getOperandValue(m, .{ .AddrPostInc = ax }, i.data_size);
    setArithmeticFlags(m, d, s, d -% s, i.data_size, true); m.pc += i.size; return 12;
}
fn executeAnd(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const dir = (i.opcode >> 8) & 1;
    if (dir == 0) { const r = switch (i.dst) { .DataReg => |v| v, else => 0 }; const s = try getOperandValue(m, i.src, i.data_size); const res = m.d[r] & s; setRegisterValue(&m.d[r], res, i.data_size); m.setFlags(res, i.data_size); }
    else { const r = switch (i.src) { .DataReg => |v| v, else => 0 }; const s = getRegisterValue(m.d[r], i.data_size); const d = try getOperandValue(m, i.dst, i.data_size); const res = s & d; try setOperandValue(m, i.dst, res, i.data_size); m.setFlags(res, i.data_size); }
    m.pc += i.size; return 4;
}
fn executeAndi(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    if (i.opcode == 0x023C) { // ANDI to CCR
        const imm = switch (i.src) { .Immediate16 => |v| v, else => 0 };
        const ccr = (m.sr & 0x00FF) & (imm & 0x00FF);
        m.sr = (m.sr & 0xFF00) | ccr;
        m.pc += i.size;
        return 20;
    }
    if (i.opcode == 0x027C) { // ANDI to SR (privileged)
        if (!m.getFlag(cpu.M68k.FLAG_S)) {
            try m.enterException(8, m.pc, 0, null);
            return 34;
        }
        const imm = switch (i.src) { .Immediate16 => |v| v, else => 0 };
        m.setSR(m.sr & imm);
        m.pc += i.size;
        return 20;
    }
    const s = try getOperandValue(m, i.src, i.data_size); const d = try getOperandValue(m, i.dst, i.data_size); const res = d & s; try setOperandValue(m, i.dst, res, i.data_size); m.setFlags(res, i.data_size); m.pc += i.size; return 8;
}
fn executeOr(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const dir = (i.opcode >> 8) & 1;
    if (dir == 0) { const r = switch (i.dst) { .DataReg => |v| v, else => 0 }; const s = try getOperandValue(m, i.src, i.data_size); const res = m.d[r] | s; setRegisterValue(&m.d[r], res, i.data_size); m.setFlags(res, i.data_size); }
    else { const r = switch (i.src) { .DataReg => |v| v, else => 0 }; const s = getRegisterValue(m.d[r], i.data_size); const d = try getOperandValue(m, i.dst, i.data_size); const res = s | d; try setOperandValue(m, i.dst, res, i.data_size); m.setFlags(res, i.data_size); }
    m.pc += i.size; return 4;
}
fn executeOri(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    if (i.opcode == 0x003C) { // ORI to CCR
        const imm = switch (i.src) { .Immediate16 => |v| v, else => 0 };
        const ccr = (m.sr & 0x00FF) | (imm & 0x00FF);
        m.sr = (m.sr & 0xFF00) | ccr;
        m.pc += i.size;
        return 20;
    }
    if (i.opcode == 0x007C) { // ORI to SR (privileged)
        if (!m.getFlag(cpu.M68k.FLAG_S)) {
            try m.enterException(8, m.pc, 0, null);
            return 34;
        }
        const imm = switch (i.src) { .Immediate16 => |v| v, else => 0 };
        m.setSR(m.sr | imm);
        m.pc += i.size;
        return 20;
    }
    const s = try getOperandValue(m, i.src, i.data_size); const d = try getOperandValue(m, i.dst, i.data_size); const res = d | s; try setOperandValue(m, i.dst, res, i.data_size); m.setFlags(res, i.data_size); m.pc += i.size; return 8;
}
fn executeEor(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const r = switch (i.src) { .DataReg => |v| v, else => 0 }; const d = try getOperandValue(m, i.dst, i.data_size); const res = m.d[r] ^ d; try setOperandValue(m, i.dst, res, i.data_size); m.setFlags(res, i.data_size); m.pc += i.size; return 4;
}
fn executeEori(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    if (i.opcode == 0x0A3C) { // EORI to CCR
        const imm = switch (i.src) { .Immediate16 => |v| v, else => 0 };
        const ccr = (m.sr & 0x00FF) ^ (imm & 0x00FF);
        m.sr = (m.sr & 0xFF00) | ccr;
        m.pc += i.size;
        return 20;
    }
    if (i.opcode == 0x0A7C) { // EORI to SR (privileged)
        if (!m.getFlag(cpu.M68k.FLAG_S)) {
            try m.enterException(8, m.pc, 0, null);
            return 34;
        }
        const imm = switch (i.src) { .Immediate16 => |v| v, else => 0 };
        m.setSR(m.sr ^ imm);
        m.pc += i.size;
        return 20;
    }
    const s = try getOperandValue(m, i.src, i.data_size); const d = try getOperandValue(m, i.dst, i.data_size); const res = d ^ s; try setOperandValue(m, i.dst, res, i.data_size); m.setFlags(res, i.data_size); m.pc += i.size; return 8;
}
fn executeNot(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const d = try getOperandValue(m, i.dst, i.data_size); const res = ~d; try setOperandValue(m, i.dst, res, i.data_size); m.setFlags(res, i.data_size); m.pc += i.size; return 4;
}
fn executeMulu(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const r = switch (i.dst) { .DataReg => |v| v, else => 0 }; const s: u32 = try getOperandValue(m, i.src, .Word); const d: u32 = m.d[r] & 0xFFFF; const res = s * d; m.d[r] = res; m.setFlag(cpu.M68k.FLAG_N, (res & 0x80000000) != 0); m.setFlag(cpu.M68k.FLAG_Z, res == 0); m.setFlag(cpu.M68k.FLAG_V, false); m.setFlag(cpu.M68k.FLAG_C, false); m.pc += i.size; return 38;
}
fn executeMuls(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const r = switch (i.dst) { .DataReg => |v| v, else => 0 }; const vs = try getOperandValue(m, i.src, .Word); const s16: i16 = @bitCast(@as(u16, @truncate(vs))); const d16: i16 = @bitCast(@as(u16, @truncate(m.d[r]))); const res: i32 = @as(i32, s16) * @as(i32, d16); m.d[r] = @bitCast(res); m.setFlag(cpu.M68k.FLAG_N, res < 0); m.setFlag(cpu.M68k.FLAG_Z, res == 0); m.setFlag(cpu.M68k.FLAG_V, false); m.setFlag(cpu.M68k.FLAG_C, false); m.pc += i.size; return 38;
}
fn executeDivu(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const r = switch (i.dst) { .DataReg => |v| v, else => 0 }; const divisor = try getOperandValue(m, i.src, .Word); if (divisor == 0) { try m.enterException(5, m.pc, 0, null); return 38; }
    const res = m.d[r] / divisor; const rem = m.d[r] % divisor; if (res > 0xFFFF) { m.setFlag(cpu.M68k.FLAG_V, true); } else { m.d[r] = (rem << 16) | (res & 0xFFFF); m.setFlags(res & 0xFFFF, .Word); } m.pc += i.size; return 76;
}
fn executeDivs(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const r = switch (i.dst) { .DataReg => |v| v, else => 0 }; const vs = try getOperandValue(m, i.src, .Word); const s: i16 = @bitCast(@as(u16, @truncate(vs))); if (s == 0) { try m.enterException(5, m.pc, 0, null); return 38; }
    const d: i32 = @bitCast(m.d[r]); const res = @divTrunc(d, s); const rem = @rem(d, s); if (res < -32768 or res > 32767) { m.setFlag(cpu.M68k.FLAG_V, true); } else { const u_rem: u16 = @bitCast(@as(i16, @truncate(rem))); const u_res: u16 = @bitCast(@as(i16, @truncate(res))); m.d[r] = (@as(u32, u_rem) << 16) | u_res; m.setFlags(@as(u32, u_res), .Word); } m.pc += i.size; return 76;
}
fn executeNeg(m: *cpu.M68k, i: *const decoder.Instruction) !u32 { const d = try getOperandValue(m, i.dst, i.data_size); const res = 0 -% d; try setOperandValue(m, i.dst, res, i.data_size); setArithmeticFlags(m, 0, d, res, i.data_size, true); m.pc += i.size; return 4; }
fn executeNegx(m: *cpu.M68k, i: *const decoder.Instruction) !u32 { const x: u32 = if (m.getFlag(cpu.M68k.FLAG_X)) 1 else 0; const d = try getOperandValue(m, i.dst, i.data_size); const res = 0 -% d -% x; try setOperandValue(m, i.dst, res, i.data_size); setArithmeticFlags(m, 0, d +% x, res, i.data_size, true); m.pc += i.size; return 4; }
fn executeClr(m: *cpu.M68k, i: *const decoder.Instruction) !u32 { try setOperandValue(m, i.dst, 0, i.data_size); m.setFlags(0, i.data_size); m.pc += i.size; return 4; }
fn executeTst(m: *cpu.M68k, i: *const decoder.Instruction) !u32 { const v = try getOperandValue(m, i.dst, i.data_size); m.setFlags(v, i.data_size); m.pc += i.size; return 4; }
fn executeSwap(m: *cpu.M68k, i: *const decoder.Instruction) !u32 { const r = switch (i.dst) { .DataReg => |v| v, else => 0 }; const low = m.d[r] & 0xFFFF; const high = m.d[r] >> 16; m.d[r] = (low << 16) | high; m.setFlags(m.d[r], .Long); m.pc += i.size; return 4; }
fn executeExt(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const r = switch (i.dst) { .DataReg => |v| v, else => 0 }; if (i.is_extb) { m.d[r] = @bitCast(@as(i32, @as(i8, @bitCast(@as(u8, @truncate(m.d[r])))))); }
    else if (i.data_size == .Word) { const ext_val = @as(i16, @as(i8, @bitCast(@as(u8, @truncate(m.d[r]))))); m.d[r] = (m.d[r] & 0xFFFF0000) | (@as(u32, @bitCast(@as(i32, ext_val))) & 0xFFFF); }
    else { m.d[r] = @bitCast(@as(i32, @as(i16, @bitCast(@as(u16, @truncate(m.d[r])))))); }
    m.setFlags(m.d[r], .Long); m.pc += i.size; return 4;
}
fn executeLea(m: *cpu.M68k, i: *const decoder.Instruction) !u32 { const r = switch (i.dst) { .AddrReg => |v| v, else => 0 }; m.a[r] = try calculateEA(m, i.src); m.pc += i.size; return 4; }
fn executeRts(m: *cpu.M68k) !u32 { m.pc = try m.memory.read32(m.a[7]); m.a[7] += 4; return 16; }
fn executeRtr(m: *cpu.M68k) !u32 { const ccr = try m.memory.read16(m.a[7]); m.sr = (m.sr & 0xFF00) | (ccr & 0xFF); m.pc = try m.memory.read32(m.a[7] + 2); m.a[7] += 6; return 20; }
fn executeRte(m: *cpu.M68k) !u32 { 
    if (!m.getFlag(cpu.M68k.FLAG_S)) {
        try m.enterException(8, m.pc, 0, null);
        return 34;
    }
    const sp = m.a[7]; 
    const sr = try m.memory.read16(sp);
    const pc = try m.memory.read32(sp + 2);
    const format_vector = try m.memory.read16(sp + 6);
    const format = @as(u4, @truncate(format_vector >> 12));
    
    // 68020 스택 프레임 처리
    var frame_size: u32 = 8; // 기본: SR(2) + PC(4) + Format/Vector(2)
    switch (format) {
        0 => frame_size = 8,  // Short format (4-word)
        1 => frame_size = 8,  // Throwaway (4-word)
        2 => frame_size = 12, // Instruction exception (6-word)
        9 => frame_size = 20, // Coprocessor mid-instruction (10-word)
        0xA => frame_size = 24, // Short bus cycle fault (12-word)
        0xB => frame_size = 84, // Long bus cycle fault (42-word)
        else => {}, // Unknown format, use default
    }
    
    m.a[7] = sp + frame_size;
    m.setSR(sr);
    m.pc = pc;
    return 20; 
}
fn executeTrap(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const v = switch (i.src) { .Immediate8 => |w| w, else => 0 }; const vn: u8 = 32 + (v & 0xF); try m.enterException(vn, m.pc + 2, 0, null); return 34;
}
fn executeTrapv(m: *cpu.M68k) !u32 {
    if (m.getFlag(cpu.M68k.FLAG_V)) {
        try m.enterException(7, m.pc + 2, 0, null);
        return 34;
    }
    m.pc += 2;
    return 4;
}
fn executeStop(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    if (!m.getFlag(cpu.M68k.FLAG_S)) {
        try m.enterException(8, m.pc, 0, null);
        return 34;
    }
    const new_sr = switch (i.src) {
        .Immediate16 => |v| v,
        else => return error.InvalidOperand,
    };
    m.setSR(new_sr);
    m.pc += i.size;
    m.stopped = true;
    return 4;
}
fn executeReset(m: *cpu.M68k) !u32 {
    if (!m.getFlag(cpu.M68k.FLAG_S)) {
        try m.enterException(8, m.pc, 0, null);
        return 34;
    }
    // External bus reset signaling is platform-specific; keep CPU state and advance PC.
    m.pc += 2;
    return 132;
}
fn executeIllegalInstruction(m: *cpu.M68k) !u32 {
    try m.enterException(4, m.pc, 0, null);
    return 34;
}
fn executeCoprocessorDispatch(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    if (m.coprocessor_handler) |handler| {
        const pc_before = m.pc;
        switch (handler(m.coprocessor_ctx, m, i.opcode, m.pc)) {
            .handled => |cycles| {
                if (m.pc == pc_before) m.pc += i.size;
                return cycles;
            },
            .fault => |fault_addr| {
                try m.raiseBusError(fault_addr, .{
                    .function_code = m.getProgramFunctionCode(),
                    .space = .Program,
                    .is_write = false,
                });
                return 50;
            },
            .unavailable => {},
        }
    }
    // 0xF-line opcodes trap through Line-1111 emulator vector when coprocessor is absent.
    try m.enterException(11, m.pc, 0, null);
    return 34;
}
fn executeLineAEmulator(m: *cpu.M68k) !u32 {
    // 0xA-line opcodes trap through Line-1010 emulator vector.
    try m.enterException(10, m.pc, 0, null);
    return 34;
}
fn executeBra(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const d = switch (i.src) { .Immediate8 => |v| @as(i32, @as(i8, @bitCast(v))), .Immediate16 => |v| @as(i32, @as(i16, @bitCast(v))), .Immediate32 => |v| @as(i32, @bitCast(v)), else => 0 }; m.pc = @bitCast(@as(i32, @bitCast(m.pc)) + 2 + d); return branchTakenCycles(i.size);
}
fn executeBcc(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const cond: u4 = @truncate((i.opcode >> 8) & 0xF); if (evaluateCondition(m, cond)) return try executeBra(m, i); m.pc += i.size; return branchNotTakenCycles(i.size);
}
fn executeBsr(m: *cpu.M68k, i: *const decoder.Instruction) !u32 { m.a[7] -= 4; try m.memory.write32(m.a[7], m.pc + i.size); return try executeBra(m, i); }
fn executeJsr(m: *cpu.M68k, i: *const decoder.Instruction) !u32 { const t = try calculateEA(m, i.dst); m.a[7] -= 4; try m.memory.write32(m.a[7], m.pc + i.size); m.pc = t; return 16; }
fn executeJmp(m: *cpu.M68k, i: *const decoder.Instruction) !u32 { m.pc = try calculateEA(m, i.dst); return 8; }
fn executeDbcc(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const cond: u4 = @truncate((i.opcode >> 8) & 0xF); const r = @as(u3, @truncate(i.opcode & 7));
    if (!evaluateCondition(m, cond)) { const v: i16 = @bitCast(@as(u16, @truncate(m.d[r]))); const nv = v -% 1; setRegisterValue(&m.d[r], @as(u32, @as(u16, @bitCast(nv))), .Word); if (nv != -1) return try executeBra(m, i); }
    m.pc += 4; return 12;
}
fn executeScc(m: *cpu.M68k, i: *const decoder.Instruction) !u32 { const cond: u4 = @truncate((i.opcode >> 8) & 0xF); const res: u8 = if (evaluateCondition(m, cond)) 0xFF else 0; try setOperandValue(m, i.dst, res, .Byte); m.pc += i.size; return 4; }
fn executeShift(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const count = switch (i.src) { .Immediate8 => |v| @as(u32, v), .DataReg => |r| m.d[r] & 63, else => 1 };
    var val = try getOperandValue(m, i.dst, i.data_size); const mask: u32 = if (i.data_size == .Byte) 0xFF else if (i.data_size == .Word) 0xFFFF else 0xFFFFFFFF; const sign: u32 = if (i.data_size == .Byte) 0x80 else if (i.data_size == .Word) 0x8000 else 0x80000000;
    var c = m.getFlag(cpu.M68k.FLAG_C); var x = m.getFlag(cpu.M68k.FLAG_X);
    for (0..count) |_| {
        switch (i.mnemonic) {
            .LSR => { c = (val & 1) != 0; x = c; val >>= 1; },
            .LSL => { c = (val & sign) != 0; x = c; val = (val << 1) & mask; },
            .ASR => { c = (val & 1) != 0; x = c; const s = val & sign; val >>= 1; val |= s; },
            .ASL => { c = (val & sign) != 0; x = c; val = (val << 1) & mask; },
            .ROR => { c = (val & 1) != 0; val >>= 1; if (c) val |= sign; },
            .ROL => { c = (val & sign) != 0; val = (val << 1) & mask; if (c) val |= 1; },
            .ROXR => {
                const old_x = x;
                c = (val & 1) != 0;
                val >>= 1;
                if (old_x) val |= sign;
                x = c;
            },
            .ROXL => {
                const old_x = x;
                c = (val & sign) != 0;
                val = (val << 1) & mask;
                if (old_x) val |= 1;
                x = c;
            },
            else => {},
        }
    }
    try setOperandValue(m, i.dst, val, i.data_size);
    m.setFlags(val, i.data_size);
    m.setFlag(cpu.M68k.FLAG_C, c);
    m.setFlag(cpu.M68k.FLAG_X, x);
    m.pc += i.size;
    return 6 + (2 * count);
}
fn executeBtst(m: *cpu.M68k, i: *const decoder.Instruction) !u32 { const b = (try getOperandValue(m, i.src, .Byte)) & 31; const v = try getOperandValue(m, i.dst, i.data_size); m.setFlag(cpu.M68k.FLAG_Z, (v & (@as(u32, 1) << @truncate(b))) == 0); m.pc += i.size; return 4; }
fn executeBset(m: *cpu.M68k, i: *const decoder.Instruction) !u32 { const b = (try getOperandValue(m, i.src, .Byte)) & 31; const v = try getOperandValue(m, i.dst, i.data_size); m.setFlag(cpu.M68k.FLAG_Z, (v & (@as(u32, 1) << @truncate(b))) == 0); try setOperandValue(m, i.dst, v | (@as(u32, 1) << @truncate(b)), i.data_size); m.pc += i.size; return 8; }
fn executeBclr(m: *cpu.M68k, i: *const decoder.Instruction) !u32 { const b = (try getOperandValue(m, i.src, .Byte)) & 31; const v = try getOperandValue(m, i.dst, i.data_size); m.setFlag(cpu.M68k.FLAG_Z, (v & (@as(u32, 1) << @truncate(b))) == 0); try setOperandValue(m, i.dst, v & ~(@as(u32, 1) << @truncate(b)), i.data_size); m.pc += i.size; return 8; }
fn executeBchg(m: *cpu.M68k, i: *const decoder.Instruction) !u32 { const b = (try getOperandValue(m, i.src, .Byte)) & 31; const v = try getOperandValue(m, i.dst, i.data_size); m.setFlag(cpu.M68k.FLAG_Z, (v & (@as(u32, 1) << @truncate(b))) == 0); try setOperandValue(m, i.dst, v ^ (@as(u32, 1) << @truncate(b)), i.data_size); m.pc += i.size; return 8; }
fn executeMovec(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    if (!m.getFlag(cpu.M68k.FLAG_S)) {
        try m.enterException(8, m.pc, 0, null);
        return 34;
    }
    const reg = i.control_reg orelse 0;
    if (i.is_to_control) {
        const val = try getOperandValue(m, i.src, .Long);
        switch (reg) {
            0 => m.sfc = @truncate(val & 7),
            1 => m.dfc = @truncate(val & 7),
            2 => m.setCacr(val),
            0x800 => {
                m.setStackRegister(.User, val);
            },
            0x801 => m.vbr = val,
            0x802 => m.caar = val,
            0x803 => {
                m.setStackRegister(.Master, val);
            },
            0x804 => {
                m.setStackRegister(.Interrupt, val);
            },
            else => return error.InvalidControlRegister,
        }
    } else {
        const val: u32 = switch (reg) {
            0 => m.sfc,
            1 => m.dfc,
            2 => m.cacr,
            0x800 => m.getStackRegister(.User),
            0x801 => m.vbr,
            0x802 => m.caar,
            0x803 => m.getStackRegister(.Master),
            0x804 => m.getStackRegister(.Interrupt),
            else => return error.InvalidControlRegister,
        };
        try setOperandValue(m, i.src, val, .Long);
    }
    m.pc += 4; return 12;
}
fn executeMoveUsp(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    if (!m.getFlag(cpu.M68k.FLAG_S)) {
        try m.enterException(8, m.pc, 0, null);
        return 34;
    }

    switch (i.src) {
        .AddrReg => |r| {
            // MOVE An,USP
            m.setStackRegister(.User, m.a[r]);
        },
        else => {
            // MOVE USP,An
            const r = switch (i.dst) {
                .AddrReg => |areg| areg,
                else => return error.InvalidOperand,
            };
            m.a[r] = m.getStackRegister(.User);
        },
    }

    m.pc += 2;
    return 4;
}
fn executeLink(m: *cpu.M68k, i: *const decoder.Instruction) !u32 { const r = switch (i.dst) { .AddrReg => |v| v, else => 7 }; const d: i16 = @bitCast(switch (i.src) { .Immediate16 => |v| v, else => 0 }); m.a[7] -= 4; try m.memory.write32(m.a[7], m.a[r]); m.a[r] = m.a[7]; m.a[7] = @bitCast(@as(i32, @bitCast(m.a[7])) + @as(i32, d)); m.pc += 4; return 16; }
fn executeUnlk(m: *cpu.M68k, i: *const decoder.Instruction) !u32 { const r = switch (i.dst) { .AddrReg => |v| v, else => 7 }; m.a[7] = m.a[r]; m.a[r] = try m.memory.read32(m.a[7]); m.a[7] += 4; m.pc += i.size; return 12; }
fn executePea(m: *cpu.M68k, i: *const decoder.Instruction) !u32 { const a = try calculateEA(m, i.src); m.a[7] -= 4; try m.memory.write32(m.a[7], a); m.pc += i.size; return 12; }
fn executeMovem(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const mask = switch (i.src) { .Immediate16 => |v| v, else => 0 };
    const dir = (i.opcode >> 10) & 1;
    const size_bytes: u32 = if (i.data_size == .Word) 2 else 4;
    const reg_count: u32 = @intCast(@popCount(mask));

    if (dir == 0) {
        switch (i.dst) {
            .AddrPreDec => |areg| {
                var addr = m.a[areg];
                var bit: i32 = 15;
                while (bit >= 0) : (bit -= 1) {
                    const shift: u4 = @truncate(@as(u32, @intCast(bit)));
                    if ((mask & (@as(u16, 1) << shift)) == 0) continue;
                    const idx: usize = @intCast(bit);
                    const reg_val: u32 = if (idx < 8) m.d[idx] else m.a[idx - 8];
                    addr -= size_bytes;
                    if (i.data_size == .Word) {
                        try m.memory.write16(addr, @truncate(reg_val));
                    } else {
                        try m.memory.write32(addr, reg_val);
                    }
                }
                m.a[areg] = addr;
            },
            else => {
                var addr: u32 = switch (i.dst) {
                    .AddrPostInc => |r| m.a[r],
                    .AddrPreDec => |r| m.a[r],
                    else => try calculateEA(m, i.dst),
                };
                for (0..16) |idx| {
                    const shift: u4 = @truncate(idx);
                    if ((mask & (@as(u16, 1) << shift)) == 0) continue;
                    const reg_val: u32 = if (idx < 8) m.d[idx] else m.a[idx - 8];
                    if (i.data_size == .Word) {
                        try m.memory.write16(addr, @truncate(reg_val));
                    } else {
                        try m.memory.write32(addr, reg_val);
                    }
                    addr += size_bytes;
                }
                if (i.dst == .AddrPostInc) {
                    const areg = switch (i.dst) { .AddrPostInc => |r| r, else => unreachable };
                    m.a[areg] = addr;
                }
            },
        }
    } else {
        var addr: u32 = switch (i.dst) {
            .AddrPostInc => |r| m.a[r],
            .AddrPreDec => |r| m.a[r],
            else => try calculateEA(m, i.dst),
        };
        for (0..16) |idx| {
            const shift: u4 = @truncate(idx);
            if ((mask & (@as(u16, 1) << shift)) == 0) continue;
            if (i.data_size == .Word) {
                const w = try m.memory.read16(addr);
                const value = @as(u32, @bitCast(@as(i32, @as(i16, @bitCast(w)))));
                if (idx < 8) m.d[idx] = value else m.a[idx - 8] = value;
            } else {
                const l = try m.memory.read32(addr);
                if (idx < 8) m.d[idx] = l else m.a[idx - 8] = l;
            }
            addr += size_bytes;
        }
        if (i.dst == .AddrPostInc) {
            const areg = switch (i.dst) { .AddrPostInc => |r| r, else => unreachable };
            m.a[areg] = addr;
        }
    }
    m.pc += i.size;
    return movemCycleCost(i.data_size, dir == 1, i.dst, reg_count);
}
fn movemModePenalty(op: decoder.Operand) u32 {
    return switch (op) {
        .AddrPreDec, .AddrPostInc, .Address, .AddrDisplace => 2,
        .ComplexEA => 4,
        else => 0,
    };
}
fn movemCycleCost(size: decoder.DataSize, mem_to_reg: bool, dst: decoder.Operand, reg_count: u32) u32 {
    const base: u32 = 8;
    const per_reg: u32 = switch (size) {
        .Word => if (mem_to_reg) 5 else 4,
        .Long => if (mem_to_reg) 9 else 8,
        else => 4,
    };
    return base + (per_reg * reg_count) + movemModePenalty(dst);
}
fn executeExg(m: *cpu.M68k, i: *const decoder.Instruction) !u32 { const rx = (i.opcode >> 9) & 7; const ry = i.opcode & 7; const mode = (i.opcode >> 3) & 0x1F; if (mode == 8) { const tmp = m.d[rx]; m.d[rx] = m.d[ry]; m.d[ry] = tmp; } else if (mode == 9) { const tmp = m.a[rx]; m.a[rx] = m.a[ry]; m.a[ry] = tmp; } else { const tmp = m.d[rx]; m.d[rx] = m.a[ry]; m.a[ry] = tmp; } m.pc += i.size; return 6; }
fn executeChk(m: *cpu.M68k, i: *const decoder.Instruction) !u32 { const r = switch (i.dst) { .DataReg => |v| v, else => 0 }; const b = try getOperandValue(m, i.src, .Word); const v = m.d[r] & 0xFFFF; if (v > b or (v & 0x8000) != 0) { try m.enterException(6, m.pc + i.size, 0, null); return 44; } m.pc += i.size; return 10; }
fn executeTas(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const v = try getOperandValue(m, i.dst, .Byte);
    m.setFlags(v, .Byte);
    try setOperandValue(m, i.dst, v | 0x80, .Byte);
    m.pc += i.size;
    return if (isMem(i.dst)) 14 else 4;
}
fn executeAbcd(m: *cpu.M68k, i: *const decoder.Instruction) !u32 { const s = try getOperandValue(m, i.src, .Byte); const d = try getOperandValue(m, i.dst, .Byte); const res = addBcd(@truncate(d), @truncate(s), m.getFlag(cpu.M68k.FLAG_X)); try setOperandValue(m, i.dst, res.result, .Byte); m.setFlag(cpu.M68k.FLAG_X, res.carry); m.setFlag(cpu.M68k.FLAG_C, res.carry); if (res.result != 0) { m.setFlag(cpu.M68k.FLAG_Z, false); } m.pc += i.size; return 6; }
fn executeSbcd(m: *cpu.M68k, i: *const decoder.Instruction) !u32 { const s = try getOperandValue(m, i.src, .Byte); const d = try getOperandValue(m, i.dst, .Byte); const res = subBcd(@truncate(d), @truncate(s), m.getFlag(cpu.M68k.FLAG_X)); try setOperandValue(m, i.dst, res.result, .Byte); m.setFlag(cpu.M68k.FLAG_X, res.carry); m.setFlag(cpu.M68k.FLAG_C, res.carry); if (res.result != 0) { m.setFlag(cpu.M68k.FLAG_Z, false); } m.pc += i.size; return 6; }
fn executeNbcd(m: *cpu.M68k, i: *const decoder.Instruction) !u32 { const v = try getOperandValue(m, i.dst, .Byte); const res = subBcd(0, @truncate(v), m.getFlag(cpu.M68k.FLAG_X)); try setOperandValue(m, i.dst, res.result, .Byte); m.setFlag(cpu.M68k.FLAG_X, res.carry); m.setFlag(cpu.M68k.FLAG_C, res.carry); if (res.result != 0) { m.setFlag(cpu.M68k.FLAG_Z, false); } m.pc += i.size; return 6; }
fn executeMovep(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const is_m_to_r = switch (i.dst) { .DataReg => true, else => false };
    if (is_m_to_r) { 
        const r = switch (i.dst) { .DataReg => |v| v, else => 0 }; 
        const a = try calculateEA(m, i.src); 
        if (i.data_size == .Word) {
            const hi = @as(u32, try m.memory.read8(a)) << 8;
            const lo = @as(u32, try m.memory.read8(a + 2));
            m.d[r] = (m.d[r] & 0xFFFF0000) | hi | lo;
        } else {
            const b0 = @as(u32, try m.memory.read8(a)) << 24;
            const b1 = @as(u32, try m.memory.read8(a + 2)) << 16;
            const b2 = @as(u32, try m.memory.read8(a + 4)) << 8;
            const b3 = @as(u32, try m.memory.read8(a + 6));
            m.d[r] = b0 | b1 | b2 | b3;
        }
    }
    else { 
        const r = switch (i.src) { .DataReg => |v| v, else => 0 }; 
        const a = try calculateEA(m, i.dst); 
        const v = m.d[r]; 
        if (i.data_size == .Word) { 
            try m.memory.write8(a, @truncate(v >> 8)); 
            try m.memory.write8(a + 2, @truncate(v & 0xFF)); 
        } else { 
            try m.memory.write8(a, @truncate(v >> 24)); 
            try m.memory.write8(a + 2, @truncate(v >> 16)); 
            try m.memory.write8(a + 4, @truncate(v >> 8)); 
            try m.memory.write8(a + 6, @truncate(v & 0xFF)); 
        }
    }
    m.pc += 4; 
    return 16;
}
fn executeBftst(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const ext = switch (i.src) { .Immediate16 => |v| v, else => 0 };
    const offset = if ((ext & 0x800) != 0) m.d[@as(u3, @truncate((ext >> 6) & 7))] & 31 else @as(u32, (ext >> 6) & 31);
    const width = if ((ext & 0x20) != 0) ((m.d[@as(u3, @truncate(ext & 7))] - 1) & 31) + 1 else (((ext & 31) - 1) & 31) + 1;
    const base = try getOperandValue(m, i.dst, .Long);
    var field: u32 = 0; var bit = offset;
    for (0..width) |_| { if ((base & (@as(u32, 1) << @truncate(bit))) != 0) { field |= @as(u32, 1) << @truncate(width - 1 - bit + offset); } bit = (bit + 1) & 31; }
    m.setFlag(cpu.M68k.FLAG_Z, field == 0); m.setFlag(cpu.M68k.FLAG_N, (field & (@as(u32, 1) << @truncate(width - 1))) != 0);
    m.setFlag(cpu.M68k.FLAG_V, false); m.setFlag(cpu.M68k.FLAG_C, false); m.pc += 4; return bitfieldCycles(i.dst, false);
}
fn executeBfset(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const ext = switch (i.src) { .Immediate16 => |v| v, else => 0 };
    const offset = if ((ext & 0x800) != 0) m.d[@as(u3, @truncate((ext >> 6) & 7))] & 31 else @as(u32, (ext >> 6) & 31);
    const width = if ((ext & 0x20) != 0) ((m.d[@as(u3, @truncate(ext & 7))] - 1) & 31) + 1 else (((ext & 31) - 1) & 31) + 1;
    var val = try getOperandValue(m, i.dst, .Long);
    var mask: u32 = 0; for (0..width) |j| { mask |= @as(u32, 1) << @truncate((offset + j) & 31); }
    const field = val & mask; m.setFlag(cpu.M68k.FLAG_Z, field == 0); m.setFlag(cpu.M68k.FLAG_N, (val & (@as(u32, 1) << @truncate((offset + width - 1) & 31))) != 0);
    val |= mask; try setOperandValue(m, i.dst, val, .Long); m.pc += 4; return bitfieldCycles(i.dst, true);
}
fn executeBfclr(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const ext = switch (i.src) { .Immediate16 => |v| v, else => 0 };
    const offset = if ((ext & 0x800) != 0) m.d[@as(u3, @truncate((ext >> 6) & 7))] & 31 else @as(u32, (ext >> 6) & 31);
    const width = if ((ext & 0x20) != 0) ((m.d[@as(u3, @truncate(ext & 7))] - 1) & 31) + 1 else (((ext & 31) - 1) & 31) + 1;
    var val = try getOperandValue(m, i.dst, .Long);
    var mask: u32 = 0; for (0..width) |j| { mask |= @as(u32, 1) << @truncate((offset + j) & 31); }
    const field = val & mask; m.setFlag(cpu.M68k.FLAG_Z, field == 0); m.setFlag(cpu.M68k.FLAG_N, (val & (@as(u32, 1) << @truncate((offset + width - 1) & 31))) != 0);
    val &= ~mask; try setOperandValue(m, i.dst, val, .Long); m.pc += 4; return bitfieldCycles(i.dst, true);
}
fn executeBfchg(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const ext = switch (i.src) { .Immediate16 => |v| v, else => 0 };
    const offset = if ((ext & 0x800) != 0) m.d[@as(u3, @truncate((ext >> 6) & 7))] & 31 else @as(u32, (ext >> 6) & 31);
    const width = if ((ext & 0x20) != 0) ((m.d[@as(u3, @truncate(ext & 7))] - 1) & 31) + 1 else (((ext & 31) - 1) & 31) + 1;
    var val = try getOperandValue(m, i.dst, .Long);
    var mask: u32 = 0; for (0..width) |j| { mask |= @as(u32, 1) << @truncate((offset + j) & 31); }
    const field = val & mask; m.setFlag(cpu.M68k.FLAG_Z, field == 0); m.setFlag(cpu.M68k.FLAG_N, (val & (@as(u32, 1) << @truncate((offset + width - 1) & 31))) != 0);
    val ^= mask; try setOperandValue(m, i.dst, val, .Long); m.pc += 4; return bitfieldCycles(i.dst, true);
}
fn executeBfexts(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const ext = switch (i.src) { .Immediate16 => |v| v, else => 0 }; const dn = @as(u3, @truncate((ext >> 12) & 7));
    const offset = if ((ext & 0x800) != 0) m.d[@as(u3, @truncate((ext >> 6) & 7))] & 31 else @as(u32, (ext >> 6) & 31);
    const width = if ((ext & 0x20) != 0) ((m.d[@as(u3, @truncate(ext & 7))] - 1) & 31) + 1 else (((ext & 31) - 1) & 31) + 1;
    const val = try getOperandValue(m, i.dst, .Long); var field: u32 = 0;
    for (0..width) |j| { if ((val & (@as(u32, 1) << @truncate((offset + j) & 31))) != 0) { field |= @as(u32, 1) << @truncate(j); } }
    if ((field & (@as(u32, 1) << @truncate(width - 1))) != 0) { field |= ~(@as(u32, 0) >> @truncate(32 - width)); }
    m.d[dn] = field; m.setFlag(cpu.M68k.FLAG_Z, field == 0); m.setFlag(cpu.M68k.FLAG_N, (field & 0x80000000) != 0); m.pc += 4; return if (isMem(i.dst)) 12 else 8;
}
fn executeBfextu(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const ext = switch (i.src) { .Immediate16 => |v| v, else => 0 }; const dn = @as(u3, @truncate((ext >> 12) & 7));
    const offset = if ((ext & 0x800) != 0) m.d[@as(u3, @truncate((ext >> 6) & 7))] & 31 else @as(u32, (ext >> 6) & 31);
    const width = if ((ext & 0x20) != 0) ((m.d[@as(u3, @truncate(ext & 7))] - 1) & 31) + 1 else (((ext & 31) - 1) & 31) + 1;
    const val = try getOperandValue(m, i.dst, .Long); var field: u32 = 0;
    for (0..width) |j| { if ((val & (@as(u32, 1) << @truncate((offset + j) & 31))) != 0) { field |= @as(u32, 1) << @truncate(j); } }
    m.d[dn] = field; m.setFlag(cpu.M68k.FLAG_Z, field == 0); m.setFlag(cpu.M68k.FLAG_N, false); m.pc += 4; return if (isMem(i.dst)) 12 else 8;
}
fn executeBfins(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const ext = switch (i.src) { .Immediate16 => |v| v, else => 0 }; const dn = @as(u3, @truncate((ext >> 12) & 7));
    const offset = if ((ext & 0x800) != 0) m.d[@as(u3, @truncate((ext >> 6) & 7))] & 31 else @as(u32, (ext >> 6) & 31);
    const width = if ((ext & 0x20) != 0) ((m.d[@as(u3, @truncate(ext & 7))] - 1) & 31) + 1 else (((ext & 31) - 1) & 31) + 1;
    var val = try getOperandValue(m, i.dst, .Long); var mask: u32 = 0;
    for (0..width) |j| { mask |= @as(u32, 1) << @truncate((offset + j) & 31); }
    val &= ~mask; for (0..width) |j| { if ((m.d[dn] & (@as(u32, 1) << @truncate(j))) != 0) { val |= @as(u32, 1) << @truncate((offset + j) & 31); } }
    m.setFlag(cpu.M68k.FLAG_Z, (val & mask) == 0); m.setFlag(cpu.M68k.FLAG_N, (val & (@as(u32, 1) << @truncate((offset + width - 1) & 31))) != 0);
    try setOperandValue(m, i.dst, val, .Long); m.pc += 4; return bitfieldCycles(i.dst, true);
}
fn executeBfffo(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const ext = switch (i.src) { .Immediate16 => |v| v, else => 0 }; const dn = @as(u3, @truncate((ext >> 12) & 7));
    const offset = if ((ext & 0x800) != 0) m.d[@as(u3, @truncate((ext >> 6) & 7))] & 31 else @as(u32, (ext >> 6) & 31);
    const width = if ((ext & 0x20) != 0) ((m.d[@as(u3, @truncate(ext & 7))] - 1) & 31) + 1 else (((ext & 31) - 1) & 31) + 1;
    const val = try getOperandValue(m, i.dst, .Long); var ffo: u32 = offset;
    for (0..width) |j| { if ((val & (@as(u32, 1) << @truncate((offset + j) & 31))) != 0) { ffo = offset + @as(u32, @truncate(j)); break; } } else { ffo = offset + width; }
    m.d[dn] = ffo; m.setFlag(cpu.M68k.FLAG_Z, ffo == offset + width); m.setFlag(cpu.M68k.FLAG_N, false); m.pc += 4; return if (isMem(i.dst)) 14 else 10;
}
fn executeCas(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const ext = switch (i.src) { .Immediate16 => |v| v, else => 0 }; const dc = @as(u3, @truncate(ext & 7)); const du = @as(u3, @truncate((ext >> 6) & 7));
    const mem = try getOperandValue(m, i.dst, i.data_size); const comp = getRegisterValue(m.d[dc], i.data_size);
    if (mem == comp) { try setOperandValue(m, i.dst, getRegisterValue(m.d[du], i.data_size), i.data_size); m.setFlag(cpu.M68k.FLAG_Z, true); }
    else { setRegisterValue(&m.d[dc], mem, i.data_size); m.setFlag(cpu.M68k.FLAG_Z, false); }
    setArithmeticFlags(m, mem, comp, mem -% comp, i.data_size, true); m.pc += 4; return 12;
}
fn executeCas2(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const ext1 = switch (i.src) { .Immediate16 => |v| v, else => 0 }; const ext2 = switch (i.dst) { .Immediate16 => |v| v, else => 0 };
    const r1 = @as(u3, @truncate((ext1 >> 12) & 7)); const a1 = if ((ext1 & 0x8000) != 0) m.a[r1] else m.d[r1];
    const r2 = @as(u3, @truncate((ext2 >> 12) & 7)); const a2 = if ((ext2 & 0x8000) != 0) m.a[r2] else m.d[r2];
    const dc1 = @as(u3, @truncate(ext1 & 7)); const du1 = @as(u3, @truncate((ext1 >> 8) & 7));
    const dc2 = @as(u3, @truncate(ext2 & 7)); const du2 = @as(u3, @truncate((ext2 >> 8) & 7));
    const m1 = if (i.data_size == .Word) @as(u32, try m.memory.read16(a1)) else try m.memory.read32(a1);
    const m2 = if (i.data_size == .Word) @as(u32, try m.memory.read16(a2)) else try m.memory.read32(a2);
    const c1 = getRegisterValue(m.d[dc1], i.data_size); const c2 = getRegisterValue(m.d[dc2], i.data_size);
    if (m1 == c1 and m2 == c2) {
        const up1 = getRegisterValue(m.d[du1], i.data_size); const up2 = getRegisterValue(m.d[du2], i.data_size);
        if (i.data_size == .Word) { try m.memory.write16(a1, @truncate(up1)); try m.memory.write16(a2, @truncate(up2)); }
        else { try m.memory.write32(a1, up1); try m.memory.write32(a2, up2); }
        m.setFlag(cpu.M68k.FLAG_Z, true);
    } else { setRegisterValue(&m.d[dc1], m1, i.data_size); setRegisterValue(&m.d[dc2], m2, i.data_size); m.setFlag(cpu.M68k.FLAG_Z, false); }
    m.setFlag(cpu.M68k.FLAG_N, false); m.setFlag(cpu.M68k.FLAG_V, false); m.setFlag(cpu.M68k.FLAG_C, false); m.pc += 6; return 20;
}
fn executeCallm(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const arg_count: u16 = switch (i.src) {
        .Immediate8 => |v| v,
        else => return error.InvalidOperand,
    };
    const descriptor_addr = try calculateEA(m, i.dst);
    const entry_ptr = try m.memory.read32(descriptor_addr + 4);
    const module_data_ptr = try m.memory.read32(descriptor_addr + 8);
    const entry_word = try m.memory.read16(entry_ptr);
    const reg_spec: u4 = @truncate((entry_word >> 12) & 0xF);
    const is_addr_reg = (reg_spec & 0x8) != 0;
    const reg: u3 = @truncate(reg_spec & 0x7);
    const saved_reg_value = if (is_addr_reg) m.a[reg] else m.d[reg];

    m.a[7] -= 12;
    try m.memory.write16(m.a[7], m.sr & 0x00FF);
    try m.memory.write32(m.a[7] + 2, m.pc + i.size);
    try m.memory.write32(m.a[7] + 6, saved_reg_value);
    try m.memory.write16(m.a[7] + 10, arg_count);

    // A7 is the active module frame stack; keep it stable.
    if (!(is_addr_reg and reg == 7)) {
        if (is_addr_reg) m.a[reg] = module_data_ptr else m.d[reg] = module_data_ptr;
    }
    m.pc = entry_ptr + 2;
    return 40;
}
fn executeRtm(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const restore_addr_reg = switch (i.dst) {
        .AddrReg => true,
        .DataReg => false,
        else => return error.InvalidOperand,
    };
    const reg: u3 = switch (i.dst) {
        .AddrReg => |r| r,
        .DataReg => |r| r,
        else => unreachable,
    };

    const sp = m.a[7];
    const saved_ccr = try m.memory.read16(sp);
    const return_pc = try m.memory.read32(sp + 2);
    const saved_reg_value = try m.memory.read32(sp + 6);
    const arg_count = try m.memory.read16(sp + 10);

    m.sr = (m.sr & 0xFF00) | (saved_ccr & 0x00FF);
    if (restore_addr_reg) {
        if (reg != 7) m.a[reg] = saved_reg_value;
    } else {
        m.d[reg] = saved_reg_value;
    }
    m.a[7] = sp + 12 + @as(u32, arg_count);
    m.pc = return_pc;
    return 24;
}
fn executeRtd(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const disp: i16 = @bitCast(switch (i.src) { .Immediate16 => |v| v, else => 0 });
    m.pc = try m.memory.read32(m.a[7]);
    m.a[7] = @bitCast(@as(i32, @bitCast(m.a[7])) + 4 + @as(i32, disp));
    return 10;
}
fn executeBkpt(m: *cpu.M68k, _: *const decoder.Instruction) !u32 {
    const opcode = try m.memory.read16(m.pc);
    const vector: u3 = @truncate(opcode & 0x7);
    if (m.bkpt_handler) |handler| {
        const pc_before = m.pc;
        switch (handler(m.bkpt_ctx, m, vector, m.pc)) {
            .handled => |cycles| {
                if (m.pc == pc_before) m.pc += 2;
                return cycles;
            },
            .illegal => {},
        }
    }
    // Without an attached debugger, BKPT behaves like an illegal instruction trap.
    try m.enterException(4, m.pc, 0, null);
    return 10;
}
fn executeTrapcc(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const cond: u4 = @truncate((i.opcode >> 8) & 0xF);
    if (evaluateCondition(m, cond)) {
        try m.enterException(7, m.pc + i.size, 0, null);
        return 33;
    }
    m.pc += i.size;
    return 3;
}
fn executeChk2(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const ext = i.extension_word orelse return error.InvalidExtensionWord;
    const reg: u3 = @truncate((ext >> 12) & 7);
    const is_addr = (ext & 0x8000) != 0;
    const cmp_val = if (is_addr) m.a[reg] else m.d[reg];
    const size_bytes = getSizeBytes(i.data_size);
    const ea = try calculateEA(m, i.src);
    const lower = if (i.data_size == .Byte) @as(u32, try m.memory.read8(ea)) else if (i.data_size == .Word) @as(u32, try m.memory.read16(ea)) else try m.memory.read32(ea);
    const upper_addr = ea + size_bytes;
    const upper = if (i.data_size == .Byte) @as(u32, try m.memory.read8(upper_addr)) else if (i.data_size == .Word) @as(u32, try m.memory.read16(upper_addr)) else try m.memory.read32(upper_addr);
    const in_range = isWithinBounds(cmp_val, lower, upper, i.data_size);

    m.setFlag(cpu.M68k.FLAG_Z, in_range);
    m.setFlag(cpu.M68k.FLAG_N, compareSized(cmp_val, lower, i.data_size) < 0);
    m.setFlag(cpu.M68k.FLAG_V, false);
    m.setFlag(cpu.M68k.FLAG_C, compareSized(cmp_val, upper, i.data_size) > 0);
    m.pc += i.size;

    if (!in_range) {
        try m.enterException(6, m.pc, 0, null);
        return 44;
    }
    return 15;
}
fn executeCmp2(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const ext = i.extension_word orelse return error.InvalidExtensionWord;
    const reg: u3 = @truncate((ext >> 12) & 7);
    const is_addr = (ext & 0x8000) != 0;
    const cmp_val = if (is_addr) m.a[reg] else m.d[reg];
    const size_bytes = getSizeBytes(i.data_size);
    const ea = try calculateEA(m, i.src);
    const lower = if (i.data_size == .Byte) @as(u32, try m.memory.read8(ea)) else if (i.data_size == .Word) @as(u32, try m.memory.read16(ea)) else try m.memory.read32(ea);
    const upper_addr = ea + size_bytes;
    const upper = if (i.data_size == .Byte) @as(u32, try m.memory.read8(upper_addr)) else if (i.data_size == .Word) @as(u32, try m.memory.read16(upper_addr)) else try m.memory.read32(upper_addr);
    const in_range = isWithinBounds(cmp_val, lower, upper, i.data_size);

    m.setFlag(cpu.M68k.FLAG_Z, in_range);
    m.setFlag(cpu.M68k.FLAG_N, compareSized(cmp_val, lower, i.data_size) < 0);
    m.setFlag(cpu.M68k.FLAG_V, false);
    m.setFlag(cpu.M68k.FLAG_C, compareSized(cmp_val, upper, i.data_size) > 0);
    m.pc += i.size;
    return 12;
}
fn executePack(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const ext = i.extension_word orelse return error.InvalidExtensionWord;
    const adj: i16 = @bitCast(ext);
    const src_word: u16 = switch (i.src) {
        .DataReg => |r| @truncate(m.d[r]),
        .AddrPreDec => @truncate(try getOperandValue(m, i.src, .Word)),
        else => return error.InvalidOperand,
    };

    const adjusted: u16 = src_word +% @as(u16, @bitCast(adj));
    const packed_bcd: u8 = @truncate((((adjusted >> 8) & 0xF) << 4) | (adjusted & 0xF));

    switch (i.dst) {
        .DataReg => |r| setRegisterValue(&m.d[r], packed_bcd, .Byte),
        .AddrPreDec => try setOperandValue(m, i.dst, packed_bcd, .Byte),
        else => return error.InvalidOperand,
    }

    m.pc += i.size;
    return if (i.src == .DataReg) 5 else 6;
}
fn executeUnpk(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const ext = i.extension_word orelse return error.InvalidExtensionWord;
    const adj: i16 = @bitCast(ext);
    const src_byte: u8 = switch (i.src) {
        .DataReg => |r| @truncate(m.d[r]),
        .AddrPreDec => @truncate(try getOperandValue(m, i.src, .Byte)),
        else => return error.InvalidOperand,
    };

    const unpacked: u16 = (((@as(u16, src_byte) >> 4) & 0xF) << 8) | (@as(u16, src_byte) & 0xF);
    const adjusted: u16 = unpacked +% @as(u16, @bitCast(adj));

    switch (i.dst) {
        .DataReg => |r| setRegisterValue(&m.d[r], adjusted, .Word),
        .AddrPreDec => try setOperandValue(m, i.dst, adjusted, .Word),
        else => return error.InvalidOperand,
    }

    m.pc += i.size;
    return if (i.src == .DataReg) 5 else 6;
}
fn executeMulsL(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const ext = i.extension_word orelse return error.InvalidExtensionWord;
    const dl: u3 = @truncate(ext & 0x7);
    const dh: u3 = @truncate((ext >> 12) & 0x7);
    const multiplicand: i32 = @bitCast(m.d[dl]);
    const multiplier: i32 = @bitCast(try getOperandValue(m, i.src, .Long));
    const prod: i64 = @as(i64, multiplicand) * @as(i64, multiplier);
    const prod_u: u64 = @bitCast(prod);
    const high: i32 = @bitCast(@as(u32, @truncate(prod_u >> 32)));
    const low: i32 = @bitCast(@as(u32, @truncate(prod_u)));
    const sign_ext: i32 = if (low < 0) @as(i32, -1) else @as(i32, 0);
    m.d[dl] = @bitCast(low);
    if (dh != dl) m.d[dh] = @bitCast(high);
    m.setFlags(m.d[dl], .Long);
    m.setFlag(cpu.M68k.FLAG_V, high != sign_ext);
    m.setFlag(cpu.M68k.FLAG_C, false);
    m.pc += i.size;
    return 40;
}
fn executeMuluL(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const ext = i.extension_word orelse return error.InvalidExtensionWord;
    const dl: u3 = @truncate(ext & 0x7);
    const dh: u3 = @truncate((ext >> 12) & 0x7);
    const multiplicand: u64 = m.d[dl];
    const multiplier: u64 = try getOperandValue(m, i.src, .Long);
    const prod: u64 = multiplicand * multiplier;
    m.d[dl] = @truncate(prod);
    if (dh != dl) m.d[dh] = @truncate(prod >> 32);
    m.setFlags(m.d[dl], .Long);
    m.setFlag(cpu.M68k.FLAG_V, (prod >> 32) != 0);
    m.setFlag(cpu.M68k.FLAG_C, false);
    m.pc += i.size;
    return 40;
}
fn executeDivsL(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const ext = i.extension_word orelse return error.InvalidExtensionWord;
    const dq: u3 = @truncate(ext & 0x7);
    const dr: u3 = @truncate((ext >> 12) & 0x7);
    const divisor: i32 = @bitCast(try getOperandValue(m, i.src, .Long));
    if (divisor == 0) {
        try m.enterException(5, m.pc, 0, null);
        return 70;
    }

    const dividend: i64 = if (dr != dq)
        @as(i64, @bitCast((@as(u64, m.d[dr]) << 32) | @as(u64, m.d[dq])))
    else
        @as(i64, @as(i32, @bitCast(m.d[dq])));

    const quot = @divTrunc(dividend, @as(i64, divisor));
    const rem = @rem(dividend, @as(i64, divisor));
    if (quot < std.math.minInt(i32) or quot > std.math.maxInt(i32)) {
        m.setFlag(cpu.M68k.FLAG_V, true);
    } else {
        m.d[dq] = @bitCast(@as(i32, @truncate(quot)));
        m.d[dr] = @bitCast(@as(i32, @truncate(rem)));
        m.setFlags(m.d[dq], .Long);
        m.setFlag(cpu.M68k.FLAG_V, false);
    }
    m.setFlag(cpu.M68k.FLAG_C, false);
    m.pc += i.size;
    return 76;
}
fn executeDivuL(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const ext = i.extension_word orelse return error.InvalidExtensionWord;
    const dq: u3 = @truncate(ext & 0x7);
    const dr: u3 = @truncate((ext >> 12) & 0x7);
    const divisor: u64 = try getOperandValue(m, i.src, .Long);
    if (divisor == 0) {
        try m.enterException(5, m.pc, 0, null);
        return 70;
    }

    const dividend: u64 = if (dr != dq)
        (@as(u64, m.d[dr]) << 32) | @as(u64, m.d[dq])
    else
        @as(u64, m.d[dq]);

    const quot = dividend / divisor;
    const rem = dividend % divisor;
    if (quot > std.math.maxInt(u32)) {
        m.setFlag(cpu.M68k.FLAG_V, true);
    } else {
        m.d[dq] = @truncate(quot);
        m.d[dr] = @truncate(rem);
        m.setFlags(m.d[dq], .Long);
        m.setFlag(cpu.M68k.FLAG_V, false);
    }
    m.setFlag(cpu.M68k.FLAG_C, false);
    m.pc += i.size;
    return 76;
}

fn getRegisterValue(v: u32, s: decoder.DataSize) u32 { return switch (s) { .Byte => v & 0xFF, .Word => v & 0xFFFF, .Long => v }; }
fn setRegisterValue(r: *u32, v: u32, s: decoder.DataSize) void { switch (s) { .Byte => r.* = (r.* & 0xFFFFFF00) | (v & 0xFF), .Word => r.* = (r.* & 0xFFFF0000) | (v & 0xFFFF), .Long => r.* = v } }
fn getSizeBytes(s: decoder.DataSize) u32 {
    return switch (s) { .Byte => 1, .Word => 2, .Long => 4 };
}
fn signExtendSized(v: u32, s: decoder.DataSize) i64 {
    return switch (s) {
        .Byte => @as(i64, @as(i8, @bitCast(@as(u8, @truncate(v))))),
        .Word => @as(i64, @as(i16, @bitCast(@as(u16, @truncate(v))))),
        .Long => @as(i64, @as(i32, @bitCast(v))),
    };
}
fn compareSized(a: u32, b: u32, s: decoder.DataSize) i8 {
    const sa = signExtendSized(a, s);
    const sb = signExtendSized(b, s);
    if (sa < sb) return -1;
    if (sa > sb) return 1;
    return 0;
}
fn isWithinBounds(value: u32, lower: u32, upper: u32, s: decoder.DataSize) bool {
    return compareSized(value, lower, s) >= 0 and compareSized(value, upper, s) <= 0;
}
fn getOperandValue(m: *cpu.M68k, op: decoder.Operand, s: decoder.DataSize) !u32 {
    const readMem = struct {
        fn run(mm: *cpu.M68k, addr: u32, sz: decoder.DataSize) !u32 {
            mm.noteDataAccess(addr, false);
            const access = memory.BusAccess{
                .function_code = mm.dfc,
                .space = .Data,
                .is_write = false,
            };
            return if (sz == .Byte)
                try mm.memory.read8Bus(addr, access)
            else if (sz == .Word)
                try mm.memory.read16Bus(addr, access)
            else
                try mm.memory.read32Bus(addr, access);
        }
    }.run;
    return switch (op) {
        .DataReg => |r| getRegisterValue(m.d[r], s), .AddrReg => |r| m.a[r], .Immediate8 => |v| v, .Immediate16 => |v| v, .Immediate32 => |v| v,
        .AddrIndirect => |r| try readMem(m, m.a[r], s),
        .AddrPostInc => |r| { const a = m.a[r]; const inc: u32 = if (s == .Byte) (if (r == 7) 2 else 1) else if (s == .Word) 2 else 4; m.a[r] += inc; return try readMem(m, a, s); },
        .AddrPreDec => |r| { const inc: u32 = if (s == .Byte) (if (r == 7) 2 else 1) else if (s == .Word) 2 else 4; m.a[r] -= inc; return try readMem(m, m.a[r], s); },
        .Address => |a| try readMem(m, a, s),
        .AddrDisplace => |i| { const a = @as(u32, @bitCast(@as(i32, @bitCast(m.a[i.reg])) + @as(i32, i.displacement))); return try readMem(m, a, s); },
        .ComplexEA => |ea| {
            const a = try resolveComplexEA(m, ea);
            return try readMem(m, a, s);
        },
        else => 0,
    };
}
fn setOperandValue(m: *cpu.M68k, op: decoder.Operand, v: u32, s: decoder.DataSize) !void {
    const writeMem = struct {
        fn run(mm: *cpu.M68k, addr: u32, value: u32, sz: decoder.DataSize) !void {
            mm.noteDataAccess(addr, true);
            const access = memory.BusAccess{
                .function_code = mm.dfc,
                .space = .Data,
                .is_write = true,
            };
            if (sz == .Byte)
                try mm.memory.write8Bus(addr, @truncate(value), access)
            else if (sz == .Word)
                try mm.memory.write16Bus(addr, @truncate(value), access)
            else
                try mm.memory.write32Bus(addr, value, access);
        }
    }.run;
    switch (op) {
        .DataReg => |r| setRegisterValue(&m.d[r], v, s),
        .AddrReg => |r| m.a[r] = v,
        .AddrIndirect => |r| {
            try writeMem(m, m.a[r], v, s);
        },
        .AddrPostInc => |r| {
            const a = m.a[r];
            const inc: u32 = if (s == .Byte) (if (r == 7) 2 else 1) else if (s == .Word) 2 else 4;
            try writeMem(m, a, v, s);
            m.a[r] += inc;
        },
        .AddrPreDec => |r| {
            const inc: u32 = if (s == .Byte) (if (r == 7) 2 else 1) else if (s == .Word) 2 else 4;
            m.a[r] -= inc;
            try writeMem(m, m.a[r], v, s);
        },
        .Address => |a| {
            try writeMem(m, a, v, s);
        },
        .AddrDisplace => |i| {
            const a = @as(u32, @bitCast(@as(i32, @bitCast(m.a[i.reg])) + @as(i32, i.displacement)));
            try writeMem(m, a, v, s);
        },
        .ComplexEA => |ea| {
            const a = try resolveComplexEA(m, ea);
            try writeMem(m, a, v, s);
        },
        else => {},
    }
}
fn calculateEA(m: *cpu.M68k, op: decoder.Operand) !u32 {
    return switch (op) {
        .AddrIndirect => |r| m.a[r],
        .Address => |a| a,
        .AddrDisplace => |i| @as(u32, @bitCast(@as(i32, @bitCast(m.a[i.reg])) + @as(i32, i.displacement))),
        .ComplexEA => |ea| try resolveComplexEA(m, ea),
        else => 0,
    };
}
fn addSigned(base: u32, disp: i32) u32 {
    return @bitCast(@as(i32, @bitCast(base)) +% disp);
}
fn indexValue(m: *cpu.M68k, idx: decoder.IndexReg) i32 {
    const raw: u32 = if (idx.is_addr) m.a[idx.reg] else m.d[idx.reg];
    const signed: i32 = if (idx.is_long)
        @bitCast(raw)
    else
        @as(i32, @as(i16, @bitCast(@as(u16, @truncate(raw)))));
    return signed * @as(i32, idx.scale);
}
fn resolveComplexEA(m: *cpu.M68k, ea: std.meta.FieldType(decoder.Operand, .ComplexEA)) !u32 {
    var addr: u32 = if (ea.is_pc_relative)
        m.pc + 2
    else if (ea.base_reg) |r|
        m.a[r]
    else
        0;

    addr = addSigned(addr, ea.base_disp);

    if (!ea.is_mem_indirect) {
        if (ea.index_reg) |idx| {
            addr = addSigned(addr, indexValue(m, idx));
        }
        return addSigned(addr, ea.outer_disp);
    }

    // Memory indirect: read pointer then apply pre/post indexing and outer displacement.
    var ptr_addr = addr;
    if (!ea.is_post_indexed) {
        if (ea.index_reg) |idx| {
            ptr_addr = addSigned(ptr_addr, indexValue(m, idx));
        }
    }

    m.noteDataAccess(ptr_addr, false);
    var effective = try m.memory.read32(ptr_addr);
    if (ea.is_post_indexed) {
        if (ea.index_reg) |idx| {
            effective = addSigned(effective, indexValue(m, idx));
        }
    }
    return addSigned(effective, ea.outer_disp);
}
fn setArithmeticFlags(m: *cpu.M68k, d: u32, s: u32, r: u32, sz: decoder.DataSize, sub: bool) void {
    const mask: u32 = if (sz == .Byte) 0xFF else if (sz == .Word) 0xFFFF else 0xFFFFFFFF;
    const sign: u32 = if (sz == .Byte) 0x80 else if (sz == .Word) 0x8000 else 0x80000000;
    const md = d & mask;
    const ms = s & mask;
    const mr = r & mask;

    m.setFlag(cpu.M68k.FLAG_Z, mr == 0);
    m.setFlag(cpu.M68k.FLAG_N, (mr & sign) != 0);

    if (sub) {
        const borrow = ms > md;
        const overflow = (((md ^ ms) & (md ^ mr)) & sign) != 0;
        m.setFlag(cpu.M68k.FLAG_C, borrow);
        m.setFlag(cpu.M68k.FLAG_X, borrow);
        m.setFlag(cpu.M68k.FLAG_V, overflow);
    } else {
        const carry = (@as(u64, md) + @as(u64, ms)) > @as(u64, mask);
        const overflow = ((~(md ^ ms) & (md ^ mr)) & sign) != 0;
        m.setFlag(cpu.M68k.FLAG_C, carry);
        m.setFlag(cpu.M68k.FLAG_X, carry);
        m.setFlag(cpu.M68k.FLAG_V, overflow);
    }
}
fn evaluateCondition(m: *cpu.M68k, c: u4) bool {
    const cv = m.getFlag(cpu.M68k.FLAG_C); const vv = m.getFlag(cpu.M68k.FLAG_V); const zv = m.getFlag(cpu.M68k.FLAG_Z); const nv = m.getFlag(cpu.M68k.FLAG_N);
    return switch (c) { 0 => true, 1 => false, 2 => !cv and !zv, 3 => cv or zv, 4 => !cv, 5 => cv, 6 => !zv, 7 => zv, 8 => !vv, 9 => vv, 10 => !nv, 11 => nv, 12 => (nv == vv), 13 => (nv != vv), 14 => (nv == vv) and !zv, 15 => zv or (nv != vv) };
}
fn branchTakenCycles(size: u8) u32 {
    return switch (size) { 2 => 10, 4 => 12, 6 => 14, else => 10 };
}
fn branchNotTakenCycles(size: u8) u32 {
    return switch (size) { 2 => 8, 4 => 10, 6 => 12, else => 8 };
}
fn bitfieldCycles(dst: decoder.Operand, writes_back: bool) u32 {
    if (!isMem(dst)) return if (writes_back) 10 else 6;
    return if (writes_back) 14 else 10;
}
fn addBcd(d: u8, s: u8, x: bool) struct { result: u8, carry: bool } {
    var lo = (d & 0xF) + (s & 0xF) + (if (x) @as(u8, 1) else 0); var hi = (d >> 4) + (s >> 4); var c = false;
    if (lo > 9) { lo += 6; hi += 1; } if (hi > 9) { hi += 6; c = true; } return .{ .result = ((hi & 0xF) << 4) | (lo & 0xF), .carry = c };
}
fn subBcd(d: u8, s: u8, x: bool) struct { result: u8, carry: bool } {
    var lo: i16 = @as(i16, d & 0xF) - @as(i16, s & 0xF) - (if (x) @as(i16, 1) else 0); var hi: i16 = @as(i16, d >> 4) - @as(i16, s >> 4);
    if (lo < 0) { lo += 10; hi -= 1; } var c = false; if (hi < 0) { hi += 10; c = true; }
    return .{ .result = (@as(u8, @truncate(@as(u16, @bitCast(hi)))) << 4) | @as(u8, @truncate(@as(u16, @bitCast(lo)))), .carry = c };
}
fn isMem(op: decoder.Operand) bool { return switch (op) { .DataReg, .AddrReg, .None => false, else => true }; }
fn getEACycles(op: decoder.Operand, _: decoder.DataSize, _: bool) u32 { return switch (op) { .DataReg, .AddrReg => 0, .Immediate8, .Immediate16, .Immediate32 => 0, .AddrIndirect, .AddrPostInc => 2, .AddrPreDec, .AddrDisplace => 3, else => 4 }; }
const InstructionCycles = struct {
    pub fn get(m: decoder.Mnemonic, _: decoder.DataSize, mem: bool) u32 { return switch (m) { .MOVE => if (mem) 4 else 2, .MOVEQ => 2, .ADD, .SUB => if (mem) 4 else 2, .MULU, .MULS => 25, .DIVU, .DIVS => 45, .RTS => 10, .RTE => 15, .TRAP => 25, else => 4 }; }
};
