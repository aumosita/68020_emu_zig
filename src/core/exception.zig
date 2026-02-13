const std = @import("std");
const cpu = @import("cpu.zig");
const memory = @import("memory.zig");
const registers = @import("registers.zig");

pub const FaultCycleSubtype = enum {
    instruction_fetch,
    decode_extension_fetch,
    execute_data_access,
};

pub fn faultCycles(subtype: FaultCycleSubtype) u32 {
    return switch (subtype) {
        .instruction_fetch => 50,
        .decode_extension_fetch => 52,
        .execute_data_access => 54,
    };
}

pub fn getExceptionVector(self: *const cpu.M68k, vector_number: u8) u32 {
    return self.vbr + (@as(u32, vector_number) * 4);
}

pub fn buildFormatAAccessWord(access: memory.BusAccess) u16 {
    return (@as(u16, access.function_code) << 13) |
        (if (access.space == .Program) @as(u16, 1) << 12 else 0) |
        (if (access.is_write) @as(u16, 1) << 11 else 0);
}

pub fn readFaultInstructionWord(self: *const cpu.M68k, return_pc: u32) u16 {
    return self.memory.read16Bus(return_pc, supervisorData()) catch 0;
}

// Supervisor data function code for exception stack access
fn supervisorData() memory.BusAccess {
    return .{
        .function_code = 0b101, // Supervisor data
        .space = .Data,
        .is_write = false,
    };
}

fn supervisorWrite() memory.BusAccess {
    return .{
        .function_code = 0b101, // Supervisor data
        .space = .Data,
        .is_write = true,
    };
}

pub fn enterFaultFrameA(self: *cpu.M68k, vector: u8, return_pc: u32, fault_addr: u32, access: memory.BusAccess, retry_count: u8) !void {
    const old_sr = self.sr;
    var sr_new = self.sr | registers.FLAG_S;
    sr_new &= ~registers.FLAG_M;
    registers.setSR(self, sr_new);

    const write_access = supervisorWrite();

    self.a[7] -= 24;
    try self.memory.write16Bus(self.a[7], old_sr, write_access);
    try self.memory.write32Bus(self.a[7] + 2, return_pc, write_access);
    try self.memory.write16Bus(self.a[7] + 6, (@as(u16, 0xA) << 12) | (@as(u16, vector) * 4), write_access);
    try self.memory.write32Bus(self.a[7] + 8, fault_addr, write_access);
    try self.memory.write16Bus(self.a[7] + 12, buildFormatAAccessWord(access), write_access);
    try self.memory.write16Bus(self.a[7] + 14, readFaultInstructionWord(self, return_pc), write_access);
    try self.memory.write16Bus(self.a[7] + 16, retry_count, write_access);
    try self.memory.write16Bus(self.a[7] + 18, 0, write_access);
    try self.memory.write16Bus(self.a[7] + 20, 0, write_access);
    try self.memory.write16Bus(self.a[7] + 22, 0, write_access);
    self.pc = self.memory.read32Bus(getExceptionVector(self, vector), supervisorData()) catch 0;
}

pub fn enterBusErrorFrameA(self: *cpu.M68k, return_pc: u32, fault_addr: u32, access: memory.BusAccess) !void {
    try enterFaultFrameA(self, 2, return_pc, fault_addr, access, self.bus_retry_count);
}

pub fn enterAddressErrorFrameA(self: *cpu.M68k, return_pc: u32, fault_addr: u32, access: memory.BusAccess) !void {
    try enterFaultFrameA(self, 3, return_pc, fault_addr, access, 0);
}

pub fn pushExceptionFrame(self: *cpu.M68k, status_word: u16, return_pc: u32, vector: u8, format: u4) !void {
    const write_access = supervisorWrite();
    self.a[7] -= 8;
    try self.memory.write16Bus(self.a[7], status_word, write_access);
    try self.memory.write32Bus(self.a[7] + 2, return_pc, write_access);
    try self.memory.write16Bus(self.a[7] + 6, (@as(u16, format) << 12) | (@as(u16, vector) * 4), write_access);
}

pub fn enterException(self: *cpu.M68k, vector: u8, return_pc: u32, format: u4, new_ipl: ?u3) !void {
    const old_sr = self.sr;
    var sr_new = self.sr | registers.FLAG_S;
    sr_new &= ~registers.FLAG_M;
    if (new_ipl) |level| {
        sr_new = (sr_new & 0xF8FF) | (@as(u16, level) << 8);
    }
    registers.setSR(self, sr_new);
    try pushExceptionFrame(self, old_sr, return_pc, vector, format);
    self.pc = self.memory.read32Bus(getExceptionVector(self, vector), supervisorData()) catch 0;
}
