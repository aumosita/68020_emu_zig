const std = @import("std");

/// Zilog 8530 SCC (Serial Communications Controller) — Stub
/// Mac LC ROM polls SCC during init. Without this, Bus Error on first SCC access.
///
/// Mac LC SCC Address Map:
///   24-bit: 0xC00000–0xCFFFFF
///   32-bit: 0x50004000–0x50005FFF
///
/// Register layout (from CPU side, active-low addressing):
///   Even addresses = Channel B, Odd addresses = Channel A
///   Bit 1: 0 = Command/Status (WR/RR), 1 = Data
///
/// Minimal stub: returns "Tx buffer empty, no pending RX" to satisfy ROM polling.
pub const Scc = struct {
    // Per-channel state
    channels: [2]Channel = .{ Channel.init(), Channel.init() },

    // Master Interrupt Control (WR9)
    wr9_mic: u8 = 0xC0, // Hardware reset state

    // Interrupt pending
    rr3_ip: u8 = 0, // Interrupt Pending (read from Channel A only)

    pub const Channel = struct {
        // Write Registers
        wr0: u8 = 0, // Command register
        wr1: u8 = 0, // Tx/Rx interrupt enable
        wr3: u8 = 0, // Rx params
        wr4: u8 = 0x04, // Tx/Rx misc (1 stop bit default)
        wr5: u8 = 0, // Tx params
        wr10: u8 = 0, // Misc Tx/Rx
        wr11: u8 = 0, // Clock mode
        wr12: u8 = 0, // BRG low
        wr13: u8 = 0, // BRG high
        wr14: u8 = 0, // BRG control
        wr15: u8 = 0, // External/Status IE

        // Read register pointer (set by WR0 bits 2:0)
        rr_pointer: u3 = 0,

        pub fn init() Channel {
            return .{};
        }

        /// Read Register (RR)
        pub fn readRR(_: *const Channel, reg: u3) u8 {
            return switch (reg) {
                // RR0: Tx/Rx Buffer Status
                // Bit 0: Rx Char Available (0 = no)
                // Bit 2: Tx Buffer Empty (1 = yes, always ready)
                // Bit 5: CTS (1 = clear to send)
                0 => 0x24, // Tx empty + CTS

                // RR1: Special Receive Condition
                // Bit 0: All Sent (1 = yes)
                1 => 0x01,

                // RR2: Interrupt vector (Channel B modified)
                2 => 0x00,

                // RR3: Interrupt Pending (Channel A only)
                3 => 0x00,

                // RR10: Loop/Clock status
                // RR12/13: BRG readback
                else => 0x00,
            };
        }

        /// Write Register (WR)
        pub fn writeWR(self: *Channel, reg: u3, value: u8) void {
            switch (reg) {
                0 => {
                    // WR0: Command + RR pointer
                    self.rr_pointer = @truncate(value & 0x07);
                    // Command bits (5:3)
                    const cmd: u3 = @truncate((value >> 3) & 0x07);
                    switch (cmd) {
                        0 => {}, // Null command
                        1 => {}, // Point High (select RR8-RR15)
                        2 => {}, // Reset Ext/Status Interrupts
                        3 => {}, // Send Abort
                        4 => {}, // Enable Int on next Rx char
                        5 => {}, // Reset Tx Int Pending
                        6 => {}, // Error Reset
                        7 => {}, // Reset Highest IUS
                    }
                },
                1 => self.wr1 = value,
                3 => self.wr3 = value,
                4 => self.wr4 = value,
                5 => self.wr5 = value,
                else => {},
            }
        }
    };

    pub fn init() Scc {
        return .{};
    }

    /// Read from SCC register.
    /// addr bit 0: 0=Channel B, 1=Channel A
    /// addr bit 1: 0=Control, 1=Data
    pub fn read(self: *Scc, addr: u32) u8 {
        const channel_idx: u1 = if ((addr & 1) != 0) 0 else 1; // A=0, B=1
        const is_data = (addr & 2) != 0;
        const ch = &self.channels[channel_idx];

        if (is_data) {
            // Data register read — no data available
            return 0x00;
        } else {
            // Control/Status register read
            const reg = ch.rr_pointer;
            ch.rr_pointer = 0; // Reset pointer after read
            return ch.readRR(reg);
        }
    }

    /// Write to SCC register.
    pub fn write(self: *Scc, addr: u32, value: u8) void {
        const channel_idx: u1 = if ((addr & 1) != 0) 0 else 1;
        const is_data = (addr & 2) != 0;
        var ch = &self.channels[channel_idx];

        if (is_data) {
            // Data register write — discard (no serial output)
            return;
        } else {
            // Control register write
            if (ch.rr_pointer == 0) {
                // First write goes to WR0 (sets pointer for next write)
                ch.writeWR(0, value);
            } else {
                // Subsequent write goes to WR[pointer]
                const reg = ch.rr_pointer;
                ch.rr_pointer = 0;
                ch.writeWR(reg, value);
            }
        }
    }

    /// Reset both channels
    pub fn reset(self: *Scc) void {
        self.channels = .{ Channel.init(), Channel.init() };
        self.wr9_mic = 0xC0;
        self.rr3_ip = 0;
    }

    /// Interrupt output (active when any unmasked interrupt pending)
    pub fn getInterruptOutput(self: *const Scc) bool {
        return self.rr3_ip != 0;
    }
};
