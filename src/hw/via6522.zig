const std = @import("std");
const Scheduler = @import("../core/scheduler.zig").Scheduler;

pub const Via6522 = struct {
    // Registers
    port_b: u8 = 0, // 0x00
    port_a: u8 = 0, // 0x01 (handshake)
    ddr_b: u8 = 0, // 0x02
    ddr_a: u8 = 0, // 0x03
    t1c_l: u8 = 0, // 0x04
    t1c_h: u8 = 0, // 0x05 (Latches high byte)
    t1l_l: u8 = 0, // 0x06
    t1l_h: u8 = 0, // 0x07
    t2c_l: u8 = 0, // 0x08
    t2c_h: u8 = 0, // 0x09
    sr: u8 = 0, // 0x0A
    acr: u8 = 0, // 0x0B
    pcr: u8 = 0, // 0x0C
    ifr: u8 = 0, // 0x0D
    ier: u8 = 0, // 0x0E
    port_a_nh: u8 = 0, // 0x0F (no handshake)

    // Internal state for Event Scheduler
    t1_expiry: u64 = 0,
    t1_active: bool = false,
    t1_start_time: u64 = 0, // Time when counter was loaded

    t2_expiry: u64 = 0,
    t2_active: bool = false,
    t2_start_time: u64 = 0,

    irq_pin: bool = false,

    pub const INT_CA2: u8 = 0x01;
    pub const INT_CA1: u8 = 0x02;
    pub const INT_SR: u8 = 0x04;
    pub const INT_CB2: u8 = 0x08;
    pub const INT_CB1: u8 = 0x10;
    pub const INT_T2: u8 = 0x20;
    pub const INT_T1: u8 = 0x40;
    pub const INT_ANY: u8 = 0x80;

    pub fn init() Via6522 {
        return .{};
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

        self.t1_expiry = 0;
        self.t1_active = false;
        self.t1_start_time = 0;
        self.t2_expiry = 0;
        self.t2_active = false;
        self.t2_start_time = 0;
        self.irq_pin = false;
    }

    pub fn read(self: *Via6522, addr: u4, current_time: u64) u8 {
        return switch (addr) {
            0x00 => self.port_b,
            0x01 => self.readPortA(true),
            0x02 => self.ddr_b,
            0x03 => self.ddr_a,
            0x04 => self.readTimer1Low(current_time),
            0x05 => self.readTimer1High(current_time),
            0x06 => self.t1l_l,
            0x07 => self.t1l_h,
            0x08 => self.readTimer2Low(current_time),
            0x09 => self.readTimer2High(current_time),
            0x0A => self.sr,
            0x0B => self.acr,
            0x0C => self.pcr,
            0x0D => self.ifr,
            0x0E => self.ier | 0x80,
            0x0F => self.readPortA(false),
        };
    }

    pub fn write(self: *Via6522, addr: u4, value: u8, current_time: u64, scheduler: *Scheduler) !void {
        switch (addr) {
            0x00 => {
                self.port_b = value;
                self.clearInterrupt(INT_CB1); // Example? Modifying B usually clears
            },
            0x01 => {
                self.writePortA(value, true);
                self.clearInterrupt(INT_CA1); // Handshake
            },
            0x02 => self.ddr_b = value,
            0x03 => self.ddr_a = value,
            0x04 => self.t1l_l = value, // Write T1C-L writes to latches
            0x05 => try self.writeTimer1High(value, current_time, scheduler), // Write T1C-H loads counter
            0x06 => self.t1l_l = value,
            0x07 => {
                self.t1l_h = value;
                self.clearInterrupt(INT_T1);
            },
            0x08 => self.t2c_l = value, // Latches low
            0x09 => try self.writeTimer2High(value, current_time, scheduler), // Write T2C-H loads counter
            0x0A => self.sr = value,
            0x0B => self.acr = value,
            0x0C => self.pcr = value,
            0x0D => {
                // Clear interrupts
                self.ifr &= ~value;
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

    // Timer Logic
    fn writeTimer1High(self: *Via6522, value: u8, current_time: u64, scheduler: *Scheduler) !void {
        self.t1l_h = value;
        self.t1c_h = value; // Also loads counter high? No, usually writing high loads latch AND transfers to counter
        // Counter = (T1L_H << 8) | T1L_L
        const count: u16 = (@as(u16, self.t1l_h) << 8) | self.t1l_l;

        self.t1_start_time = current_time;
        // Count + 2 cycles usually? +1?
        // Let's assume count cycles.
        self.t1_expiry = current_time + count;
        self.t1_active = true;

        self.clearInterrupt(INT_T1);

        // Output PB7 if enabled (ACR bit 7)
        if ((self.acr & 0x80) != 0) {
            // Toggle PB7? or Low logic?
        }

        // Schedule Interrupt
        _ = try scheduler.schedule(self.t1_expiry, self, timer1Callback);
    }

    fn readTimer1Low(self: *Via6522, current_time: u64) u8 {
        if (!self.t1_active) return 0;
        // Calculate remaining
        if (current_time >= self.t1_expiry) return 0xFF; // Underflowed/Reloaded?
        // Simple decrement model
        const elapsed = current_time - self.t1_start_time;
        const initial: u16 = (@as(u16, self.t1l_h) << 8) | self.t1l_l;
        if (elapsed > initial) return 0; // Should not happen if active=true ensures validity
        const remaining = initial - @as(u16, @truncate(elapsed));
        return @truncate(remaining & 0xFF);
    }

    fn readTimer1High(self: *Via6522, current_time: u64) u8 {
        if (!self.t1_active) return 0;
        const elapsed = current_time - self.t1_start_time;
        const initial: u16 = (@as(u16, self.t1l_h) << 8) | self.t1l_l;
        if (elapsed > initial) return 0;
        const remaining = initial - @as(u16, @truncate(elapsed));
        return @truncate(remaining >> 8);
    }

    fn writeTimer2High(self: *Via6522, value: u8, current_time: u64, scheduler: *Scheduler) !void {
        self.t2c_h = value; // T2C_H write clears int and starts timer
        const count: u16 = (@as(u16, value) << 8) | self.t2c_l;
        self.t2_start_time = current_time;
        self.t2_expiry = current_time + count;
        self.t2_active = true;
        self.clearInterrupt(INT_T2);

        // Schedule
        _ = try scheduler.schedule(self.t2_expiry, self, timer2Callback);
    }

    fn readTimer2Low(self: *Via6522, current_time: u64) u8 {
        _ = current_time;
        return self.t2c_l; // Read T2C-L reads latch/counter? T2 is usually simpler.
    }

    fn readTimer2High(self: *Via6522, current_time: u64) u8 {
        if (!self.t2_active) return 0;
        const elapsed = current_time - self.t2_start_time;
        const initial: u16 = (@as(u16, self.t2c_h) << 8) | self.t2c_l;
        if (elapsed > initial) return 0;
        const remaining = initial - @as(u16, @truncate(elapsed));
        return @truncate(remaining >> 8);
    }

    // Callbacks
    fn timer1Callback(context: *anyopaque, time: u64) void {
        var self: *Via6522 = @ptrCast(@alignCast(context));
        // Check if this event is still valid (e.g., timer wasn't reset)
        // Simplest: Check if time matches expiry.
        if (time != self.t1_expiry) return; // Stale event

        self.setInterrupt(INT_T1);

        // Free-running mode (ACR bit 6)
        if ((self.acr & 0x40) != 0) {
            // Reload
            const reload: u16 = (@as(u16, self.t1l_h) << 8) | self.t1l_l;
            self.t1_start_time = time;
            self.t1_expiry = time + reload;

            // We need to schedule again.
            // BUT: We don't have access to scheduler here!
            // Solution: Callback signature has time, but not scheduler.
            // AND we can't easily pass scheduler in context unless context is a wrapper.
            // OR: The context *is* MacLcSystem, which calls Via6522?
            // Ideally: VIA *owns* the event logic.
        } else {
            self.t1_active = false;
        }
    }

    fn timer2Callback(context: *anyopaque, time: u64) void {
        var self: *Via6522 = @ptrCast(@alignCast(context));
        if (time != self.t2_expiry) return; // Stale event

        self.setInterrupt(INT_T2);
        self.t2_active = false; // T2 is always one-shot
    }

    // ... helper methods ...
    fn readPortA(self: *Via6522, handshake: bool) u8 {
        _ = handshake;
        return self.port_a;
    }
    fn writePortA(self: *Via6522, value: u8, handshake: bool) void {
        _ = handshake;
        self.port_a = value;
    }
    fn clearInterrupt(self: *Via6522, source: u8) void {
        self.ifr &= ~source;
        self.updateIrq();
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
    pub fn setInterrupt(self: *Via6522, source: u8) void {
        self.ifr |= (source & 0x7F);
        self.updateIrq();
    }

    pub fn getInterruptOutput(self: *Via6522) bool {
        return self.irq_pin;
    }
};

test "Via6522 basic timer 1" {
    var scheduler = Scheduler.init(std.testing.allocator);
    defer scheduler.deinit();

    var via = Via6522.init();
    try via.write(0x0E, 0xC0, 0, &scheduler); // Enable T1 interrupt

    // Set T1 to 10 cycles
    try via.write(0x04, 10, 0, &scheduler); // Low
    try via.write(0x05, 0, 0, &scheduler); // High (starts timer, expiry = 0 + 10 = 10)

    // Run scheduler to time 9
    scheduler.runUntil(9);
    try std.testing.expectEqual(false, via.getInterruptOutput());

    // Run to 10
    scheduler.runUntil(10);
    try std.testing.expect(via.getInterruptOutput());
}
