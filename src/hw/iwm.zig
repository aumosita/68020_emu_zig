const std = @import("std");

/// Apple IWM/SWIM (Integrated Woz Machine / Super Woz Integrated Machine)
/// Floppy disk controller — Stub implementation
///
/// Mac LC ROM probes IWM during init to detect floppy drives.
/// Without this stub, ROM hits Bus Error on IWM address access.
///
/// Mac LC IWM Address Map:
///   24-bit: 0xE00000–0xEFFFFF
///   32-bit: 0x50016000–0x50017FFF
///
/// Register layout (active-low, even byte addresses):
///   Each register is at addr[4:1] (bits 4 down to 1)
///   Minimal stub: return 0xFF ("no drive connected") for all reads.
pub const Iwm = struct {
    // IWM mode register (written via register protocol)
    mode: u8 = 0,

    // Status flags
    motor_on: bool = false,
    q6: bool = false,
    q7: bool = false,

    pub fn init() Iwm {
        return .{};
    }

    /// Read from IWM register.
    /// Returns 0xFF = "no drive present / all lines high" for all registers.
    /// This satisfies ROM's drive detection probe.
    pub fn read(self: *Iwm, addr: u32) u8 {
        // IWM register select is based on address bits
        // Even addresses are active, register encoded in bits [4:1]
        const reg: u4 = @truncate((addr >> 1) & 0xF);
        _ = self;

        return switch (reg) {
            // Status registers — return "no drive"
            // Bit 7 = 1 means "no drive connected" for most status reads
            else => 0xFF,
        };
    }

    /// Write to IWM register.
    /// Stub: silently ignore all writes.
    pub fn write(self: *Iwm, addr: u32, value: u8) void {
        const reg: u4 = @truncate((addr >> 1) & 0xF);
        _ = value;
        _ = self;

        switch (reg) {
            // All writes silently ignored in stub mode
            else => {},
        }
    }

    /// Reset IWM to initial state
    pub fn reset(self: *Iwm) void {
        self.mode = 0;
        self.motor_on = false;
        self.q6 = false;
        self.q7 = false;
    }
};
