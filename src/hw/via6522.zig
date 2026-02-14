const std = @import("std");
const Scheduler = @import("../core/scheduler.zig").Scheduler;

/// MOS 6522 Versatile Interface Adapter — Enhanced Implementation
///
/// Implements the complete register set and timing behavior required for
/// Macintosh LC ROM boot. Key improvements over the stub:
///   - DDR-aware port I/O (input/output pin separation)
///   - Timer 1 free-running mode with automatic reload via scheduler
///   - Timer 2 counter read (not latch)
///   - T1C-L read clears T1 interrupt flag
///   - PB7 square wave output (ACR bit 7)
///   - IFR bit 7 auto-calculation
pub const Via6522 = struct {
    // ── Output Latches (written by CPU) ──
    port_b: u8 = 0, // 0x00 — Output Register B
    port_a: u8 = 0, // 0x01 — Output Register A (handshake)
    ddr_b: u8 = 0, // 0x02 — Data Direction B (1=output, 0=input)
    ddr_a: u8 = 0, // 0x03 — Data Direction A

    // ── External Input Pins (set by peripherals) ──
    port_a_input: u8 = 0xFF, // External PA0-PA7 state
    port_b_input: u8 = 0xFF, // External PB0-PB7 state

    // ── Timer 1 ──
    t1c_l: u8 = 0, // 0x04 — Counter low
    t1c_h: u8 = 0, // 0x05 — Counter high
    t1l_l: u8 = 0xFF, // 0x06 — Latch low
    t1l_h: u8 = 0xFF, // 0x07 — Latch high

    // ── Timer 2 ──
    t2c_l: u8 = 0, // 0x08 — Counter low (latch on write, counter on read)
    t2c_h: u8 = 0, // 0x09 — Counter high
    t2_latch_l: u8 = 0, // T2 low byte latch (written via reg 0x08)

    // ── Other Registers ──
    sr: u8 = 0, // 0x0A — Shift Register
    acr: u8 = 0, // 0x0B — Auxiliary Control Register
    pcr: u8 = 0, // 0x0C — Peripheral Control Register
    ifr: u8 = 0, // 0x0D — Interrupt Flag Register
    ier: u8 = 0, // 0x0E — Interrupt Enable Register

    // ── Internal Timer State ──
    t1_expiry: u64 = 0,
    t1_active: bool = false,
    t1_start_time: u64 = 0,
    t1_pb7_output: bool = false, // PB7 square wave state

    t2_expiry: u64 = 0,
    t2_active: bool = false,
    t2_start_time: u64 = 0,

    // ── IRQ and Scheduler ──
    irq_pin: bool = false,
    scheduler: ?*Scheduler = null,

    // ── Interrupt Source Bits ──
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
        self.port_a_input = 0xFF;
        self.port_b_input = 0xFF;
        self.t1c_l = 0;
        self.t1c_h = 0;
        self.t1l_l = 0xFF;
        self.t1l_h = 0xFF;
        self.t2c_l = 0;
        self.t2c_h = 0;
        self.t2_latch_l = 0;
        self.sr = 0;
        self.acr = 0;
        self.pcr = 0;
        self.ifr = 0;
        self.ier = 0;
        self.t1_expiry = 0;
        self.t1_active = false;
        self.t1_start_time = 0;
        self.t1_pb7_output = false;
        self.t2_expiry = 0;
        self.t2_active = false;
        self.t2_start_time = 0;
        self.irq_pin = false;
    }

    // ════════════════════════════════════════════
    //  Register Read
    // ════════════════════════════════════════════

    pub fn read(self: *Via6522, addr: u4, current_time: u64) u8 {
        return switch (addr) {
            0x00 => blk: {
                // Read Port B: (output_latch & DDR) | (input & ~DDR)
                // Reading ORB clears CB1/CB2 interrupts
                self.clearInterrupt(INT_CB1 | INT_CB2);
                var result = (self.port_b & self.ddr_b) | (self.port_b_input & ~self.ddr_b);
                // PB7 is controlled by Timer 1 if ACR bit 7 is set
                if ((self.acr & 0x80) != 0) {
                    result = (result & 0x7F) | (if (self.t1_pb7_output) @as(u8, 0x80) else 0);
                }
                break :blk result;
            },
            0x01 => blk: {
                // Read Port A with handshake: clears CA1/CA2 interrupts
                self.clearInterrupt(INT_CA1 | INT_CA2);
                break :blk (self.port_a & self.ddr_a) | (self.port_a_input & ~self.ddr_a);
            },
            0x02 => self.ddr_b,
            0x03 => self.ddr_a,
            0x04 => blk: {
                // Read T1C-L: clears T1 interrupt flag
                self.clearInterrupt(INT_T1);
                break :blk self.readTimer1Low(current_time);
            },
            0x05 => self.readTimer1High(current_time),
            0x06 => self.t1l_l,
            0x07 => self.t1l_h,
            0x08 => blk: {
                // Read T2C-L: clears T2 interrupt flag, returns counter
                self.clearInterrupt(INT_T2);
                break :blk self.readTimer2Low(current_time);
            },
            0x09 => self.readTimer2High(current_time),
            0x0A => self.sr,
            0x0B => self.acr,
            0x0C => self.pcr,
            0x0D => blk: {
                // IFR: bit 7 set if any enabled interrupt is active
                const any: u8 = if ((self.ifr & self.ier & 0x7F) != 0) 0x80 else 0;
                break :blk (self.ifr & 0x7F) | any;
            },
            0x0E => self.ier | 0x80, // IER read always has bit 7 set
            0x0F => blk: {
                // Read Port A without handshake (no interrupt side effects)
                break :blk (self.port_a & self.ddr_a) | (self.port_a_input & ~self.ddr_a);
            },
        };
    }

    // ════════════════════════════════════════════
    //  Register Write
    // ════════════════════════════════════════════

    pub fn write(self: *Via6522, addr: u4, value: u8, current_time: u64, scheduler: *Scheduler) !void {
        // Remember scheduler for timer callbacks
        self.scheduler = scheduler;

        switch (addr) {
            0x00 => {
                // Write Port B: updates output latch, clears CB1/CB2
                self.port_b = value;
                self.clearInterrupt(INT_CB1 | INT_CB2);
            },
            0x01 => {
                // Write Port A with handshake: clears CA1/CA2
                self.port_a = value;
                self.clearInterrupt(INT_CA1 | INT_CA2);
            },
            0x02 => self.ddr_b = value,
            0x03 => self.ddr_a = value,
            0x04 => self.t1l_l = value, // Write T1C-L writes to latch low
            0x05 => try self.writeTimer1High(value, current_time, scheduler),
            0x06 => self.t1l_l = value,
            0x07 => {
                // Write T1L-H: updates latch high, clears T1 interrupt
                self.t1l_h = value;
                self.clearInterrupt(INT_T1);
            },
            0x08 => self.t2_latch_l = value, // T2 low byte latch
            0x09 => try self.writeTimer2High(value, current_time, scheduler),
            0x0A => self.sr = value,
            0x0B => self.acr = value,
            0x0C => self.pcr = value,
            0x0D => {
                // Write IFR: writing 1 clears that bit
                self.ifr &= ~(value & 0x7F);
                self.updateIrq();
            },
            0x0E => {
                // Write IER: bit 7 determines set (1) or clear (0)
                if ((value & 0x80) != 0) {
                    self.ier |= (value & 0x7F);
                } else {
                    self.ier &= ~(value & 0x7F);
                }
                self.updateIrq();
            },
            0x0F => {
                // Write Port A without handshake
                self.port_a = value;
            },
        }
    }

    // ════════════════════════════════════════════
    //  Timer 1 Logic
    // ════════════════════════════════════════════

    fn writeTimer1High(self: *Via6522, value: u8, current_time: u64, scheduler: *Scheduler) !void {
        self.t1l_h = value;
        // Writing T1C-H transfers latches to counter and starts timer
        const count: u16 = (@as(u16, self.t1l_h) << 8) | self.t1l_l;

        self.t1_start_time = current_time;
        // 6522: counter counts down, interrupt at underflow (count + 1.5 cycles)
        // Simplified: interrupt after count + 2 cycles
        self.t1_expiry = current_time + @as(u64, count) + 2;
        self.t1_active = true;

        self.clearInterrupt(INT_T1);

        // PB7: set low when timer starts (if ACR bit 7)
        if ((self.acr & 0x80) != 0) {
            self.t1_pb7_output = false;
        }

        _ = try scheduler.schedule(self.t1_expiry, self, timer1Callback);
    }

    fn readTimer1Low(self: *Via6522, current_time: u64) u8 {
        if (!self.t1_active) return 0xFF;
        if (current_time >= self.t1_expiry) return 0xFF;
        const elapsed = current_time - self.t1_start_time;
        const initial: u64 = (@as(u64, @as(u16, self.t1l_h) << 8 | self.t1l_l)) + 2;
        if (elapsed >= initial) return 0xFF;
        const remaining: u16 = @truncate(initial - elapsed);
        return @truncate(remaining & 0xFF);
    }

    fn readTimer1High(self: *Via6522, current_time: u64) u8 {
        if (!self.t1_active) return 0xFF;
        if (current_time >= self.t1_expiry) return 0xFF;
        const elapsed = current_time - self.t1_start_time;
        const initial: u64 = (@as(u64, @as(u16, self.t1l_h) << 8 | self.t1l_l)) + 2;
        if (elapsed >= initial) return 0xFF;
        const remaining: u16 = @truncate(initial - elapsed);
        return @truncate(remaining >> 8);
    }

    // ════════════════════════════════════════════
    //  Timer 2 Logic
    // ════════════════════════════════════════════

    fn writeTimer2High(self: *Via6522, value: u8, current_time: u64, scheduler: *Scheduler) !void {
        self.t2c_h = value;
        self.t2c_l = self.t2_latch_l;
        const count: u16 = (@as(u16, value) << 8) | self.t2_latch_l;
        self.t2_start_time = current_time;
        self.t2_expiry = current_time + @as(u64, count) + 2;
        self.t2_active = true;
        self.clearInterrupt(INT_T2);

        _ = try scheduler.schedule(self.t2_expiry, self, timer2Callback);
    }

    fn readTimer2Low(self: *Via6522, current_time: u64) u8 {
        if (!self.t2_active) return 0xFF;
        if (current_time >= self.t2_expiry) return 0xFF;
        const elapsed = current_time - self.t2_start_time;
        const initial: u64 = (@as(u64, @as(u16, self.t2c_h) << 8 | self.t2c_l)) + 2;
        if (elapsed >= initial) return 0xFF;
        const remaining: u16 = @truncate(initial - elapsed);
        return @truncate(remaining & 0xFF);
    }

    fn readTimer2High(self: *Via6522, current_time: u64) u8 {
        if (!self.t2_active) return 0xFF;
        if (current_time >= self.t2_expiry) return 0xFF;
        const elapsed = current_time - self.t2_start_time;
        const initial: u64 = (@as(u64, @as(u16, self.t2c_h) << 8 | self.t2c_l)) + 2;
        if (elapsed >= initial) return 0xFF;
        const remaining: u16 = @truncate(initial - elapsed);
        return @truncate(remaining >> 8);
    }

    // ════════════════════════════════════════════
    //  Timer Callbacks
    // ════════════════════════════════════════════

    fn timer1Callback(context: *anyopaque, time: u64) void {
        var self: *Via6522 = @ptrCast(@alignCast(context));
        if (time != self.t1_expiry) return; // Stale event

        self.setInterrupt(INT_T1);

        // PB7 toggle on timer expiry (if ACR bit 7 set)
        if ((self.acr & 0x80) != 0) {
            self.t1_pb7_output = !self.t1_pb7_output;
        }

        // Free-running mode (ACR bit 6): reload and reschedule
        if ((self.acr & 0x40) != 0) {
            const reload: u16 = (@as(u16, self.t1l_h) << 8) | self.t1l_l;
            self.t1_start_time = time;
            self.t1_expiry = time + @as(u64, reload) + 2;

            if (self.scheduler) |sched| {
                _ = sched.schedule(self.t1_expiry, self, timer1Callback) catch {};
            }
        } else {
            // One-shot mode
            self.t1_active = false;
        }
    }

    fn timer2Callback(context: *anyopaque, time: u64) void {
        var self: *Via6522 = @ptrCast(@alignCast(context));
        if (time != self.t2_expiry) return; // Stale event

        self.setInterrupt(INT_T2);
        self.t2_active = false; // T2 is always one-shot
    }

    // ════════════════════════════════════════════
    //  Helpers
    // ════════════════════════════════════════════

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

    /// Set external input pin values (called by peripheral emulation)
    pub fn setPortAInput(self: *Via6522, value: u8) void {
        self.port_a_input = value;
    }

    /// Set external input pin values (called by peripheral emulation)
    pub fn setPortBInput(self: *Via6522, value: u8) void {
        self.port_b_input = value;
    }
};

// ════════════════════════════════════════════
//  Tests
// ════════════════════════════════════════════

test "Via6522 basic timer 1 one-shot fires interrupt" {
    var scheduler = Scheduler.init(std.testing.allocator);
    defer scheduler.deinit();

    var via = Via6522.init();
    try via.write(0x0E, 0xC0, 0, &scheduler); // Enable T1 interrupt

    // Set T1 to 10 cycles (fires at 12 with +2 offset)
    try via.write(0x04, 10, 0, &scheduler); // Latch low = 10
    try via.write(0x05, 0, 0, &scheduler); // Write high starts timer

    scheduler.runUntil(11);
    try std.testing.expect(!via.getInterruptOutput());

    scheduler.runUntil(12);
    try std.testing.expect(via.getInterruptOutput());
    try std.testing.expect(!via.t1_active); // One-shot: deactivated
}

test "Via6522 timer 1 free-running reloads and re-fires" {
    var scheduler = Scheduler.init(std.testing.allocator);
    defer scheduler.deinit();

    var via = Via6522.init();
    via.acr = 0x40; // Free-running mode (ACR bit 6)
    try via.write(0x0E, 0xC0, 0, &scheduler); // Enable T1 interrupt

    // T1 = 10, fires at 12
    try via.write(0x04, 10, 0, &scheduler);
    try via.write(0x05, 0, 0, &scheduler);

    scheduler.runUntil(12);
    try std.testing.expect(via.getInterruptOutput());
    try std.testing.expect(via.t1_active); // Still active (free-running)

    // Clear interrupt
    via.ifr = 0;
    via.irq_pin = false;

    // Should reload and fire again at 12 + 12 = 24
    scheduler.runUntil(23);
    try std.testing.expect(!via.getInterruptOutput());

    scheduler.runUntil(24);
    try std.testing.expect(via.getInterruptOutput());
}

test "Via6522 T1C-L read clears T1 interrupt" {
    var scheduler = Scheduler.init(std.testing.allocator);
    defer scheduler.deinit();

    var via = Via6522.init();
    try via.write(0x0E, 0xC0, 0, &scheduler);
    try via.write(0x04, 5, 0, &scheduler);
    try via.write(0x05, 0, 0, &scheduler);

    scheduler.runUntil(7); // Fire at 7
    try std.testing.expect(via.getInterruptOutput());

    // Read T1C-L should clear T1 interrupt
    _ = via.read(0x04, 10);
    try std.testing.expect(!via.getInterruptOutput());
    try std.testing.expectEqual(@as(u8, 0), via.ifr & Via6522.INT_T1);
}

test "Via6522 T2C-L read clears T2 interrupt and returns counter" {
    var scheduler = Scheduler.init(std.testing.allocator);
    defer scheduler.deinit();

    var via = Via6522.init();
    try via.write(0x0E, 0xA0, 0, &scheduler); // Enable T2 interrupt

    // T2 = 20, fires at 22
    try via.write(0x08, 20, 0, &scheduler); // Latch low
    try via.write(0x09, 0, 0, &scheduler); // Write high starts

    // Read counter mid-way at time=5: remaining = 22-5 = 17
    const t2_low = via.read(0x08, 5);
    try std.testing.expectEqual(@as(u8, 17), t2_low);

    scheduler.runUntil(22);
    try std.testing.expect(via.getInterruptOutput());

    // Read T2C-L clears interrupt
    _ = via.read(0x08, 25);
    try std.testing.expect(!via.getInterruptOutput());
}

test "Via6522 DDR-aware port B read" {
    var via = Via6522.init();

    // DDR: bits 7-4 output, bits 3-0 input
    via.ddr_b = 0xF0;
    via.port_b = 0xA0; // Output latch: 1010_0000
    via.port_b_input = 0x05; // External input: 0000_0101

    // Expect: output bits from latch, input bits from external
    // (0xA0 & 0xF0) | (0x05 & 0x0F) = 0xA0 | 0x05 = 0xA5
    const result = via.read(0x00, 0);
    try std.testing.expectEqual(@as(u8, 0xA5), result);
}

test "Via6522 DDR-aware port A read with handshake clears CA interrupts" {
    var via = Via6522.init();

    via.ddr_a = 0x00; // All input
    via.port_a_input = 0x42;

    // Enable CA1 interrupt first, then trigger it
    via.ier = Via6522.INT_CA1;
    via.setInterrupt(Via6522.INT_CA1);
    try std.testing.expect(via.getInterruptOutput());

    // Read port A with handshake should clear CA1
    const result = via.read(0x01, 0);
    try std.testing.expectEqual(@as(u8, 0x42), result);
    try std.testing.expect(!via.getInterruptOutput());
}

test "Via6522 IER set and clear semantics" {
    var scheduler = Scheduler.init(std.testing.allocator);
    defer scheduler.deinit();
    var via = Via6522.init();

    // Set bits: write with bit 7 = 1
    try via.write(0x0E, 0xC0, 0, &scheduler); // Set T1 enable
    try std.testing.expectEqual(@as(u8, 0x40), via.ier);

    // Set more bits
    try via.write(0x0E, 0xA0, 0, &scheduler); // Set T2 enable
    try std.testing.expectEqual(@as(u8, 0x60), via.ier);

    // Clear bits: write with bit 7 = 0
    try via.write(0x0E, 0x40, 0, &scheduler); // Clear T1 enable
    try std.testing.expectEqual(@as(u8, 0x20), via.ier);

    // IER read always has bit 7 set
    try std.testing.expectEqual(@as(u8, 0xA0), via.read(0x0E, 0));
}

test "Via6522 PB7 toggles on timer 1 expiry when ACR bit 7 set" {
    var scheduler = Scheduler.init(std.testing.allocator);
    defer scheduler.deinit();

    var via = Via6522.init();
    via.acr = 0xC0; // Free-running + PB7 output
    via.ddr_b = 0x80; // PB7 as output
    try via.write(0x0E, 0xC0, 0, &scheduler);

    try via.write(0x04, 5, 0, &scheduler);
    try via.write(0x05, 0, 0, &scheduler);

    // PB7 starts low after timer load
    try std.testing.expect(!via.t1_pb7_output);

    // After first expiry, PB7 should toggle to high
    scheduler.runUntil(7);
    try std.testing.expect(via.t1_pb7_output);

    // Read port B: bit 7 should reflect PB7 output
    const pb = via.read(0x00, 7);
    try std.testing.expectEqual(@as(u8, 0x80), pb & 0x80);
}

test "Via6522 IFR bit 7 reflects any enabled interrupt" {
    var via = Via6522.init();

    // No interrupts: bit 7 = 0
    try std.testing.expectEqual(@as(u8, 0), via.read(0x0D, 0));

    // Set T1 flag but T1 not enabled: bit 7 = 0
    via.ifr = Via6522.INT_T1;
    try std.testing.expectEqual(@as(u8, 0x40), via.read(0x0D, 0));

    // Enable T1: now bit 7 = 1
    via.ier = Via6522.INT_T1;
    try std.testing.expectEqual(@as(u8, 0xC0), via.read(0x0D, 0));
}
