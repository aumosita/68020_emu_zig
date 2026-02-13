const std = @import("std");

/// Macintosh RBV (RAM-Based Video) / V8 / Eagle / Combo chip
/// Emulates VIA2 functionality for Macintosh LC, IIci, IIsi.
pub const Rbv = struct {
    // Interrupt Registers (RBV style)
    ifr: u8 = 0, // Status/Flags
    ier: u8 = 0, // Enable/Mask

    // Video configuration (simplified)
    depth: u8 = 0,
    mon_type: u8 = 6, // 12" RGB

    // Interrupt source bits for RBV
    pub const BIT_SCSI: u8 = 0x01;
    pub const BIT_SLOT_E: u8 = 0x02;
    pub const BIT_SLOT_F: u8 = 0x04;
    pub const BIT_VBL: u8 = 0x08;
    pub const BIT_ASC: u8 = 0x10;
    pub const BIT_MON: u8 = 0x20;
    pub const BIT_ANY: u8 = 0x80;

    pub fn init() Rbv {
        return .{};
    }

    pub fn read(self: *Rbv, addr: u4) u8 {
        return switch (addr) {
            0x00 => self.ifr | (if ((self.ifr & self.ier & 0x7F) != 0) @as(u8, 0x80) else 0),
            0x01 => self.ier,
            0x02 => self.mon_type, // Usually read here or specific offset
            else => 0,
        };
    }

    pub fn write(self: *Rbv, addr: u4, value: u8) void {
        switch (addr) {
            0x00 => {
                // In RBV, writing to status often clears flags (Write 0 to bits?)
                // Or some versions have specific clear behavior.
                // We'll implement "Write 0 to clear" or "Write 1 to clear" depending on common Mac behavior.
                // Standard VIA2 is Write 1 to IFR to clear.
                self.ifr &= ~value;
            },
            0x01 => {
                // In RBV, bit 7 determines if we set or clear enabled bits
                if ((value & 0x80) != 0) {
                    self.ier |= (value & 0x7F);
                } else {
                    self.ier &= ~(value & 0x7F);
                }
            },
            0x02 => {
                // Video depth / palette control usually starts around here
                self.depth = value;
            },
            else => {},
        }
    }

    pub fn getInterruptOutput(self: *const Rbv) bool {
        return (self.ifr & self.ier & 0x7F) != 0;
    }

    pub fn setInterrupt(self: *Rbv, bit: u8) void {
        self.ifr |= (bit & 0x7F);
    }

    pub fn getIrq(self: *const Rbv) bool {
        return (self.ifr & self.ier & 0x7F) != 0;
    }
};
