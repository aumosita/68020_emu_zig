const std = @import("std");
const cpu = @import("../../src/core/cpu.zig");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    
    try stdout.print("Motorola 68020 Emulator - Shift/Rotate Test Suite\n", .{});
    try stdout.print("===================================================\n\n", .{});
    
    var m68k = cpu.M68k.init(std.heap.page_allocator);
    defer m68k.deinit();
    
    var passed: u32 = 0;
    var total: u32 = 0;
    
    // Test LSL (Logical Shift Left)
    total += 1;
    try stdout.print("Test {}: LSL.L #1, D0 (0x80000000 << 1)\n", .{total});
    m68k.d[0] = 0x80000000;
    try m68k.memory.write16(0x1000, 0xE388); // LSL.L #1, D0
    m68k.pc = 0x1000;
    _ = try m68k.step();
    if (m68k.d[0] == 0 and m68k.getFlag(cpu.M68k.FLAG_C) and m68k.getFlag(cpu.M68k.FLAG_Z)) {
        try stdout.print("  ✓ PASS (result=0, C=1, Z=1)\n", .{});
        passed += 1;
    } else {
        try stdout.print("  ✗ FAIL (got 0x{X}, C={}, Z={})\n", .{m68k.d[0], m68k.getFlag(cpu.M68k.FLAG_C), m68k.getFlag(cpu.M68k.FLAG_Z)});
    }
    
    // Test LSR (Logical Shift Right)
    total += 1;
    try stdout.print("\nTest {}: LSR.L #1, D1 (0x00000001 >> 1)\n", .{total});
    m68k.d[1] = 0x00000001;
    try m68k.memory.write16(0x1000, 0xE289); // LSR.L #1, D1
    m68k.pc = 0x1000;
    _ = try m68k.step();
    if (m68k.d[1] == 0 and m68k.getFlag(cpu.M68k.FLAG_C) and m68k.getFlag(cpu.M68k.FLAG_Z)) {
        try stdout.print("  ✓ PASS (result=0, C=1, Z=1)\n", .{});
        passed += 1;
    } else {
        try stdout.print("  ✗ FAIL (got 0x{X}, C={}, Z={})\n", .{m68k.d[1], m68k.getFlag(cpu.M68k.FLAG_C), m68k.getFlag(cpu.M68k.FLAG_Z)});
    }
    
    // Test ASL (Arithmetic Shift Left)
    total += 1;
    try stdout.print("\nTest {}: ASL.W #4, D2 (0x0010 << 4 = 0x0100)\n", .{total});
    m68k.d[2] = 0x00000010;
    try m68k.memory.write16(0x1000, 0xE94A); // ASL.W #4, D2
    m68k.pc = 0x1000;
    _ = try m68k.step();
    if ((m68k.d[2] & 0xFFFF) == 0x0100) {
        try stdout.print("  ✓ PASS (result=0x{X})\n", .{m68k.d[2] & 0xFFFF});
        passed += 1;
    } else {
        try stdout.print("  ✗ FAIL (got 0x{X})\n", .{m68k.d[2] & 0xFFFF});
    }
    
    // Test ASR (Arithmetic Shift Right with sign extension)
    total += 1;
    try stdout.print("\nTest {}: ASR.W #2, D3 (0x8000 >> 2 = 0xE000)\n", .{total});
    m68k.d[3] = 0x00008000;
    try m68k.memory.write16(0x1000, 0xE443); // ASR.W #2, D3 (corrected opcode)
    m68k.pc = 0x1000;
    _ = try m68k.step();
    if ((m68k.d[3] & 0xFFFF) == 0xE000 and m68k.getFlag(cpu.M68k.FLAG_N)) {
        try stdout.print("  ✓ PASS (result=0x{X}, N=1)\n", .{m68k.d[3] & 0xFFFF});
        passed += 1;
    } else {
        try stdout.print("  ✗ FAIL (got 0x{X}, N={})\n", .{m68k.d[3] & 0xFFFF, m68k.getFlag(cpu.M68k.FLAG_N)});
    }
    
    // Test ROL (Rotate Left)
    total += 1;
    try stdout.print("\nTest {}: ROL.B #1, D4 (0x80 rotated left = 0x01)\n", .{total});
    m68k.d[4] = 0x00000080;
    try m68k.memory.write16(0x1000, 0xE31C); // ROL.B #1, D4
    m68k.pc = 0x1000;
    _ = try m68k.step();
    if ((m68k.d[4] & 0xFF) == 0x01 and m68k.getFlag(cpu.M68k.FLAG_C)) {
        try stdout.print("  ✓ PASS (result=0x{X}, C=1)\n", .{m68k.d[4] & 0xFF});
        passed += 1;
    } else {
        try stdout.print("  ✗ FAIL (got 0x{X}, C={})\n", .{m68k.d[4] & 0xFF, m68k.getFlag(cpu.M68k.FLAG_C)});
    }
    
    // Test ROR (Rotate Right)
    total += 1;
    try stdout.print("\nTest {}: ROR.B #1, D5 (0x01 rotated right = 0x80)\n", .{total});
    m68k.d[5] = 0x00000001;
    try m68k.memory.write16(0x1000, 0xE21D); // ROR.B #1, D5
    m68k.pc = 0x1000;
    _ = try m68k.step();
    if ((m68k.d[5] & 0xFF) == 0x80 and m68k.getFlag(cpu.M68k.FLAG_C) and m68k.getFlag(cpu.M68k.FLAG_N)) {
        try stdout.print("  ✓ PASS (result=0x{X}, C=1, N=1)\n", .{m68k.d[5] & 0xFF});
        passed += 1;
    } else {
        try stdout.print("  ✗ FAIL (got 0x{X}, C={}, N={})\n", .{m68k.d[5] & 0xFF, m68k.getFlag(cpu.M68k.FLAG_C), m68k.getFlag(cpu.M68k.FLAG_N)});
    }
    
    // Test ROXL (Rotate with Extend Left)
    total += 1;
    try stdout.print("\nTest {}: ROXL.B #1, D6 (0x00 with X=1 rotated = 0x01)\n", .{total});
    m68k.d[6] = 0x00000000;
    m68k.setFlag(cpu.M68k.FLAG_X, true);
    try m68k.memory.write16(0x1000, 0xE316); // ROXL.B #1, D6
    m68k.pc = 0x1000;
    _ = try m68k.step();
    if ((m68k.d[6] & 0xFF) == 0x01) {
        try stdout.print("  ✓ PASS (result=0x{X})\n", .{m68k.d[6] & 0xFF});
        passed += 1;
    } else {
        try stdout.print("  ✗ FAIL (got 0x{X})\n", .{m68k.d[6] & 0xFF});
    }
    
    // Test ROXR (Rotate with Extend Right)
    total += 1;
    try stdout.print("\nTest {}: ROXR.B #1, D7 (0x00 with X=1 rotated = 0x80)\n", .{total});
    m68k.d[7] = 0x00000000;
    m68k.setFlag(cpu.M68k.FLAG_X, true);
    try m68k.memory.write16(0x1000, 0xE217); // ROXR.B #1, D7
    m68k.pc = 0x1000;
    _ = try m68k.step();
    if ((m68k.d[7] & 0xFF) == 0x80) {
        try stdout.print("  ✓ PASS (result=0x{X})\n", .{m68k.d[7] & 0xFF});
        passed += 1;
    } else {
        try stdout.print("  ✗ FAIL (got 0x{X})\n", .{m68k.d[7] & 0xFF});
    }
    
    // Summary
    try stdout.print("\n" ++ "=" ** 50 ++ "\n", .{});
    try stdout.print("Test Results: {} / {} passed ({d:.1}%)\n", .{
        passed, total, @as(f64, @floatFromInt(passed)) / @as(f64, @floatFromInt(total)) * 100.0
    });
    
    if (passed == total) {
        try stdout.print("\n🎉 All shift/rotate tests passed!\n", .{});
    } else {
        try stdout.print("\n⚠️  Some tests failed\n", .{});
    }
    
    try stdout.print("\n📊 Implemented Shift/Rotate Instructions:\n", .{});
    try stdout.print("  ✓ ASL - Arithmetic Shift Left\n", .{});
    try stdout.print("  ✓ ASR - Arithmetic Shift Right (sign extend)\n", .{});
    try stdout.print("  ✓ LSL - Logical Shift Left\n", .{});
    try stdout.print("  ✓ LSR - Logical Shift Right\n", .{});
    try stdout.print("  ✓ ROL - Rotate Left\n", .{});
    try stdout.print("  ✓ ROR - Rotate Right\n", .{});
    try stdout.print("  ✓ ROXL - Rotate Left with Extend\n", .{});
    try stdout.print("  ✓ ROXR - Rotate Right with Extend\n", .{});
}
