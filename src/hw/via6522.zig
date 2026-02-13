const std = @import("std");

pub const Via6522 = struct {
    // Registers
    port_b: u8 = 0,     // 0x00
    port_a: u8 = 0,     // 0x01 (handshake)
    ddr_b: u8 = 0,      // 0x02
    ddr_a: u8 = 0,      // 0x03
    t1c_l: u8 = 0,      // 0x04
    t1c_h: u8 = 0,      // 0x05
    t1l_l: u8 = 0,      // 0x06
    t1l_h: u8 = 0,      // 0x07
    t2c_l: u8 = 0,      // 0x08
    t2c_h: u8 = 0,      // 0x09
    sr: u8 = 0,         // 0x0A
    acr: u8 = 0,        // 0x0B
    pcr: u8 = 0,        // 0x0C
    ifr: u8 = 0,        // 0x0D
    ier: u8 = 0,        // 0x0E
    port_a_nh: u8 = 0,  // 0x0F (no handshake)

    // Internal state
    t1_counter: u16 = 0,
    t1_latches: u16 = 0,
    t1_active: bool = false,
    
    t2_counter: u16 = 0,
    t2_active: bool = false,

    irq_pin: bool = false,

    pub fn init() Via6522 {
        return .{};
    }

    pub fn read(self: *Via6522, addr: u4) u8 {
        return switch (addr) {
            0x00 => self.port_b,
            0x01 => self.readPortA(true),
            0x02 => self.ddr_b,
            0x03 => self.ddr_a,
            0x04 => @truncate(self.t1_counter & 0xFF),
            0x05 => @truncate(self.t1_counter >> 8),
            0x06 => self.t1l_l,
            0x07 => self.t1l_h,
            0x08 => @truncate(self.t2_counter & 0xFF),
            0x09 => @truncate(self.t2_counter >> 8),
            0x0A => self.sr,
            0x0B => self.acr,
            0x0C => self.pcr,
            0x0D => self.ifr,
            0x0E => self.ier | 0x80, // Bit 7 always read as 1
            0x0F => self.readPortA(false),
        };
    }

    pub fn write(self: *Via6522, addr: u4, value: u8) void {
        switch (addr) {
            0x00 => self.port_b = value,
            0x01 => self.writePortA(value, true),
            0x02 => self.ddr_b = value,
            0x03 => self.ddr_a = value,
            0x04 => self.t1l_l = value,
            0x05 => {
                self.t1l_h = value;
                self.t1_counter = (@as(u16, value) << 8) | self.t1l_l;
                self.ifr &= ~@as(u8, 0x40); // Clear T1 interrupt flag
                self.t1_active = true;
                self.updateIrq();
            },
            0x06 => self.t1l_l = value,
            0x07 => {
                self.t1l_h = value;
                self.ifr &= ~@as(u8, 0x40);
                self.updateIrq();
            },
            0x08 => self.t2_counter = (@as(u16, self.t2_counter) & 0xFF00) | value,
            0x09 => {
                self.t2_counter = (@as(u16, value) << 8) | (self.t2_counter & 0x00FF);
                self.ifr &= ~@as(u8, 0x20); // Clear T2 interrupt flag
                self.t2_active = true;
                self.updateIrq();
            },
            0x0A => self.sr = value,
            0x0B => self.acr = value,
            0x0C => self.pcr = value,
            0x0D => {
                self.ifr &= ~value; // Clear flags by writing 1s
                self.updateIrq();
            },
            0x0E => {
                if ((value & 0x80) != 0) {
                    self.ier |= (value & 0x7F);
                } else {
                    self.ier &= ~(value & 0x7F);
                }
                self.updateIrq();
            },
            0x0F => self.writePortA(value, false),
        }
    }

    fn readPortA(self: *Via6522, handshake: bool) u8 {
        _ = handshake; // TBD: CA1/CA2 handshake logic
        return self.port_a;
    }

    fn writePortA(self: *Via6522, value: u8, handshake: bool) void {
        _ = handshake; // TBD: CA1/CA2 handshake logic
        self.port_a = value;
    }

    pub fn step(self: *Via6522, cycles: u32) void {
        for (0..cycles) |_| {
            // Timer 1
            if (self.t1_active) {
                if (self.t1_counter == 0) {
                    self.ifr |= 0x40; // Set T1 interrupt flag
                    if ((self.acr & 0x40) != 0) {
                        // Free-running mode: reload
                        self.t1_counter = (@as(u16, self.t1l_h) << 8) | self.t1l_l;
                    } else {
                        // One-shot mode
                        self.t1_active = false;
                    }
                    self.updateIrq();
                } else {
                    self.t1_counter -= 1;
                }
            }

            // Timer 2
            if (self.t2_active) {
                if ((self.acr & 0x20) == 0) { // Timed interrupt mode
                    if (self.t2_counter == 0) {
                        self.ifr |= 0x20; // Set T2 interrupt flag
                        self.t2_active = false;
                        self.updateIrq();
                    } else {
                        self.t2_counter -= 1;
                    }
                }
            }
        }
    }

    fn updateIrq(self: *Via6522) void {
        if ((self.ifr & self.ier & 0x7F) != 0) {
            self.ifr |= 0x80;
            self.irq_pin = true;
        } else {
            self.ifr &= 0x7F;
            self.irq_pin = false;
        }
    }

    pub fn reset(self: *Via6522) void {
        self.port_b = 0;
        self.port_a = 0;
        self.ddr_b = 0;
        self.ddr_a = 0;
        self.t1c_l = 0;
        self.t1c_h = 0;
        self.t1l_l = 0;
        self.t1l_h = 0;
        self.t2c_l = 0;
        self.t2c_h = 0;
        self.sr = 0;
        self.acr = 0;
        self.pcr = 0;
        self.ifr = 0;
        self.ier = 0;
        self.port_a_nh = 0;
        self.t1_counter = 0;
        self.t1_latches = 0;
        self.t1_active = false;
        self.t2_counter = 0;
        self.t2_active = false;
        self.irq_pin = false;
    }
};

test "Via6522 basic timer 1" {
    var via = Via6522.init();
    via.write(0x0E, 0xC0); // Enable T1 interrupt (IER bit 7=1, bit 6=1)
    
    // Set T1 to 10 cycles
    via.write(0x04, 10); // Low
    via.write(0x05, 0);  // High (starts timer)
    
    via.step(10);
    try std.testing.expectEqual(@as(u16, 0), via.t1_counter);
    
    via.step(1);
    try std.testing.expect((via.ifr & 0x40) != 0); // Flag set
    try std.testing.expect(via.irq_pin); // IRQ active
}
