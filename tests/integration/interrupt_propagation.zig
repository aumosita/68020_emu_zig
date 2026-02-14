const std = @import("std");
const testing = std.testing;
const root = @import("m68020");
const MacLcSystem = root.MacLcSystem;
const Scheduler = root.Scheduler;
const Rbv = root.Rbv;

// Bus access for writing test setup data through MMIO (required when Mac LC
// MMIO routes RAM through sys.ram[] instead of memory.data[]).
const sd: root.BusAccess = .{ .function_code = 0b101, .space = .Data, .is_write = true };

test "Interrupt Propagation: Level 1 (VIA) -> RTE" {
    const allocator = testing.allocator;
    var system = try MacLcSystem.init(allocator, 1 * 1024 * 1024, null);
    defer system.deinit(allocator);

    var m68k = root.M68k.initWithConfig(allocator, .{ .size = 1 * 1024 * 1024 });
    defer m68k.deinit();
    root.mac_lc_install(system, &m68k);

    // Setup Vector 25 (Level 1 Autovector) -> 0x2000
    try m68k.memory.write32Bus(0x64, 0x2000, sd);
    // ISR at 0x2000: RTE
    try m68k.memory.write16Bus(0x2000, 0x4E73, sd);

    // Initial State: PC=0x1000, SR=0x2000 (Supervisor, IPL=0)
    m68k.pc = 0x1000;
    m68k.setSR(0x2000);
    m68k.a[7] = 0x4000; // Stack at 0x4000

    // Trigger VIA Interrupt (Level 1)
    system.via1.ier = 0x80 | root.Via6522.INT_T1; // Enable T1
    system.via1.setInterrupt(root.Via6522.INT_T1); // Set T1 Flag
    m68k.setInterruptLevel(@intCast(system.getIrqLevel()));

    // Step until PC=0x2000
    var entered_isr = false;
    for (0..200) |_| {
        const cycles = try m68k.step();
        system.sync(cycles);
        const level = system.getIrqLevel();
        m68k.setInterruptLevel(@intCast(level));

        if (m68k.pc == 0x2000) {
            entered_isr = true;
            break;
        }
    }
    try testing.expect(entered_isr);

    // Clear VIA Interrupt (Simulate ISR doing it)
    system.via1.ifr &= ~root.Via6522.INT_T1;
    m68k.setInterruptLevel(@intCast(system.getIrqLevel()));

    // Verify IPL in ISR is 1
    const current_ipl = (m68k.sr >> 8) & 7;
    try testing.expectEqual(@as(u16, 1), current_ipl);

    // Execute RTE
    _ = try m68k.step();

    // Verify Return
    try testing.expectEqual(@as(u32, 0x1000), m68k.pc);

    // IPL should be 0
    const returned_ipl = (m68k.sr >> 8) & 7;
    try testing.expectEqual(@as(u16, 0), returned_ipl);
}

test "Interrupt Propagation: Nested (L1 -> L2 -> L1 -> Main)" {
    const allocator = testing.allocator;
    var system = try MacLcSystem.init(allocator, 1 * 1024 * 1024, null);
    defer system.deinit(allocator);

    var m68k = root.M68k.initWithConfig(allocator, .{ .size = 1 * 1024 * 1024 });
    defer m68k.deinit();
    root.mac_lc_install(system, &m68k);

    // Vector 25 (L1) -> 0x2000
    try m68k.memory.write32Bus(0x64, 0x2000, sd);
    // ISR 1: NOP, NOP, RTE
    try m68k.memory.write16Bus(0x2000, 0x4E71, sd);
    try m68k.memory.write16Bus(0x2002, 0x4E71, sd);
    try m68k.memory.write16Bus(0x2004, 0x4E73, sd);

    // Vector 26 (L2) Autovector -> 0x68 -> 0x3000
    try m68k.memory.write32Bus(0x68, 0x3000, sd);
    // ISR 2: RTE
    try m68k.memory.write16Bus(0x3000, 0x4E73, sd);

    // Initial State
    m68k.pc = 0x1000;
    m68k.setSR(0x2000); // IPL 0
    m68k.a[7] = 0x4000;

    // 1. Trigger L1 (VIA)
    system.via1.ier = 0x80 | root.Via6522.INT_T1; // Enable T1
    system.via1.setInterrupt(root.Via6522.INT_T1);
    m68k.setInterruptLevel(@intCast(system.getIrqLevel()));

    // Run until L1 ISR
    var l1_taken = false;
    for (0..200) |_| {
        const cycles = try m68k.step();
        system.sync(cycles);
        m68k.setInterruptLevel(@intCast(system.getIrqLevel()));
        if (m68k.pc == 0x2000) {
            l1_taken = true;
            break;
        }
    }
    try testing.expect(l1_taken);
    try testing.expectEqual(@as(u16, 1), (m68k.sr >> 8) & 7);

    // 2. Trigger L2 (RBV) inside L1 ISR
    _ = try m68k.step();
    try testing.expectEqual(@as(u32, 0x2002), m68k.pc);

    // Now Trigger RBV VBL (Level 2)
    system.rbv.ier = 0x80 | root.Rbv.BIT_VBL; // Enable VBL
    system.rbv.setInterrupt(root.Rbv.BIT_VBL);
    m68k.setInterruptLevel(@intCast(system.getIrqLevel()));

    // Verify system level is 2
    try testing.expectEqual(@as(u8, 2), system.getIrqLevel());

    // Step CPU (should preempt L1 because 2 > 1)
    var l2_taken = false;
    for (0..20) |_| {
        const cycles = try m68k.step();
        system.sync(cycles);
        m68k.setInterruptLevel(@intCast(system.getIrqLevel()));
        if (m68k.pc == 0x3000) {
            l2_taken = true;
            break;
        }
    }
    try testing.expect(l2_taken);

    // Verify L2 Context
    try testing.expectEqual(@as(u16, 2), (m68k.sr >> 8) & 7);

    // 3. Return from L2 (RTE)
    // Clear RBV Interrupt
    system.rbv.ifr &= ~root.Rbv.BIT_VBL;
    m68k.setInterruptLevel(@intCast(system.getIrqLevel()));

    _ = try m68k.step(); // RTE

    try testing.expectEqual(@as(u32, 0x2002), m68k.pc);
    try testing.expectEqual(@as(u16, 1), (m68k.sr >> 8) & 7);

    // 4. Finish L2 ISR (NOP at 0x2002 -> 0x2004)
    _ = try m68k.step();
    try testing.expectEqual(@as(u32, 0x2004), m68k.pc);

    // 5. Return from L1 (RTE at 0x2004)
    // Clear VIA Interrupt
    system.via1.ifr &= ~root.Via6522.INT_T1;
    m68k.setInterruptLevel(@intCast(system.getIrqLevel()));

    _ = try m68k.step();

    try testing.expectEqual(@as(u32, 0x1000), m68k.pc);
    try testing.expectEqual(@as(u16, 0), (m68k.sr >> 8) & 7);
}

test "Interrupt Propagation: Priority Masking (L1 ignored at IPL 2)" {
    const allocator = testing.allocator;
    var system = try MacLcSystem.init(allocator, 1 * 1024 * 1024, null);
    defer system.deinit(allocator);

    var m68k = root.M68k.initWithConfig(allocator, .{ .size = 1 * 1024 * 1024 });
    defer m68k.deinit();
    root.mac_lc_install(system, &m68k);

    // Initial State: PC=0x1000, SR=0x2200 (Supervisor, IPL=2)
    m68k.pc = 0x1000;
    m68k.setSR(0x2200);
    m68k.a[7] = 0x4000;

    // Vector 25 (L1) -> 0x2000
    try m68k.memory.write32Bus(0x64, 0x2000, sd);
    // Code at 0x1000: NOP
    try m68k.memory.write16Bus(0x1000, 0x4E71, sd);

    // Trigger L1 (VIA)
    system.via1.ier = 0x80 | root.Via6522.INT_T1;
    system.via1.setInterrupt(root.Via6522.INT_T1);
    m68k.setInterruptLevel(@intCast(system.getIrqLevel()));

    // Step. Should NOT take interrupt because L1 < IPL2.
    // Should execute NOP (0x1000) -> 0x1002.
    _ = try m68k.step();

    try testing.expectEqual(@as(u32, 0x1002), m68k.pc);
    try testing.expectEqual(@as(u16, 2), (m68k.sr >> 8) & 7);
}

test "Interrupt Propagation: Spurious Interrupt" {
    const allocator = testing.allocator;
    var system = try MacLcSystem.init(allocator, 1 * 1024 * 1024, null);
    defer system.deinit(allocator);

    var m68k = root.M68k.initWithConfig(allocator, .{ .size = 1 * 1024 * 1024 });
    defer m68k.deinit();
    root.mac_lc_install(system, &m68k);

    // Vector 24 (Spurious) -> 0x4000
    try m68k.memory.write32Bus(0x60, 0x4000, sd);
    // ISR at 0x4000: RTE
    try m68k.memory.write16Bus(0x4000, 0x4E73, sd);

    m68k.pc = 0x1000;
    m68k.setSR(0x2000); // IPL 0
    m68k.a[7] = 0x8000;

    // Trigger Spurious Interrupt (Level 3)
    m68k.setSpuriousInterrupt(3);

    // Step. Should take interrupt.
    _ = try m68k.step();

    // Should be at 0x4000
    try testing.expectEqual(@as(u32, 0x4000), m68k.pc);
    // IPL should be 3
    try testing.expectEqual(@as(u16, 3), (m68k.sr >> 8) & 7);

    // Execute RTE
    _ = try m68k.step();
    try testing.expectEqual(@as(u32, 0x1000), m68k.pc);
}

test "Interrupt Propagation: Vectorized Interrupt (External Vector 0x40)" {
    const allocator = testing.allocator;
    var system = try MacLcSystem.init(allocator, 1 * 1024 * 1024, null);
    defer system.deinit(allocator);

    var m68k = root.M68k.initWithConfig(allocator, .{ .size = 1 * 1024 * 1024 });
    defer m68k.deinit();
    root.mac_lc_install(system, &m68k);

    // Initial State
    m68k.pc = 0x1000;
    m68k.setSR(0x2000); // IPL 0
    m68k.a[7] = 0x8000;

    // Vector 0x40 (64) -> 0x5000
    try m68k.memory.write32Bus(0x40 * 4, 0x5000, sd);
    // ISR at 0x5000: RTE
    try m68k.memory.write16Bus(0x5000, 0x4E73, sd);

    // Trigger Level 4 Interrupt with Vector 0x40
    m68k.setInterruptVector(4, 0x40);

    // Step. Should take interrupt to 0x5000.
    _ = try m68k.step();

    try testing.expectEqual(@as(u32, 0x5000), m68k.pc);
    // Verify IPL is 4 (masked by level)
    try testing.expectEqual(@as(u16, 4), (m68k.sr >> 8) & 7);

    // Execute RTE
    _ = try m68k.step();
    try testing.expectEqual(@as(u32, 0x1000), m68k.pc);
}
