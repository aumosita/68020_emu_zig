const std = @import("std");
const testing = std.testing;
const root = @import("m68020");
const MacLcSystem = root.MacLcSystem;
const Scheduler = root.Scheduler; // Assuming exported
const Rbv = root.Rbv; // Assuming exported

test "RBV VBL Timing" {
    const allocator = testing.allocator;

    // Initialize System
    var sys = try MacLcSystem.init(allocator, 4 * 1024 * 1024, null);
    defer sys.deinit(allocator);

    // System init starts the VBL loop in Rbv
    // VBL Interval is 266,667 cycles.

    // 1. Check initial state
    try testing.expectEqual(@as(u64, 0), sys.scheduler.current_time);
    try testing.expect(!sys.rbv.getInterruptOutput());
    try testing.expect((sys.rbv.ifr & Rbv.BIT_VBL) == 0);

    // 2. Advance time close to VBL but before it
    // Say 266,000 cycles
    while (sys.scheduler.current_time < 266000) {
        if (sys.scheduler.nextEventTime()) |next_time| {
            if (next_time > 266000) break;
            sys.scheduler.runUntil(next_time);
        } else {
            break; // No events? Should have VBL.
        }
    }

    // Check IRQ still clear
    try testing.expect((sys.rbv.ifr & Rbv.BIT_VBL) == 0);

    // 3. Advance past 266,667
    const target_time = 266668;
    while (sys.scheduler.current_time < target_time) {
        if (sys.scheduler.nextEventTime()) |next_time| {
            sys.scheduler.runUntil(next_time);
            if (next_time > target_time) break;
        } else {
            break;
        }
    }

    // Check IRQ set
    try testing.expect((sys.rbv.ifr & Rbv.BIT_VBL) != 0);

    // 4. Acknowledge Interrupt (Write 1 to clear?)
    // In VIA, writing 1 to IFR usually clears. In Rbv?
    // rbv.zig implementation: self.ifr &= ~value;
    // So writing BIT_VBL (0x08) should clear it if we follow that logic.
    sys.rbv.write(0x00, Rbv.BIT_VBL);
    try testing.expect((sys.rbv.ifr & Rbv.BIT_VBL) == 0);
}
