const std = @import("std");
const testing = std.testing;
const Scc = @import("m68020").Scc;

test "SCC: Initial RR0 returns Tx Empty + CTS" {
    var scc = Scc.init();
    // Channel A control read (odd address, bit 1 = 0)
    const rr0_a = scc.read(1); // Channel A control
    try testing.expectEqual(@as(u8, 0x24), rr0_a); // Tx empty (bit 2) + CTS (bit 5)

    // Channel B control read (even address, bit 1 = 0)
    const rr0_b = scc.read(0); // Channel B control
    try testing.expectEqual(@as(u8, 0x24), rr0_b);
}

test "SCC: Write register pointer selects RR" {
    var scc = Scc.init();
    // Write WR0 with pointer = 1 to Channel A
    scc.write(1, 0x01); // Set RR pointer to 1
    // Now read should return RR1 (All Sent = 0x01)
    const rr1 = scc.read(1);
    try testing.expectEqual(@as(u8, 0x01), rr1);
    // Pointer auto-resets to 0, next read returns RR0
    const rr0 = scc.read(1);
    try testing.expectEqual(@as(u8, 0x24), rr0);
}

test "SCC: Data register read returns 0" {
    var scc = Scc.init();
    // Data register: bit 1 = 1, so addr = 2 (Channel B data) or 3 (Channel A data)
    const data_a = scc.read(3); // Channel A data
    try testing.expectEqual(@as(u8, 0x00), data_a);
    const data_b = scc.read(2); // Channel B data
    try testing.expectEqual(@as(u8, 0x00), data_b);
}

test "SCC: Data register write does not crash" {
    var scc = Scc.init();
    // Writing data should be silently ignored
    scc.write(3, 0xFF);
    scc.write(2, 0xAA);
    // Verify state unchanged
    const rr0 = scc.read(1);
    try testing.expectEqual(@as(u8, 0x24), rr0);
}

test "SCC: Reset clears state" {
    var scc = Scc.init();
    scc.write(1, 0x01); // Set pointer
    scc.reset();
    // After reset, RR0 should still return default
    const rr0 = scc.read(0);
    try testing.expectEqual(@as(u8, 0x24), rr0);
}

test "SCC: No interrupt pending initially" {
    var scc = Scc.init();
    try testing.expect(!scc.getInterruptOutput());
}
