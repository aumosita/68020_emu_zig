const std = @import("std");
const cpu = @import("cpu.zig");
const decoder = @import("decoder.zig");

pub const FLAG_C: u16 = 1 << 0;
pub const FLAG_V: u16 = 1 << 1;
pub const FLAG_Z: u16 = 1 << 2;
pub const FLAG_N: u16 = 1 << 3;
pub const FLAG_X: u16 = 1 << 4;
pub const FLAG_M: u16 = 1 << 12;
pub const FLAG_S: u16 = 1 << 13;

pub const StackKind = enum { User, Interrupt, Master };

pub inline fn getFlag(self: *const cpu.M68k, flag: u16) bool {
    return (self.sr & flag) != 0;
}

pub fn setFlag(self: *cpu.M68k, flag: u16, value: bool) void {
    var sr_new = self.sr;
    if (value) {
        sr_new |= flag;
    } else {
        sr_new &= ~flag;
    }

    if (flag == FLAG_S or flag == FLAG_M) {
        setSR(self, sr_new);
        return;
    }
    self.sr = sr_new;
}

pub fn setFlags(self: *cpu.M68k, result: u32, size: decoder.DataSize) void {
    const mask: u32 = switch (size) {
        .Byte => 0xFF,
        .Word => 0xFFFF,
        .Long => 0xFFFFFFFF,
    };
    const masked = result & mask;
    setFlag(self, FLAG_Z, masked == 0);
    const sign_bit: u32 = switch (size) {
        .Byte => 0x80,
        .Word => 0x8000,
        .Long => 0x80000000,
    };
    setFlag(self, FLAG_N, (masked & sign_bit) != 0);
    setFlag(self, FLAG_V, false);
    setFlag(self, FLAG_C, false);
}

pub fn setSR(self: *cpu.M68k, new_sr: u16) void {
    const prev_sp = self.a[7];
    saveActiveStackPointer(self);
    self.sr = new_sr;
    loadActiveStackPointer(self, prev_sp);
}

pub fn activeStackKind(sr: u16) StackKind {
    const supervisor = (sr & FLAG_S) != 0;
    if (!supervisor) return .User;
    if ((sr & FLAG_M) != 0) return .Master;
    return .Interrupt;
}

pub fn saveActiveStackPointer(self: *cpu.M68k) void {
    switch (activeStackKind(self.sr)) {
        .User => self.usp = self.a[7],
        .Interrupt => self.isp = self.a[7],
        .Master => self.msp = self.a[7],
    }
}

pub fn loadActiveStackPointer(self: *cpu.M68k, fallback_sp: u32) void {
    self.a[7] = switch (activeStackKind(self.sr)) {
        .User => blk: {
            if (self.usp == 0) self.usp = fallback_sp;
            break :blk self.usp;
        },
        .Interrupt => blk: {
            if (self.isp == 0) self.isp = fallback_sp;
            break :blk self.isp;
        },
        .Master => blk: {
            if (self.msp == 0) self.msp = fallback_sp;
            break :blk self.msp;
        },
    };
}

pub fn getStackPointer(self: *const cpu.M68k, kind: StackKind) u32 {
    const active = activeStackKind(self.sr);
    if (active == kind) return self.a[7];
    return switch (kind) {
        .User => self.usp,
        .Interrupt => self.isp,
        .Master => self.msp,
    };
}

pub fn setStackPointer(self: *cpu.M68k, kind: StackKind, value: u32) void {
    switch (kind) {
        .User => self.usp = value,
        .Interrupt => self.isp = value,
        .Master => self.msp = value,
    }
    if (activeStackKind(self.sr) == kind) {
        self.a[7] = value;
    }
}
