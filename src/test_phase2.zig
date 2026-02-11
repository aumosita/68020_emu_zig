const std = @import("std");
const cpu = @import("cpu.zig");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Running Phase 2 tests (RTR, RTE, TRAP, TAS)...\n", .{});
    
    var passed: u32 = 0;
    var total: u32 = 0;
    
    // Test RTR
    total += 1;
    testRtr() catch |err| {
        try stdout.print("  ❌ RTR test failed: {}\n", .{err});
        total -= 1;
    };
    if (total == 1) {
        try stdout.print("  ✅ RTR test passed\n", .{});
        passed += 1;
    }
    
    // Test RTE
    total += 1;
    testRte() catch |err| {
        try stdout.print("  ❌ RTE test failed: {}\n", .{err});
        total -= 1;
    };
    if (total == 2) {
        try stdout.print("  ✅ RTE test passed\n", .{});
        passed += 1;
    }
    
    // Test TRAP
    total += 1;
    testTrap() catch |err| {
        try stdout.print("  ❌ TRAP test failed: {}\n", .{err});
        total -= 1;
    };
    if (total == 3) {
        try stdout.print("  ✅ TRAP test passed\n", .{});
        passed += 1;
    }
    
    // Test TAS
    total += 1;
    testTas() catch |err| {
        try stdout.print("  ❌ TAS test failed: {}\n", .{err});
        total -= 1;
    };
    if (total == 4) {
        try stdout.print("  ✅ TAS test passed\n", .{});
        passed += 1;
    }
    
    const failed = total - passed;
    try stdout.print("\n", .{});
    try stdout.print("Results: {} passed, {} failed\n", .{passed, failed});
    
    if (failed > 0) {
        std.process.exit(1);
    }
}

fn testRtr() !void {
    var m68k = cpu.M68k.init(std.heap.page_allocator);
    defer m68k.deinit();
    
    // RTR - Return and Restore Condition Codes
    // Setup: Push CCR and PC on stack
    m68k.a[7] = 0x2000; // Stack pointer
    m68k.sr = 0x2700;   // Current SR (supervisor mode)
    
    // Push CCR (0x1F = all flags set) and return PC (0x1234)
    try m68k.memory.write16(0x2000, 0x001F); // CCR (lower byte only)
    try m68k.memory.write32(0x2002, 0x1234); // Return PC
    
    // RTR instruction
    try m68k.memory.write16(0x400, 0x4E77);
    m68k.pc = 0x400;
    
    _ = try m68k.step();
    
    // Check: PC should be restored
    if (m68k.pc != 0x1234) return error.WrongPC;
    
    // Check: CCR (lower 8 bits of SR) should be 0x1F
    if ((m68k.sr & 0x00FF) != 0x1F) return error.WrongCCR;
    
    // Check: Upper 8 bits (system byte) should be preserved
    if ((m68k.sr & 0xFF00) != 0x2700) return error.SystemByteChanged;
    
    // Check: Stack pointer should advance
    if (m68k.a[7] != 0x2006) return error.WrongStackPointer;
}

fn testRte() !void {
    var m68k = cpu.M68k.init(std.heap.page_allocator);
    defer m68k.deinit();
    
    // RTE - Return from Exception
    // Setup: Push SR and PC on stack
    m68k.a[7] = 0x2000; // Stack pointer
    m68k.sr = 0x2700;   // Current SR
    
    // Push full SR (0x2005 = supervisor, interrupt level 0, flags = 0x05)
    // and return PC (0x5678)
    try m68k.memory.write16(0x2000, 0x2005); // Full SR
    try m68k.memory.write32(0x2002, 0x5678); // Return PC
    
    // RTE instruction
    try m68k.memory.write16(0x400, 0x4E73);
    m68k.pc = 0x400;
    
    _ = try m68k.step();
    
    // Check: PC should be restored
    if (m68k.pc != 0x5678) return error.WrongPC;
    
    // Check: Full SR should be restored
    if (m68k.sr != 0x2005) return error.WrongSR;
    
    // Check: Stack pointer should advance
    if (m68k.a[7] != 0x2006) return error.WrongStackPointer;
}

fn testTrap() !void {
    var m68k = cpu.M68k.init(std.heap.page_allocator);
    defer m68k.deinit();
    
    // TRAP #0 - Software Interrupt
    // Setup: Set exception vector for TRAP #0 (vector 32 = 0x80)
    const trap_vector_addr = 0x80; // Vector 32 * 4
    try m68k.memory.write32(trap_vector_addr, 0x1000); // Handler at 0x1000
    
    m68k.a[7] = 0x2000; // Stack pointer
    m68k.sr = 0x2000;   // User mode initially
    m68k.pc = 0x400;
    
    // TRAP #0 instruction
    try m68k.memory.write16(0x400, 0x4E40); // TRAP #0
    
    _ = try m68k.step();
    
    // Check: PC should jump to handler
    if (m68k.pc != 0x1000) return error.WrongPC;
    
    // Check: SR and return PC should be pushed
    if (m68k.a[7] != 0x1FFA) return error.WrongStackPointer;
    
    const saved_sr = try m68k.memory.read16(0x1FFA);
    const saved_pc = try m68k.memory.read32(0x1FFC);
    
    if (saved_sr != 0x2000) return error.WrongSavedSR;
    if (saved_pc != 0x402) return error.WrongSavedPC; // PC after TRAP
    
    // Check: Supervisor mode should be set
    if ((m68k.sr & 0x2000) == 0) return error.NotInSupervisorMode;
}

fn testTas() !void {
    var m68k = cpu.M68k.init(std.heap.page_allocator);
    defer m68k.deinit();
    
    // TAS - Test and Set (atomic operation)
    // Test value at memory location
    try m68k.memory.write8(0x1000, 0x42); // Test value (bit 7 = 0)
    
    // TAS (A0) - where A0 points to 0x1000
    m68k.a[0] = 0x1000;
    try m68k.memory.write16(0x400, 0x4AD0); // TAS (A0)
    m68k.pc = 0x400;
    
    _ = try m68k.step();
    
    // Check: Value should have bit 7 set
    const new_value = try m68k.memory.read8(0x1000);
    if (new_value != 0xC2) return error.WrongValue; // 0x42 | 0x80 = 0xC2
    
    // Check: Flags should be set based on original value (0x42)
    // N=0 (bit 7 was 0), Z=0 (not zero), V=0, C=0
    const n_flag = (m68k.sr & 0x08) != 0;
    const z_flag = (m68k.sr & 0x04) != 0;
    
    if (n_flag) return error.WrongNFlag;
    if (z_flag) return error.WrongZFlag;
    
    // Test with zero value
    try m68k.memory.write8(0x1000, 0x00);
    m68k.pc = 0x400;
    
    _ = try m68k.step();
    
    // Check: Value should be 0x80
    const zero_test_value = try m68k.memory.read8(0x1000);
    if (zero_test_value != 0x80) return error.WrongZeroValue;
    
    // Check: Z flag should be set
    const z_flag_set = (m68k.sr & 0x04) != 0;
    if (!z_flag_set) return error.ZFlagNotSet;
}
