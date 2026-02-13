const std = @import("std");
const cpu = @import("cpu.zig");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    
    try stdout.print("Motorola 68020 Emulator - Stack Operation Test Suite\n", .{});
    try stdout.print("=====================================================\n\n", .{});
    
    var m68k = cpu.M68k.init(std.heap.page_allocator);
    defer m68k.deinit();
    
    var passed: u32 = 0;
    var total: u32 = 0;
    
    // Test LINK
    total += 1;
    try stdout.print("Test {}: LINK A6, #-16 (create stack frame)\n", .{total});
    m68k.a[6] = 0x12345678; // Old frame pointer
    m68k.a[7] = 0x00002000; // Stack pointer
    try m68k.memory.write16(0x1000, 0x4E56); // LINK A6, #disp
    try m68k.memory.write16(0x1002, 0xFFF0); // -16
    m68k.pc = 0x1000;
    _ = try m68k.step();
    
    const new_sp = m68k.a[7];
    const new_fp = m68k.a[6];
    const saved_fp = try m68k.memory.read32(new_fp);
    
    if (saved_fp == 0x12345678 and new_fp == 0x00001FFC and new_sp == 0x00001FEC) {
        try stdout.print("  ✓ PASS (FP=0x{X}, SP=0x{X}, saved=0x{X})\n", .{new_fp, new_sp, saved_fp});
        passed += 1;
    } else {
        try stdout.print("  ✗ FAIL (FP=0x{X}, SP=0x{X}, saved=0x{X})\n", .{new_fp, new_sp, saved_fp});
    }
    
    // Test UNLK
    total += 1;
    try stdout.print("\nTest {}: UNLK A6 (restore stack frame)\n", .{total});
    try m68k.memory.write16(0x1000, 0x4E5E); // UNLK A6
    m68k.pc = 0x1000;
    _ = try m68k.step();
    
    if (m68k.a[6] == 0x12345678 and m68k.a[7] == 0x00002000) {
        try stdout.print("  ✓ PASS (restored FP=0x{X}, SP=0x{X})\n", .{m68k.a[6], m68k.a[7]});
        passed += 1;
    } else {
        try stdout.print("  ✗ FAIL (FP=0x{X}, SP=0x{X})\n", .{m68k.a[6], m68k.a[7]});
    }
    
    // Test PEA
    total += 1;
    try stdout.print("\nTest {}: PEA (A0) (push effective address)\n", .{total});
    m68k.a[0] = 0xDEADBEEF;
    m68k.a[7] = 0x00002000;
    try m68k.memory.write16(0x1000, 0x4850); // PEA (A0)
    m68k.pc = 0x1000;
    _ = try m68k.step();
    
    const pushed_addr = try m68k.memory.read32(m68k.a[7]);
    if (m68k.a[7] == 0x00001FFC and pushed_addr == 0xDEADBEEF) {
        try stdout.print("  ✓ PASS (SP=0x{X}, pushed=0x{X})\n", .{m68k.a[7], pushed_addr});
        passed += 1;
    } else {
        try stdout.print("  ✗ FAIL (SP=0x{X}, pushed=0x{X})\n", .{m68k.a[7], pushed_addr});
    }
    
    // Test MOVEM registers to memory
    total += 1;
    try stdout.print("\nTest {}: MOVEM.L D0-D2/A0, (A1) (save registers)\n", .{total});
    m68k.d[0] = 0x11111111;
    m68k.d[1] = 0x22222222;
    m68k.d[2] = 0x33333333;
    m68k.a[0] = 0xAAAAAAAA;
    m68k.a[1] = 0x00003000;
    
    // Mask: D0,D1,D2,A0 = bits 0,1,2,8 = 0x0107
    try m68k.memory.write16(0x1000, 0x48D1); // MOVEM.L <list>, (A1)
    try m68k.memory.write16(0x1002, 0x0107); // Register mask
    m68k.pc = 0x1000;
    _ = try m68k.step();
    
    const val0 = try m68k.memory.read32(0x00003000);
    const val1 = try m68k.memory.read32(0x00003004);
    const val2 = try m68k.memory.read32(0x00003008);
    const val3 = try m68k.memory.read32(0x0000300C);
    
    if (val0 == 0x11111111 and val1 == 0x22222222 and val2 == 0x33333333 and val3 == 0xAAAAAAAA) {
        try stdout.print("  ✓ PASS (saved D0,D1,D2,A0)\n", .{});
        passed += 1;
    } else {
        try stdout.print("  ✗ FAIL (D0=0x{X}, D1=0x{X}, D2=0x{X}, A0=0x{X})\n", .{val0, val1, val2, val3});
    }
    
    // Test MOVEM memory to registers
    total += 1;
    try stdout.print("\nTest {}: MOVEM.L (A1), D3-D5/A1 (restore registers)\n", .{total});
    m68k.d[3] = 0;
    m68k.d[4] = 0;
    m68k.d[5] = 0;
    m68k.a[1] = 0x00003000;
    
    // Mask: D3,D4,D5,A1 = bits 3,4,5,9 = 0x0238
    try m68k.memory.write16(0x1000, 0x4CD1); // MOVEM.L (A1), <list>
    try m68k.memory.write16(0x1002, 0x0238); // Register mask
    m68k.pc = 0x1000;
    _ = try m68k.step();
    
    if (m68k.d[3] == 0x11111111 and m68k.d[4] == 0x22222222 and m68k.d[5] == 0x33333333 and m68k.a[1] == 0xAAAAAAAA) {
        try stdout.print("  ✓ PASS (loaded D3,D4,D5,A1)\n", .{});
        passed += 1;
    } else {
        try stdout.print("  ✗ FAIL (D3=0x{X}, D4=0x{X}, D5=0x{X}, A1=0x{X})\n", .{m68k.d[3], m68k.d[4], m68k.d[5], m68k.a[1]});
    }
    
    // Test MOVEM with predecrement (save to stack)
    total += 1;
    try stdout.print("\nTest {}: MOVEM.L D6-D7, -(A7) (push to stack)\n", .{total});
    m68k.d[6] = 0x66666666;
    m68k.d[7] = 0x77777777;
    m68k.a[7] = 0x00004000;
    
    // Mask: D6,D7 = bits 6,7 = 0x00C0
    try m68k.memory.write16(0x1000, 0x48E7); // MOVEM.L <list>, -(A7)
    try m68k.memory.write16(0x1002, 0x00C0); // Register mask
    m68k.pc = 0x1000;
    _ = try m68k.step();
    
    const stack_val1 = try m68k.memory.read32(m68k.a[7]);
    const stack_val2 = try m68k.memory.read32(m68k.a[7] + 4);
    
    // Predecrement stores in reverse: D7 first (higher address), then D6 (lower address)
    // So [SP] = D6, [SP+4] = D7
    if (m68k.a[7] == 0x00003FF8 and stack_val1 == 0x66666666 and stack_val2 == 0x77777777) {
        try stdout.print("  ✓ PASS (SP=0x{X}, D6 then D7)\n", .{m68k.a[7]});
        passed += 1;
    } else {
        try stdout.print("  ✗ FAIL (SP=0x{X}, [SP]=0x{X}, [SP+4]=0x{X})\n", .{m68k.a[7], stack_val1, stack_val2});
    }
    
    // Summary
    try stdout.print("\n" ++ "=" ** 50 ++ "\n", .{});
    try stdout.print("Test Results: {} / {} passed ({d:.1}%)\n", .{
        passed, total, @as(f64, @floatFromInt(passed)) / @as(f64, @floatFromInt(total)) * 100.0
    });
    
    if (passed == total) {
        try stdout.print("\n🎉 All stack operation tests passed!\n", .{});
    } else {
        try stdout.print("\n⚠️  Some tests failed\n", .{});
    }
    
    try stdout.print("\n📊 Implemented Stack Operations:\n", .{});
    try stdout.print("  ✓ LINK - Create stack frame (save FP, allocate locals)\n", .{});
    try stdout.print("  ✓ UNLK - Restore stack frame (restore FP, deallocate)\n", .{});
    try stdout.print("  ✓ PEA - Push Effective Address\n", .{});
    try stdout.print("  ✓ MOVEM - Move Multiple registers\n", .{});
    try stdout.print("\n  Features:\n", .{});
    try stdout.print("    - LINK/UNLK for function prologue/epilogue\n", .{});
    try stdout.print("    - MOVEM supports register masks\n", .{});
    try stdout.print("    - MOVEM predecrement stores in reverse order\n", .{});
    try stdout.print("    - MOVEM postincrement loads in forward order\n", .{});
    try stdout.print("    - Word/Long size support for MOVEM\n", .{});
}
