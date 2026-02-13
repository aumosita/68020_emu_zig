const std = @import("std");
const cpu = @import("../../src/core/cpu.zig");
const memory = @import("../../src/core/memory.zig");

// Simple stdout wrapper for tests
const stdout = std.io.getStdOut().writer();

pub fn main() !void {
    try stdout.print("\nRunning CPU Interrupt Tests...\n", .{});
    try stdout.print("================================\n", .{});

    var passed: u32 = 0;
    var total: u32 = 0;

    total += 1;
    if (testInterruptPriorityMask()) |_| {
        try stdout.print("  ✅ Interrupt Priority Mask test passed\n", .{});
        passed += 1;
    } else |err| {
        try stdout.print("  ❌ Interrupt Priority Mask test failed: {}\n", .{err});
    }

    total += 1;
    if (testAutovectorInterrupt()) |_| {
        try stdout.print("  ✅ Autovector Interrupt test passed\n", .{});
        passed += 1;
    } else |err| {
        try stdout.print("  ❌ Autovector Interrupt test failed: {}\n", .{err});
    }

    total += 1;
    if (testInterruptMasking()) |_| {
        try stdout.print("  ✅ Interrupt Masking test passed\n", .{});
        passed += 1;
    } else |err| {
        try stdout.print("  ❌ Interrupt Masking test failed: {}\n", .{err});
    }

    try stdout.print("\nResults: {} / {} passed\n", .{ passed, total });

    if (passed != total) {
        return error.TestsFailed;
    }
}

fn testInterruptPriorityMask() !void {
    var m68k = cpu.M68k.init(std.heap.page_allocator);
    defer m68k.deinit();

    // Default SR = 0x2700 (Supervisor, IPL=7)
    m68k.reset();
    m68k.a[7] = 0x8000; // Initialize Stack Pointer to safe area

    // Set SR to 0x2000 (Supervisor, IPL=0)
    m68k.setSR(0x2000);

    // Request Level 4 Interrupt
    m68k.setInterruptLevel(4);

    // Step should trigger interrupt processing
    // We expect the CPU to process the interrupt because Level 4 > Mask 0
    _ = try m68k.step();

    // Check if SR IPL is updated to 4
    const new_ipl = (m68k.sr >> 8) & 0x7;
    if (new_ipl != 4) {
        try stdout.print("    Expected IPL 4, got {}\n", .{new_ipl});
        return error.CheckFailed;
    }

    // Check if PC moved to Autovector handler (Vector 28 for Level 4)
    // Vector 28 (0x70) default value is 0x0
    // But we didn't write to VBR+0x70, so it loaded 0 (or whatever was in memory)

    // Check consistency: SR should keep Supervisor bit
    if ((m68k.sr & 0x2000) == 0) return error.SupervisorBitLost;
}

fn testAutovectorInterrupt() !void {
    var m68k = cpu.M68k.init(std.heap.page_allocator);
    defer m68k.deinit();

    m68k.reset();
    m68k.a[7] = 0x8000;

    // Setup Handler for Level 2 Autovector (Vector 26 = 0x1A) at offset 0x68
    // We'll point it to 0x1000
    try m68k.memory.write32(0x68, 0x1000);

    // Write an RTE instruction at 0x1000
    try m68k.memory.write16(0x1000, 0x4E73); // RTE

    // Set PC to 0x2000 (Safety)
    m68k.pc = 0x2000;

    // Set SR to 0x2000 (IPL=0)
    m68k.setSR(0x2000);

    // Trigger Level 2 Interrupt
    m68k.setInterruptLevel(2);

    // Step 1: Process Interrupt -> Jump to 0x1000, Push Stack
    _ = try m68k.step();

    if (m68k.pc != 0x1000) {
        try stdout.print("    Expected PC 0x1000, got 0x{X}\n", .{m68k.pc});
        return error.DidNotJumpToHandler;
    }

    const stacked_sr = try m68k.memory.read16(m68k.a[7]);
    const stacked_pc = try m68k.memory.read32(m68k.a[7] + 2);

    if (stacked_pc != 0x2000) {
        try stdout.print("    Expected Stacked PC 0x2000, got 0x{X}\n", .{stacked_pc});
        return error.IncorrectStackedPC;
    }

    if (stacked_sr != 0x2000) {
        try stdout.print("    Expected Stacked SR 0x2000, got 0x{X}\n", .{stacked_sr});
        return error.IncorrectStackedSR;
    }

    // Step 2: Execute RTE -> Restore PC and SR
    _ = try m68k.step();

    if (m68k.pc != 0x2000) {
        try stdout.print("    Expected Restore PC 0x2000, got 0x{X}\n", .{m68k.pc});
        return error.RteFailedPC;
    }

    // SR should be restored (IPL=0), but note that step might check interrupts again?
    // M68k.handlePendingInterrupt clears internal pending state when taking it.
    // So IPL state in cpu mod might be cleared unless it's level triggered and persistent external.
    // In our sim, setInterruptLevel updates `pending_irq_level`.
    // `handlePendingInterrupt` clears it. So it shouldn't re-trigger immediately unless set again.

    if ((m68k.sr & 0x0700) != 0) {
        try stdout.print("    Expected Restore SR IPL 0, got 0x{X}\n", .{m68k.sr});
        return error.RteFailedSR;
    }
}

fn testInterruptMasking() !void {
    var m68k = cpu.M68k.init(std.heap.page_allocator);
    defer m68k.deinit();
    m68k.a[7] = 0x8000;

    // Set SR to IPL=4
    m68k.setSR(0x2400);
    m68k.pc = 0x1000;
    try m68k.memory.write16(0x1000, 0x4E71); // NOP

    // Trigger Level 3 Interrupt (Lower than 4)
    m68k.setInterruptLevel(3);

    // Step: Should Execute NOP, NOT Interrupt
    _ = try m68k.step();

    if (m68k.pc != 0x1002) {
        try stdout.print("    Expected PC 0x1002 (NOP executed), got 0x{X}\n", .{m68k.pc});
        return error.MaskingFailed_LowLevel;
    }

    // Trigger Level 5 Interrupt (Higher than 4)
    m68k.setInterruptLevel(5);

    // Step: Should Interrupt
    // We didn't set vector, so it will probably crash or jump to 0.
    // We just check if it entered exception processing (pushed stack)
    const sp_before = m68k.a[7];
    _ = try m68k.step();
    const sp_after = m68k.a[7];

    if (sp_after >= sp_before) {
        try stdout.print("    Expected Stack Push (IRQ taken), but SP didn't decrease\n", .{});
        return error.MaskingFailed_HighLevel;
    }

    // Check IPL updated to 5
    if ((m68k.sr >> 8) & 7 != 5) return error.IPLNotUpdated;
}
