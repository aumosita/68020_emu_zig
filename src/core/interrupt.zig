const std = @import("std");
const cpu = @import("cpu.zig");
const exception = @import("exception.zig");

pub fn setInterruptLevel(self: *cpu.M68k, level: u3) void {
    setInterruptRequest(self, level, null);
}

pub fn setInterruptVector(self: *cpu.M68k, level: u3, vector: u8) void {
    setInterruptRequest(self, level, vector);
}

pub fn setSpuriousInterrupt(self: *cpu.M68k, level: u3) void {
    setInterruptRequest(self, level, 24);
}

pub fn handlePendingInterrupt(self: *cpu.M68k) !bool {
    if (self.pending_irq_level == 0) return false;
    const current_mask: u3 = @truncate((self.sr >> 8) & 0x7);
    if (self.pending_irq_level != 7 and self.pending_irq_level <= current_mask) return false;

    const level = self.pending_irq_level;
    const vector_override = self.pending_irq_vector;
    self.pending_irq_level = 0;
    self.pending_irq_vector = null;
    const vector: u8 = vector_override orelse (24 + @as(u8, level));
    try exception.enterException(self, vector, self.pc, 0, level);
    self.stopped = false;
    return true;
}

pub fn setInterruptRequest(self: *cpu.M68k, level: u3, vector: ?u8) void {
    if (level == 0) {
        self.pending_irq_level = 0;
        self.pending_irq_vector = null;
        return;
    }

    if (level > self.pending_irq_level) {
        self.pending_irq_level = level;
        self.pending_irq_vector = vector;
        return;
    }

    if (level == self.pending_irq_level and vector != null and self.pending_irq_vector == null) {
        self.pending_irq_vector = vector;
    }
}
