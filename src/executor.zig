const std = @import("std");
const cpu = @import("cpu.zig");
const decoder = @import("decoder.zig");

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
            .BRA => return try executeBra(m68k, inst),
            .Bcc => return try executeBcc(m68k, inst),
            .BSR => return try executeBsr(m68k, inst),
            .JSR => return try executeJsr(m68k, inst),
            .JMP => return try executeJmp(m68k, inst),
            .DBcc => return try executeDbcc(m68k, inst),
            .Scc => return try executeScc(m68k, inst),
            .ASL, .ASR, .LSL, .LSR, .ROL, .ROR => return try executeShift(m68k, inst),
            .BTST => return try executeBtst(m68k, inst),
            .BSET => return try executeBset(m68k, inst),
            .BCLR => return try executeBclr(m68k, inst),
            .BCHG => return try executeBchg(m68k, inst),
            .MOVEC => return try executeMovec(m68k, inst),
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
            else => { m68k.pc += inst.size; return 4; },
        }
    }
};

fn executeMoveq(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const r = switch (i.dst) { .DataReg => |v| v, else => return error.Err };
    const v: i8 = switch (i.src) { .Immediate8 => |w| @bitCast(w), else => 0 };
    m.d[r] = @bitCast(@as(i32, v)); m.setFlags(m.d[r], .Long); m.pc += 2; return 4;
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
    if (i.dst != .AddrReg) setArithmeticFlags(m, d, s, res, i.data_size, false); m.pc += 2; return 4;
}
fn executeAddx(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const x: u32 = if (m.getFlag(cpu.M68k.FLAG_X)) 1 else 0; const s = try getOperandValue(m, i.src, i.data_size); const d = try getOperandValue(m, i.dst, i.data_size); const res = d +% s +% x;
    try setOperandValue(m, i.dst, res, i.data_size); setArithmeticFlags(m, d, s +% x, res, i.data_size, false); m.pc += 2; return 4;
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
    if (i.dst != .AddrReg) setArithmeticFlags(m, d, s, res, i.data_size, true); m.pc += 2; return 4;
}
fn executeSubx(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const x: u32 = if (m.getFlag(cpu.M68k.FLAG_X)) 1 else 0; const s = try getOperandValue(m, i.src, i.data_size); const d = try getOperandValue(m, i.dst, i.data_size); const res = d -% s -% x;
    try setOperandValue(m, i.dst, res, i.data_size); setArithmeticFlags(m, d, s +% x, res, i.data_size, true); m.pc += 2; return 4;
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
    setArithmeticFlags(m, d, s, d -% s, i.data_size, true); m.pc += 2; return 12;
}
fn executeAnd(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const dir = (i.opcode >> 8) & 1;
    if (dir == 0) { const r = switch (i.dst) { .DataReg => |v| v, else => 0 }; const s = try getOperandValue(m, i.src, i.data_size); const res = m.d[r] & s; setRegisterValue(&m.d[r], res, i.data_size); m.setFlags(res, i.data_size); }
    else { const r = switch (i.src) { .DataReg => |v| v, else => 0 }; const s = getRegisterValue(m.d[r], i.data_size); const d = try getOperandValue(m, i.dst, i.data_size); const res = s & d; try setOperandValue(m, i.dst, res, i.data_size); m.setFlags(res, i.data_size); }
    m.pc += i.size; return 4;
}
fn executeAndi(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const s = try getOperandValue(m, i.src, i.data_size); const d = try getOperandValue(m, i.dst, i.data_size); const res = d & s; try setOperandValue(m, i.dst, res, i.data_size); m.setFlags(res, i.data_size); m.pc += i.size; return 8;
}
fn executeOr(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const dir = (i.opcode >> 8) & 1;
    if (dir == 0) { const r = switch (i.dst) { .DataReg => |v| v, else => 0 }; const s = try getOperandValue(m, i.src, i.data_size); const res = m.d[r] | s; setRegisterValue(&m.d[r], res, i.data_size); m.setFlags(res, i.data_size); }
    else { const r = switch (i.src) { .DataReg => |v| v, else => 0 }; const s = getRegisterValue(m.d[r], i.data_size); const d = try getOperandValue(m, i.dst, i.data_size); const res = s | d; try setOperandValue(m, i.dst, res, i.data_size); m.setFlags(res, i.data_size); }
    m.pc += i.size; return 4;
}
fn executeOri(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const s = try getOperandValue(m, i.src, i.data_size); const d = try getOperandValue(m, i.dst, i.data_size); const res = d | s; try setOperandValue(m, i.dst, res, i.data_size); m.setFlags(res, i.data_size); m.pc += i.size; return 8;
}
fn executeEor(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const r = switch (i.src) { .DataReg => |v| v, else => 0 }; const d = try getOperandValue(m, i.dst, i.data_size); const res = m.d[r] ^ d; try setOperandValue(m, i.dst, res, i.data_size); m.setFlags(res, i.data_size); m.pc += i.size; return 4;
}
fn executeEori(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const s = try getOperandValue(m, i.src, i.data_size); const d = try getOperandValue(m, i.dst, i.data_size); const res = d ^ s; try setOperandValue(m, i.dst, res, i.data_size); m.setFlags(res, i.data_size); m.pc += i.size; return 8;
}
fn executeNot(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const d = try getOperandValue(m, i.dst, i.data_size); const res = ~d; try setOperandValue(m, i.dst, res, i.data_size); m.setFlags(res, i.data_size); m.pc += 2; return 4;
}
fn executeMulu(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const r = switch (i.dst) { .DataReg => |v| v, else => 0 }; const s: u32 = try getOperandValue(m, i.src, .Word); const d: u32 = m.d[r] & 0xFFFF; const res = s * d; m.d[r] = res; m.setFlag(cpu.M68k.FLAG_N, (res & 0x80000000) != 0); m.setFlag(cpu.M68k.FLAG_Z, res == 0); m.setFlag(cpu.M68k.FLAG_V, false); m.setFlag(cpu.M68k.FLAG_C, false); m.pc += 2; return 38;
}
fn executeMuls(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const r = switch (i.dst) { .DataReg => |v| v, else => 0 }; const vs = try getOperandValue(m, i.src, .Word); const s16: i16 = @bitCast(@as(u16, @truncate(vs))); const d16: i16 = @bitCast(@as(u16, @truncate(m.d[r]))); const res: i32 = @as(i32, s16) * @as(i32, d16); m.d[r] = @bitCast(res); m.setFlag(cpu.M68k.FLAG_N, res < 0); m.setFlag(cpu.M68k.FLAG_Z, res == 0); m.setFlag(cpu.M68k.FLAG_V, false); m.setFlag(cpu.M68k.FLAG_C, false); m.pc += 2; return 38;
}
fn executeDivu(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const r = switch (i.dst) { .DataReg => |v| v, else => 0 }; const divisor = try getOperandValue(m, i.src, .Word); if (divisor == 0) { try pushExceptionFrame(m, m.pc, 5, 0); m.pc = try m.memory.read32(m.getExceptionVector(5)); m.sr |= 0x2000; return 38; }
    const res = m.d[r] / divisor; const rem = m.d[r] % divisor; if (res > 0xFFFF) { m.setFlag(cpu.M68k.FLAG_V, true); } else { m.d[r] = (rem << 16) | (res & 0xFFFF); m.setFlags(res & 0xFFFF, .Word); } m.pc += 2; return 76;
}
fn executeDivs(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const r = switch (i.dst) { .DataReg => |v| v, else => 0 }; const vs = try getOperandValue(m, i.src, .Word); const s: i16 = @bitCast(@as(u16, @truncate(vs))); if (s == 0) { try pushExceptionFrame(m, m.pc, 5, 0); m.pc = try m.memory.read32(m.getExceptionVector(5)); m.sr |= 0x2000; return 38; }
    const d: i32 = @bitCast(m.d[r]); const res = @divTrunc(d, s); const rem = @rem(d, s); if (res < -32768 or res > 32767) { m.setFlag(cpu.M68k.FLAG_V, true); } else { const u_rem: u16 = @bitCast(@as(i16, @truncate(rem))); const u_res: u16 = @bitCast(@as(i16, @truncate(res))); m.d[r] = (@as(u32, u_rem) << 16) | u_res; m.setFlags(@as(u32, u_res), .Word); } m.pc += 2; return 76;
}
fn executeNeg(m: *cpu.M68k, i: *const decoder.Instruction) !u32 { const d = try getOperandValue(m, i.dst, i.data_size); const res = 0 -% d; try setOperandValue(m, i.dst, res, i.data_size); setArithmeticFlags(m, 0, d, res, i.data_size, true); m.pc += 2; return 4; }
fn executeNegx(m: *cpu.M68k, i: *const decoder.Instruction) !u32 { const x: u32 = if (m.getFlag(cpu.M68k.FLAG_X)) 1 else 0; const d = try getOperandValue(m, i.dst, i.data_size); const res = 0 -% d -% x; try setOperandValue(m, i.dst, res, i.data_size); setArithmeticFlags(m, 0, d +% x, res, i.data_size, true); m.pc += 2; return 4; }
fn executeClr(m: *cpu.M68k, i: *const decoder.Instruction) !u32 { try setOperandValue(m, i.dst, 0, i.data_size); m.setFlags(0, i.data_size); m.pc += 2; return 4; }
fn executeTst(m: *cpu.M68k, i: *const decoder.Instruction) !u32 { const v = try getOperandValue(m, i.dst, i.data_size); m.setFlags(v, i.data_size); m.pc += 2; return 4; }
fn executeSwap(m: *cpu.M68k, i: *const decoder.Instruction) !u32 { const r = switch (i.dst) { .DataReg => |v| v, else => 0 }; const low = m.d[r] & 0xFFFF; const high = m.d[r] >> 16; m.d[r] = (low << 16) | high; m.setFlags(m.d[r], .Long); m.pc += 2; return 4; }
fn executeExt(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const r = switch (i.dst) { .DataReg => |v| v, else => 0 }; if (i.is_extb) { m.d[r] = @bitCast(@as(i32, @as(i8, @bitCast(@as(u8, @truncate(m.d[r])))))); }
    else if (i.data_size == .Word) { const ext_val = @as(i16, @as(i8, @bitCast(@as(u8, @truncate(m.d[r]))))); m.d[r] = (m.d[r] & 0xFFFF0000) | (@as(u32, @bitCast(@as(i32, ext_val))) & 0xFFFF); }
    else { m.d[r] = @bitCast(@as(i32, @as(i16, @bitCast(@as(u16, @truncate(m.d[r])))))); }
    m.setFlags(m.d[r], .Long); m.pc += 2; return 4;
}
fn executeLea(m: *cpu.M68k, i: *const decoder.Instruction) !u32 { const r = switch (i.dst) { .AddrReg => |v| v, else => 0 }; m.a[r] = try calculateEA(m, i.src); m.pc += i.size; return 4; }
fn executeRts(m: *cpu.M68k) !u32 { m.pc = try m.memory.read32(m.a[7]); m.a[7] += 4; return 16; }
fn executeRtr(m: *cpu.M68k) !u32 { const ccr = try m.memory.read16(m.a[7]); m.sr = (m.sr & 0xFF00) | (ccr & 0xFF); m.pc = try m.memory.read32(m.a[7] + 2); m.a[7] += 6; return 20; }
fn executeRte(m: *cpu.M68k) !u32 { 
    const sp = m.a[7]; 
    m.sr = try m.memory.read16(sp); 
    m.pc = try m.memory.read32(sp + 2); 
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
    return 20; 
}
fn executeTrap(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const v = switch (i.src) { .Immediate8 => |w| w, else => 0 }; const vn: u8 = 32 + (v & 0xF); try pushExceptionFrame(m, m.pc + 2, vn, 0); m.pc = try m.memory.read32(m.getExceptionVector(vn)); m.sr |= 0x2000; return 34;
}
fn executeBra(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const d = switch (i.src) { .Immediate8 => |v| @as(i32, @as(i8, @bitCast(v))), .Immediate16 => |v| @as(i32, @as(i16, @bitCast(v))), .Immediate32 => |v| @as(i32, @bitCast(v)), else => 0 }; m.pc = @bitCast(@as(i32, @bitCast(m.pc)) + 2 + d); return 10;
}
fn executeBcc(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const cond: u4 = @truncate((i.opcode >> 8) & 0xF); if (evaluateCondition(m, cond)) return try executeBra(m, i); m.pc += i.size; return 8;
}
fn executeBsr(m: *cpu.M68k, i: *const decoder.Instruction) !u32 { m.a[7] -= 4; try m.memory.write32(m.a[7], m.pc + i.size); return try executeBra(m, i); }
fn executeJsr(m: *cpu.M68k, i: *const decoder.Instruction) !u32 { const t = try calculateEA(m, i.dst); m.a[7] -= 4; try m.memory.write32(m.a[7], m.pc + i.size); m.pc = t; return 16; }
fn executeJmp(m: *cpu.M68k, i: *const decoder.Instruction) !u32 { m.pc = try calculateEA(m, i.dst); return 8; }
fn executeDbcc(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const cond: u4 = @truncate((i.opcode >> 8) & 0xF); const r = @as(u3, @truncate(i.opcode & 7));
    if (!evaluateCondition(m, cond)) { const v: i16 = @bitCast(@as(u16, @truncate(m.d[r]))); const nv = v -% 1; setRegisterValue(&m.d[r], @as(u32, @as(u16, @bitCast(nv))), .Word); if (nv != -1) return try executeBra(m, i); }
    m.pc += 4; return 12;
}
fn executeScc(m: *cpu.M68k, i: *const decoder.Instruction) !u32 { const cond: u4 = @truncate((i.opcode >> 8) & 0xF); const res: u8 = if (evaluateCondition(m, cond)) 0xFF else 0; try setOperandValue(m, i.dst, res, .Byte); m.pc += 2; return 4; }
fn executeShift(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const count = switch (i.src) { .Immediate8 => |v| @as(u32, v), .DataReg => |r| m.d[r] & 63, else => 1 };
    var val = try getOperandValue(m, i.dst, i.data_size); const mask: u32 = if (i.data_size == .Byte) 0xFF else if (i.data_size == .Word) 0xFFFF else 0xFFFFFFFF; const sign: u32 = if (i.data_size == .Byte) 0x80 else if (i.data_size == .Word) 0x8000 else 0x80000000;
    var c = m.getFlag(cpu.M68k.FLAG_C); var x = m.getFlag(cpu.M68k.FLAG_X);
    for (0..count) |_| {
        switch (i.mnemonic) { .LSR => { c = (val & 1) != 0; x = c; val >>= 1; }, .LSL => { c = (val & sign) != 0; x = c; val = (val << 1) & mask; }, .ASR => { c = (val & 1) != 0; x = c; const s = val & sign; val >>= 1; val |= s; }, .ASL => { c = (val & sign) != 0; x = c; val = (val << 1) & mask; }, .ROR => { c = (val & 1) != 0; val >>= 1; if (c) val |= sign; }, .ROL => { c = (val & sign) != 0; val = (val << 1) & mask; if (c) val |= 1; }, else => {} }
    }
    try setOperandValue(m, i.dst, val, i.data_size); m.setFlag(cpu.M68k.FLAG_C, c); m.setFlag(cpu.M68k.FLAG_X, x); m.setFlags(val, i.data_size); m.pc += 2; return 6 + (2 * count);
}
fn executeBtst(m: *cpu.M68k, i: *const decoder.Instruction) !u32 { const b = (try getOperandValue(m, i.src, .Byte)) & 31; const v = try getOperandValue(m, i.dst, i.data_size); m.setFlag(cpu.M68k.FLAG_Z, (v & (@as(u32, 1) << @truncate(b))) == 0); m.pc += i.size; return 4; }
fn executeBset(m: *cpu.M68k, i: *const decoder.Instruction) !u32 { const b = (try getOperandValue(m, i.src, .Byte)) & 31; const v = try getOperandValue(m, i.dst, i.data_size); m.setFlag(cpu.M68k.FLAG_Z, (v & (@as(u32, 1) << @truncate(b))) == 0); try setOperandValue(m, i.dst, v | (@as(u32, 1) << @truncate(b)), i.data_size); m.pc += i.size; return 8; }
fn executeBclr(m: *cpu.M68k, i: *const decoder.Instruction) !u32 { const b = (try getOperandValue(m, i.src, .Byte)) & 31; const v = try getOperandValue(m, i.dst, i.data_size); m.setFlag(cpu.M68k.FLAG_Z, (v & (@as(u32, 1) << @truncate(b))) == 0); try setOperandValue(m, i.dst, v & ~(@as(u32, 1) << @truncate(b)), i.data_size); m.pc += i.size; return 8; }
fn executeBchg(m: *cpu.M68k, i: *const decoder.Instruction) !u32 { const b = (try getOperandValue(m, i.src, .Byte)) & 31; const v = try getOperandValue(m, i.dst, i.data_size); m.setFlag(cpu.M68k.FLAG_Z, (v & (@as(u32, 1) << @truncate(b))) == 0); try setOperandValue(m, i.dst, v ^ (@as(u32, 1) << @truncate(b)), i.data_size); m.pc += i.size; return 8; }
fn executeMovec(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const reg = i.control_reg orelse 0;
    if (i.is_to_control) { const val = try getOperandValue(m, i.src, .Long); switch (reg) { 0 => m.sfc = @truncate(val & 7), 1 => m.dfc = @truncate(val & 7), 2 => m.cacr = val, 0x800 => m.usp = val, 0x801 => m.vbr = val, 0x802 => m.caar = val, else => return error.InvalidControlRegister } }
    else { const val: u32 = switch (reg) { 0 => m.sfc, 1 => m.dfc, 2 => m.cacr, 0x800 => m.usp, 0x801 => m.vbr, 0x802 => m.caar, else => return error.InvalidControlRegister }; try setOperandValue(m, i.src, val, .Long); }
    m.pc += 4; return 12;
}
fn executeLink(m: *cpu.M68k, i: *const decoder.Instruction) !u32 { const r = switch (i.dst) { .AddrReg => |v| v, else => 7 }; const d: i16 = @bitCast(switch (i.src) { .Immediate16 => |v| v, else => 0 }); m.a[7] -= 4; try m.memory.write32(m.a[7], m.a[r]); m.a[r] = m.a[7]; m.a[7] = @bitCast(@as(i32, @bitCast(m.a[7])) + @as(i32, d)); m.pc += 4; return 16; }
fn executeUnlk(m: *cpu.M68k, i: *const decoder.Instruction) !u32 { const r = switch (i.dst) { .AddrReg => |v| v, else => 7 }; m.a[7] = m.a[r]; m.a[r] = try m.memory.read32(m.a[7]); m.a[7] += 4; m.pc += 2; return 12; }
fn executePea(m: *cpu.M68k, i: *const decoder.Instruction) !u32 { const a = try calculateEA(m, i.src); m.a[7] -= 4; try m.memory.write32(m.a[7], a); m.pc += 2; return 12; }
fn executeMovem(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const mask = switch (i.src) { .Immediate16 => |v| v, else => 0 }; const dir = (i.opcode >> 10) & 1; var a = try calculateEA(m, i.dst);
    for (0..16) |idx| { if ((mask & (@as(u16, 1) << @truncate(idx))) != 0) { if (dir == 0) { const v = if (idx < 8) m.d[idx] else m.a[idx - 8]; if (i.data_size == .Word) { try m.memory.write16(a, @truncate(v)); a += 2; } else { try m.memory.write32(a, v); a += 4; } } else { if (i.data_size == .Word) { const v = try m.memory.read16(a); if (idx < 8) { m.d[idx] = @bitCast(@as(i32, @as(i16, @bitCast(v)))); } else { m.a[idx - 8] = @bitCast(@as(i32, @as(i16, @bitCast(v)))); } a += 2; } else { const v = try m.memory.read32(a); if (idx < 8) { m.d[idx] = v; } else { m.a[idx - 8] = v; } a += 4; } } } }
    m.pc += 4; return 8;
}
fn executeExg(m: *cpu.M68k, i: *const decoder.Instruction) !u32 { const rx = (i.opcode >> 9) & 7; const ry = i.opcode & 7; const mode = (i.opcode >> 3) & 0x1F; if (mode == 8) { const tmp = m.d[rx]; m.d[rx] = m.d[ry]; m.d[ry] = tmp; } else if (mode == 9) { const tmp = m.a[rx]; m.a[rx] = m.a[ry]; m.a[ry] = tmp; } else { const tmp = m.d[rx]; m.d[rx] = m.a[ry]; m.a[ry] = tmp; } m.pc += 2; return 6; }
fn executeChk(m: *cpu.M68k, i: *const decoder.Instruction) !u32 { const r = switch (i.dst) { .DataReg => |v| v, else => 0 }; const b = try getOperandValue(m, i.src, .Word); const v = m.d[r] & 0xFFFF; if (v > b or (v & 0x8000) != 0) { try pushExceptionFrame(m, m.pc + 2, 6, 0); m.pc = try m.memory.read32(m.getExceptionVector(6)); m.sr |= 0x2000; return 44; } m.pc += 2; return 10; }
fn executeTas(m: *cpu.M68k, i: *const decoder.Instruction) !u32 { const a = try calculateEA(m, i.dst); const v = try m.memory.read8(a); m.setFlags(v, .Byte); try m.memory.write8(a, v | 0x80); m.pc += 2; return 14; }
fn executeAbcd(m: *cpu.M68k, i: *const decoder.Instruction) !u32 { const s = try getOperandValue(m, i.src, .Byte); const d = try getOperandValue(m, i.dst, .Byte); const res = addBcd(@truncate(d), @truncate(s), m.getFlag(cpu.M68k.FLAG_X)); try setOperandValue(m, i.dst, res.result, .Byte); m.setFlag(cpu.M68k.FLAG_X, res.carry); m.setFlag(cpu.M68k.FLAG_C, res.carry); if (res.result != 0) { m.setFlag(cpu.M68k.FLAG_Z, false); } m.pc += 2; return 6; }
fn executeSbcd(m: *cpu.M68k, i: *const decoder.Instruction) !u32 { const s = try getOperandValue(m, i.src, .Byte); const d = try getOperandValue(m, i.dst, .Byte); const res = subBcd(@truncate(d), @truncate(s), m.getFlag(cpu.M68k.FLAG_X)); try setOperandValue(m, i.dst, res.result, .Byte); m.setFlag(cpu.M68k.FLAG_X, res.carry); m.setFlag(cpu.M68k.FLAG_C, res.carry); if (res.result != 0) { m.setFlag(cpu.M68k.FLAG_Z, false); } m.pc += 2; return 6; }
fn executeNbcd(m: *cpu.M68k, i: *const decoder.Instruction) !u32 { const v = try getOperandValue(m, i.dst, .Byte); const res = subBcd(0, @truncate(v), m.getFlag(cpu.M68k.FLAG_X)); try setOperandValue(m, i.dst, res.result, .Byte); m.setFlag(cpu.M68k.FLAG_X, res.carry); m.setFlag(cpu.M68k.FLAG_C, res.carry); if (res.result != 0) { m.setFlag(cpu.M68k.FLAG_Z, false); } m.pc += 2; return 6; }
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
    m.setFlag(cpu.M68k.FLAG_V, false); m.setFlag(cpu.M68k.FLAG_C, false); m.pc += 4; return 6;
}
fn executeBfset(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const ext = switch (i.src) { .Immediate16 => |v| v, else => 0 };
    const offset = if ((ext & 0x800) != 0) m.d[@as(u3, @truncate((ext >> 6) & 7))] & 31 else @as(u32, (ext >> 6) & 31);
    const width = if ((ext & 0x20) != 0) ((m.d[@as(u3, @truncate(ext & 7))] - 1) & 31) + 1 else (((ext & 31) - 1) & 31) + 1;
    var val = try getOperandValue(m, i.dst, .Long);
    var mask: u32 = 0; for (0..width) |j| { mask |= @as(u32, 1) << @truncate((offset + j) & 31); }
    const field = val & mask; m.setFlag(cpu.M68k.FLAG_Z, field == 0); m.setFlag(cpu.M68k.FLAG_N, (val & (@as(u32, 1) << @truncate((offset + width - 1) & 31))) != 0);
    val |= mask; try setOperandValue(m, i.dst, val, .Long); m.pc += 4; return 10;
}
fn executeBfclr(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const ext = switch (i.src) { .Immediate16 => |v| v, else => 0 };
    const offset = if ((ext & 0x800) != 0) m.d[@as(u3, @truncate((ext >> 6) & 7))] & 31 else @as(u32, (ext >> 6) & 31);
    const width = if ((ext & 0x20) != 0) ((m.d[@as(u3, @truncate(ext & 7))] - 1) & 31) + 1 else (((ext & 31) - 1) & 31) + 1;
    var val = try getOperandValue(m, i.dst, .Long);
    var mask: u32 = 0; for (0..width) |j| { mask |= @as(u32, 1) << @truncate((offset + j) & 31); }
    const field = val & mask; m.setFlag(cpu.M68k.FLAG_Z, field == 0); m.setFlag(cpu.M68k.FLAG_N, (val & (@as(u32, 1) << @truncate((offset + width - 1) & 31))) != 0);
    val &= ~mask; try setOperandValue(m, i.dst, val, .Long); m.pc += 4; return 10;
}
fn executeBfchg(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const ext = switch (i.src) { .Immediate16 => |v| v, else => 0 };
    const offset = if ((ext & 0x800) != 0) m.d[@as(u3, @truncate((ext >> 6) & 7))] & 31 else @as(u32, (ext >> 6) & 31);
    const width = if ((ext & 0x20) != 0) ((m.d[@as(u3, @truncate(ext & 7))] - 1) & 31) + 1 else (((ext & 31) - 1) & 31) + 1;
    var val = try getOperandValue(m, i.dst, .Long);
    var mask: u32 = 0; for (0..width) |j| { mask |= @as(u32, 1) << @truncate((offset + j) & 31); }
    const field = val & mask; m.setFlag(cpu.M68k.FLAG_Z, field == 0); m.setFlag(cpu.M68k.FLAG_N, (val & (@as(u32, 1) << @truncate((offset + width - 1) & 31))) != 0);
    val ^= mask; try setOperandValue(m, i.dst, val, .Long); m.pc += 4; return 10;
}
fn executeBfexts(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const ext = switch (i.src) { .Immediate16 => |v| v, else => 0 }; const dn = @as(u3, @truncate((ext >> 12) & 7));
    const offset = if ((ext & 0x800) != 0) m.d[@as(u3, @truncate((ext >> 6) & 7))] & 31 else @as(u32, (ext >> 6) & 31);
    const width = if ((ext & 0x20) != 0) ((m.d[@as(u3, @truncate(ext & 7))] - 1) & 31) + 1 else (((ext & 31) - 1) & 31) + 1;
    const val = try getOperandValue(m, i.dst, .Long); var field: u32 = 0;
    for (0..width) |j| { if ((val & (@as(u32, 1) << @truncate((offset + j) & 31))) != 0) { field |= @as(u32, 1) << @truncate(j); } }
    if ((field & (@as(u32, 1) << @truncate(width - 1))) != 0) { field |= ~(@as(u32, 0) >> @truncate(32 - width)); }
    m.d[dn] = field; m.setFlag(cpu.M68k.FLAG_Z, field == 0); m.setFlag(cpu.M68k.FLAG_N, (field & 0x80000000) != 0); m.pc += 4; return 8;
}
fn executeBfextu(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const ext = switch (i.src) { .Immediate16 => |v| v, else => 0 }; const dn = @as(u3, @truncate((ext >> 12) & 7));
    const offset = if ((ext & 0x800) != 0) m.d[@as(u3, @truncate((ext >> 6) & 7))] & 31 else @as(u32, (ext >> 6) & 31);
    const width = if ((ext & 0x20) != 0) ((m.d[@as(u3, @truncate(ext & 7))] - 1) & 31) + 1 else (((ext & 31) - 1) & 31) + 1;
    const val = try getOperandValue(m, i.dst, .Long); var field: u32 = 0;
    for (0..width) |j| { if ((val & (@as(u32, 1) << @truncate((offset + j) & 31))) != 0) { field |= @as(u32, 1) << @truncate(j); } }
    m.d[dn] = field; m.setFlag(cpu.M68k.FLAG_Z, field == 0); m.setFlag(cpu.M68k.FLAG_N, false); m.pc += 4; return 8;
}
fn executeBfins(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const ext = switch (i.src) { .Immediate16 => |v| v, else => 0 }; const dn = @as(u3, @truncate((ext >> 12) & 7));
    const offset = if ((ext & 0x800) != 0) m.d[@as(u3, @truncate((ext >> 6) & 7))] & 31 else @as(u32, (ext >> 6) & 31);
    const width = if ((ext & 0x20) != 0) ((m.d[@as(u3, @truncate(ext & 7))] - 1) & 31) + 1 else (((ext & 31) - 1) & 31) + 1;
    var val = try getOperandValue(m, i.dst, .Long); var mask: u32 = 0;
    for (0..width) |j| { mask |= @as(u32, 1) << @truncate((offset + j) & 31); }
    val &= ~mask; for (0..width) |j| { if ((m.d[dn] & (@as(u32, 1) << @truncate(j))) != 0) { val |= @as(u32, 1) << @truncate((offset + j) & 31); } }
    m.setFlag(cpu.M68k.FLAG_Z, (val & mask) == 0); m.setFlag(cpu.M68k.FLAG_N, (val & (@as(u32, 1) << @truncate((offset + width - 1) & 31))) != 0);
    try setOperandValue(m, i.dst, val, .Long); m.pc += 4; return 8;
}
fn executeBfffo(m: *cpu.M68k, i: *const decoder.Instruction) !u32 {
    const ext = switch (i.src) { .Immediate16 => |v| v, else => 0 }; const dn = @as(u3, @truncate((ext >> 12) & 7));
    const offset = if ((ext & 0x800) != 0) m.d[@as(u3, @truncate((ext >> 6) & 7))] & 31 else @as(u32, (ext >> 6) & 31);
    const width = if ((ext & 0x20) != 0) ((m.d[@as(u3, @truncate(ext & 7))] - 1) & 31) + 1 else (((ext & 31) - 1) & 31) + 1;
    const val = try getOperandValue(m, i.dst, .Long); var ffo: u32 = offset;
    for (0..width) |j| { if ((val & (@as(u32, 1) << @truncate((offset + j) & 31))) != 0) { ffo = offset + @as(u32, @truncate(j)); break; } } else { ffo = offset + width; }
    m.d[dn] = ffo; m.setFlag(cpu.M68k.FLAG_Z, ffo == offset + width); m.setFlag(cpu.M68k.FLAG_N, false); m.pc += 4; return 10;
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
fn executeRtd(m: *cpu.M68k, _: *const decoder.Instruction) !u32 { const disp: i16 = @bitCast(try m.memory.read16(m.pc + 2)); m.pc = try m.memory.read32(m.a[7]); m.a[7] = @bitCast(@as(i32, @bitCast(m.a[7])) + 4 + @as(i32, disp)); return 10; }
fn executeBkpt(_: *cpu.M68k, _: *const decoder.Instruction) !u32 { return 10; }
fn executeTrapcc(m: *cpu.M68k, i: *const decoder.Instruction) !u32 { const cond: u4 = @truncate((i.opcode >> 8) & 0xF); if (evaluateCondition(m, cond)) { try pushExceptionFrame(m, m.pc + 2, 7, 0); m.pc = try m.memory.read32(m.getExceptionVector(7)); m.sr |= 0x2000; return 33; } m.pc += i.size; return 3; }
fn executeChk2(_: *cpu.M68k, _: *const decoder.Instruction) !u32 { return 15; }
fn executeCmp2(_: *cpu.M68k, _: *const decoder.Instruction) !u32 { return 12; }
fn executePack(_: *cpu.M68k, _: *const decoder.Instruction) !u32 { return 5; }
fn executeUnpk(_: *cpu.M68k, _: *const decoder.Instruction) !u32 { return 6; }
fn executeMulsL(_: *cpu.M68k, _: *const decoder.Instruction) !u32 { return 30; }
fn executeMuluL(_: *cpu.M68k, _: *const decoder.Instruction) !u32 { return 30; }
fn executeDivsL(_: *cpu.M68k, _: *const decoder.Instruction) !u32 { return 70; }
fn executeDivuL(_: *cpu.M68k, _: *const decoder.Instruction) !u32 { return 70; }

fn getRegisterValue(v: u32, s: decoder.DataSize) u32 { return switch (s) { .Byte => v & 0xFF, .Word => v & 0xFFFF, .Long => v }; }
fn setRegisterValue(r: *u32, v: u32, s: decoder.DataSize) void { switch (s) { .Byte => r.* = (r.* & 0xFFFFFF00) | (v & 0xFF), .Word => r.* = (r.* & 0xFFFF0000) | (v & 0xFFFF), .Long => r.* = v } }
fn getOperandValue(m: *cpu.M68k, op: decoder.Operand, s: decoder.DataSize) !u32 {
    return switch (op) {
        .DataReg => |r| getRegisterValue(m.d[r], s), .AddrReg => |r| m.a[r], .Immediate8 => |v| v, .Immediate16 => |v| v, .Immediate32 => |v| v,
        .AddrIndirect => |r| if (s == .Byte) try m.memory.read8(m.a[r]) else if (s == .Word) try m.memory.read16(m.a[r]) else try m.memory.read32(m.a[r]),
        .AddrPostInc => |r| { const a = m.a[r]; const inc: u32 = if (s == .Byte) (if (r == 7) 2 else 1) else if (s == .Word) 2 else 4; m.a[r] += inc; return if (s == .Byte) try m.memory.read8(a) else if (s == .Word) try m.memory.read16(a) else try m.memory.read32(a); },
        .AddrPreDec => |r| { const inc: u32 = if (s == .Byte) (if (r == 7) 2 else 1) else if (s == .Word) 2 else 4; m.a[r] -= inc; return if (s == .Byte) try m.memory.read8(m.a[r]) else if (s == .Word) try m.memory.read16(m.a[r]) else try m.memory.read32(m.a[r]); },
        .Address => |a| if (s == .Byte) try m.memory.read8(a) else if (s == .Word) try m.memory.read16(a) else try m.memory.read32(a),
        .AddrDisplace => |i| { const a = @as(u32, @bitCast(@as(i32, @bitCast(m.a[i.reg])) + @as(i32, i.displacement))); return if (s == .Byte) try m.memory.read8(a) else if (s == .Word) try m.memory.read16(a) else try m.memory.read32(a); },
        else => 0,
    };
}
fn setOperandValue(m: *cpu.M68k, op: decoder.Operand, v: u32, s: decoder.DataSize) !void {
    switch (op) { .DataReg => |r| setRegisterValue(&m.d[r], v, s), .AddrReg => |r| m.a[r] = v, .AddrIndirect => |r| if (s == .Byte) try m.memory.write8(m.a[r], @truncate(v)) else if (s == .Word) try m.memory.write16(m.a[r], @truncate(v)) else try m.memory.write32(m.a[r], v), .AddrDisplace => |i| { const a = @as(u32, @bitCast(@as(i32, @bitCast(m.a[i.reg])) + @as(i32, i.displacement))); if (s == .Byte) try m.memory.write8(a, @truncate(v)) else if (s == .Word) try m.memory.write16(a, @truncate(v)) else try m.memory.write32(a, v); }, else => {} }
}
fn calculateEA(m: *cpu.M68k, op: decoder.Operand) !u32 { return switch (op) { .AddrIndirect => |r| m.a[r], .Address => |a| a, .AddrDisplace => |i| @as(u32, @bitCast(@as(i32, @bitCast(m.a[i.reg])) + @as(i32, i.displacement))), else => 0 }; }
fn setArithmeticFlags(m: *cpu.M68k, d: u32, s: u32, r: u32, sz: decoder.DataSize, sub: bool) void {
    const mask: u32 = if (sz == .Byte) 0xFF else if (sz == .Word) 0xFFFF else 0xFFFFFFFF; const sign: u32 = if (sz == .Byte) 0x80 else if (sz == .Word) 0x8000 else 0x80000000;
    const mr = r & mask; m.setFlag(cpu.M68k.FLAG_Z, mr == 0); m.setFlag(cpu.M68k.FLAG_N, (mr & sign) != 0);
    if (sub) { m.setFlag(cpu.M68k.FLAG_C, s > d); m.setFlag(cpu.M68k.FLAG_X, s > d); } else { m.setFlag(cpu.M68k.FLAG_C, mr < d); m.setFlag(cpu.M68k.FLAG_X, mr < d); }
}
fn evaluateCondition(m: *cpu.M68k, c: u4) bool {
    const cv = m.getFlag(cpu.M68k.FLAG_C); const vv = m.getFlag(cpu.M68k.FLAG_V); const zv = m.getFlag(cpu.M68k.FLAG_Z); const nv = m.getFlag(cpu.M68k.FLAG_N);
    return switch (c) { 0 => true, 1 => false, 2 => !cv and !zv, 3 => cv or zv, 4 => !cv, 5 => cv, 6 => !zv, 7 => zv, 8 => !vv, 9 => vv, 10 => !nv, 11 => nv, 12 => (nv == vv), 13 => (nv != vv), 14 => (nv == vv) and !zv, 15 => zv or (nv != vv) };
}
fn pushExceptionFrame(m: *cpu.M68k, pc: u32, vec: u8, fmt: u4) !void {
    m.a[7] -= 8; try m.memory.write16(m.a[7], m.sr); try m.memory.write32(m.a[7] + 2, pc); try m.memory.write16(m.a[7] + 6, (@as(u16, fmt) << 12) | (@as(u16, vec) * 4));
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
