const std = @import("std");
const testing = std.testing;
const root = @import("m68020");

test "VIA Timer 1 Interrupt to CPU Integration" {
    const allocator = std.testing.allocator;

    // 1. Initialize System
    const sys = try root.MacLcSystem.init(allocator, 1 * 1024 * 1024, null);
    defer sys.deinit(allocator);

    var m68k = root.M68k.initWithConfig(allocator, .{ .size = 1 * 1024 * 1024 });
    defer m68k.deinit();

    root.mac_lc_install(sys, &m68k);

    // 2. Setup CPU for Interrupts
    // Initialize Vector Table (Autovector Level 1 = Vector 25 = 0x19)
    // Vector 25 address is at 0x64.
    try m68k.memory.write32(0x64, 0x2000); // ISR Handler Address
    try m68k.memory.write16(0x2000, 0x4E73); // RTE

    // Set SR to 0x2000 (Supervisor, IPL=0) to allow Level 1 interrupt
    m68k.setSR(0x2000);
    // Initialize SP
    m68k.a[7] = 0x1000;

    // 3. Configure VIA1 Timer 1
    // Base Address for VIA1 in 24-bit mode is 0x900000.
    // Register offsets are shifted by 9 (x512).
    // ACR (Aux Control) is Reg 0xB. Addr = 0x900000 + (0xB << 9) = 0x901600.
    // T1C_L (Counter Low) is Reg 0x4. Addr = 0x900800.
    // T1C_H (Counter High) is Reg 0x5. Addr = 0x900A00.
    // IER (Interrupt Enable) is Reg 0xE. Addr = 0x901C00.

    // Set ACR to 0x00 (One-shot mode for T1, though T1 is always one-shot/continuous based on Bit 6.
    // Bit 6=0: One-shot. Bit 7=0: Disable PB7 output.
    try m68k.memory.write8Bus(0x901600, 0x00, .{});

    // Enable Timer 1 Interrupt in IER (Set bit 6, and bit 7 to set) -> 0xC0
    try m68k.memory.write8Bus(0x901C00, 0xC0, .{});

    // Write Timer 1 Counter (Low then High to load latches and start)
    // 5 cycles count (very short)
    try m68k.memory.write8Bus(0x900800, 0x05, .{}); // Low
    try m68k.memory.write8Bus(0x900A00, 0x00, .{}); // High - Starts timer

    // 4. Step System
    // We need to sync system and step CPU until interrupt happens.
    // T1 should underflow in ~5 cycles + VIA overhead.
    // VIA runs at 783.36kHz (ECLK). CPU runs at ~16MHz.
    // Ratio is about 20:1. So 5 VIA cycles = 100 CPU cycles.

    var int_taken = false;
    for (0..200) |_| { // Step enough times
        const cycles = try m68k.step();
        sys.sync(cycles);

        // Propagate interrupt from System to CPU
        const level = sys.getIrqLevel();
        m68k.setInterruptLevel(@intCast(level));

        if (m68k.pc == 0x2000) {
            int_taken = true;
            break;
        }
    }

    // Verify
    try std.testing.expect(sys.via1.getInterruptOutput()); // VIA should be asserting IRQ
    try std.testing.expectEqual(@as(u8, 1), sys.getIrqLevel()); // System level should be 1
    try std.testing.expect(int_taken); // CPU should have jumped to ISR
}

test "Nested Interrupts (RBV preempting VIA)" {
    const allocator = std.testing.allocator;
    const sys = try root.MacLcSystem.init(allocator, 1 * 1024 * 1024, null);
    defer sys.deinit(allocator);

    var m68k = root.M68k.initWithConfig(allocator, .{ .size = 1 * 1024 * 1024 });
    defer m68k.deinit();
    root.mac_lc_install(sys, &m68k);

    // Setup Vectors
    // Level 1 Autovector (VIA) -> 0x64 -> 0x2000
    try m68k.memory.write32(0x64, 0x2000);
    // Level 2 Autovector (RBV) -> 0x68 -> 0x3000
    try m68k.memory.write32(0x68, 0x3000);

    // ISR 1 Code at 0x2000:
    // NOP
    // (Wait for nested interrupt logic)
    // RTE
    try m68k.memory.write16(0x2000, 0x4E71); // NOP
    try m68k.memory.write16(0x2002, 0x4E73); // RTE

    // ISR 2 Code at 0x3000:
    // MOVEQ #42, D7
    // RTE
    try m68k.memory.write16(0x3000, 0x7E2A); // MOVEQ #42, D7
    try m68k.memory.write16(0x3002, 0x4E73); // RTE

    // Initial State
    m68k.setSR(0x2000); // IPL 0
    m68k.a[7] = 0x1000;

    // 1. Trigger VIA Interrupt (Level 1)
    // ACR=0, IER=0xC0 (Timer 1 Enable)
    try m68k.memory.write8Bus(0x901600, 0x00, .{});
    try m68k.memory.write8Bus(0x901C00, 0xC0, .{});
    // Start Timer 1 (Counter=5)
    try m68k.memory.write8Bus(0x900800, 0x05, .{});
    try m68k.memory.write8Bus(0x900A00, 0x00, .{});

    // Step until Level 1 taken
    var l1_taken = false;
    for (0..200) |_| {
        const cycles = try m68k.step();
        sys.sync(cycles);
        const level = sys.getIrqLevel();
        m68k.setInterruptLevel(@intCast(level));

        if (m68k.pc == 0x2000) {
            l1_taken = true;
            break;
        }
    }
    try std.testing.expect(l1_taken);

    // Now at Level 1 ISR. SR IPL should be 1.
    try std.testing.expectEqual(@as(u3, 1), @as(u3, @truncate((m68k.sr >> 8) & 7)));

    // 2. Trigger RBV Interrupt (Level 2)
    // Enable VBL interrupt in RBV (IER bit 3)
    // RBV Enable register is at 0xD00200 in 24-bit mode
    try m68k.memory.write8Bus(0xD00200, 0x88, .{}); // Enable VBL

    // Force VBL cycle update in Sys to trigger VBL immediately
    // Using sync(300000) is too slow in debug builds.
    // Trigger VBL bit manually.
    sys.rbv.setInterrupt(root.Rbv.BIT_VBL);

    // Check IRQ level. Should be 2.
    // But RBV logic in sync says: "if (level < 2) level = 2;"
    // So if VIA (1) is active and RBV (2) is active, level is 2.
    try std.testing.expectEqual(@as(u8, 2), sys.getIrqLevel());

    // Step CPU. It should take Level 2 interrupt because current IPL is 1.
    // 2 > 1, so it should interrupt.

    var l2_taken = false;
    for (0..50) |_| {
        // We step, but we shouldn't sync much to avoid clearing conditions or confusing things?
        // Actually sync is fine.
        const cycles = try m68k.step();
        sys.sync(cycles);
        const level = sys.getIrqLevel();
        m68k.setInterruptLevel(@intCast(level));

        if (m68k.pc == 0x3000) {
            l2_taken = true;
            break;
        }
    }
    try std.testing.expect(l2_taken);

    // Clear RBV Interrupt (Simulate ISR action)
    sys.rbv.ifr = 0;

    // Now at Level 2 ISR. SR IPL should be 2.
    try std.testing.expectEqual(@as(u3, 2), @as(u3, @truncate((m68k.sr >> 8) & 7)));

    // Verify ISR 2 code
    try std.testing.expectEqual(@as(u16, 0x7E2A), try m68k.memory.read16(0x3000));

    // Execute ISR 2 (MOVEQ, RTE) and return to L1
    // Step 1: MOVEQ
    // Step 2: RTE
    for (0..2) |_| {
        _ = try m68k.step();
    }

    // Check we returned to L1 (PC should be 0x2002, the RTE instruction of L1) (or 0x2000 if it was interrupted at NOP, wait)
    // L1 executed NOP (0x2000) then got interrupted?
    // No, I looped until l1_taken (PC=0x2000).
    // Then I executed N steps in main loop waiting for L2.
    // L1 ISR: 0x2000 NOP, 0x2002 RTE.
    // If I stepped after l1_taken:
    //    Step 1 (NOP). PC->0x2002.
    //    Interrupt L2 taken?
    // If L2 taken at 0x2002, then saved PC is 0x2002.
    // So return address is 0x2002.
    try std.testing.expectEqual(@as(u32, 0x2002), m68k.pc);

    // D7 should be 42
    try std.testing.expectEqual(@as(u32, 42), m68k.d[7]);

    // Should return to Level 1 ISR (0x2000 or 0x2002 depending on prefetch/resume)
    // Actually, after RTE from L2, we return to L1 ISR.
    // We should be back at IPL 1.
    try std.testing.expectEqual(@as(u3, 1), @as(u3, @truncate((m68k.sr >> 8) & 7)));
}
