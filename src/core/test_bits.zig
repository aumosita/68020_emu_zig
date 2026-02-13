const std = @import("std");
const cpu = @import("cpu.zig");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    
    try stdout.print("Motorola 68020 Emulator - Bit Operation Test Suite\n", .{});
    try stdout.print("====================================================\n\n", .{});
    
    var m68k = cpu.M68k.init(std.heap.page_allocator);
    defer m68k.deinit();
    
    var passed: u32 = 0;
    var total: u32 = 0;
    
    // Test BTST (Bit Test)
    total += 1;
    try stdout.print("Test {}: BTST #7, D0 (test bit 7 of 0x80)\n", .{total});
    m68k.d[0] = 0x00000080;
    try m68k.memory.write16(0x1000, 0x0800); // BTST #imm, D0
    try m68k.memory.write16(0x1002, 0x0007); // bit number 7
    m68k.pc = 0x1000;
    _ = try m68k.step();
    if (!m68k.getFlag(cpu.M68k.FLAG_Z)) { // Z=0 means bit is set
        try stdout.print("  ✓ PASS (bit 7 is set, Z=0)\n", .{});
        passed += 1;
    } else {
        try stdout.print("  ✗ FAIL (Z={})\n", .{m68k.getFlag(cpu.M68k.FLAG_Z)});
    }
    
    // Test BTST with clear bit
    total += 1;
    try stdout.print("\nTest {}: BTST #6, D1 (test bit 6 of 0x80)\n", .{total});
    m68k.d[1] = 0x00000080;
    try m68k.memory.write16(0x1000, 0x0801); // BTST #imm, D1
    try m68k.memory.write16(0x1002, 0x0006); // bit number 6
    m68k.pc = 0x1000;
    _ = try m68k.step();
    if (m68k.getFlag(cpu.M68k.FLAG_Z)) { // Z=1 means bit is clear
        try stdout.print("  ✓ PASS (bit 6 is clear, Z=1)\n", .{});
        passed += 1;
    } else {
        try stdout.print("  ✗ FAIL (Z={})\n", .{m68k.getFlag(cpu.M68k.FLAG_Z)});
    }
    
    // Test BSET (Bit Set)
    total += 1;
    try stdout.print("\nTest {}: BSET #5, D2 (set bit 5 of 0x00)\n", .{total});
    m68k.d[2] = 0x00000000;
    try m68k.memory.write16(0x1000, 0x08C2); // BSET #imm, D2
    try m68k.memory.write16(0x1002, 0x0005); // bit number 5
    m68k.pc = 0x1000;
    _ = try m68k.step();
    if (m68k.d[2] == 0x00000020 and m68k.getFlag(cpu.M68k.FLAG_Z)) { // Z=1 before (was clear)
        try stdout.print("  ✓ PASS (result=0x{X}, Z=1)\n", .{m68k.d[2]});
        passed += 1;
    } else {
        try stdout.print("  ✗ FAIL (got 0x{X}, Z={})\n", .{m68k.d[2], m68k.getFlag(cpu.M68k.FLAG_Z)});
    }
    
    // Test BCLR (Bit Clear)
    total += 1;
    try stdout.print("\nTest {}: BCLR #4, D3 (clear bit 4 of 0xFF)\n", .{total});
    m68k.d[3] = 0x000000FF;
    try m68k.memory.write16(0x1000, 0x0883); // BCLR #imm, D3
    try m68k.memory.write16(0x1002, 0x0004); // bit number 4
    m68k.pc = 0x1000;
    _ = try m68k.step();
    if (m68k.d[3] == 0x000000EF and !m68k.getFlag(cpu.M68k.FLAG_Z)) { // Z=0 before (was set)
        try stdout.print("  ✓ PASS (result=0x{X}, Z=0)\n", .{m68k.d[3]});
        passed += 1;
    } else {
        try stdout.print("  ✗ FAIL (got 0x{X}, Z={})\n", .{m68k.d[3], m68k.getFlag(cpu.M68k.FLAG_Z)});
    }
    
    // Test BCHG (Bit Change/Toggle)
    total += 1;
    try stdout.print("\nTest {}: BCHG #3, D4 (toggle bit 3 of 0x00)\n", .{total});
    m68k.d[4] = 0x00000000;
    try m68k.memory.write16(0x1000, 0x0844); // BCHG #imm, D4
    try m68k.memory.write16(0x1002, 0x0003); // bit number 3
    m68k.pc = 0x1000;
    _ = try m68k.step();
    if (m68k.d[4] == 0x00000008 and m68k.getFlag(cpu.M68k.FLAG_Z)) {
        try stdout.print("  ✓ PASS (result=0x{X}, Z=1)\n", .{m68k.d[4]});
        passed += 1;
    } else {
        try stdout.print("  ✗ FAIL (got 0x{X}, Z={})\n", .{m68k.d[4], m68k.getFlag(cpu.M68k.FLAG_Z)});
    }
    
    // Test BCHG again (toggle back)
    total += 1;
    try stdout.print("\nTest {}: BCHG #3, D4 again (toggle bit 3 of 0x08)\n", .{total});
    try m68k.memory.write16(0x1000, 0x0844); // BCHG #imm, D4
    try m68k.memory.write16(0x1002, 0x0003); // bit number 3
    m68k.pc = 0x1000;
    _ = try m68k.step();
    if (m68k.d[4] == 0x00000000 and !m68k.getFlag(cpu.M68k.FLAG_Z)) {
        try stdout.print("  ✓ PASS (result=0x{X}, Z=0)\n", .{m68k.d[4]});
        passed += 1;
    } else {
        try stdout.print("  ✗ FAIL (got 0x{X}, Z={})\n", .{m68k.d[4], m68k.getFlag(cpu.M68k.FLAG_Z)});
    }
    
    // Test BTST with register
    total += 1;
    try stdout.print("\nTest {}: BTST D6, D5 (test bit from register)\n", .{total});
    m68k.d[5] = 0x000000AA; // 10101010
    m68k.d[6] = 0x00000001; // bit number 1
    try m68k.memory.write16(0x1000, 0x0D05); // BTST D6, D5 (0000 110 1 00 000 101)
    m68k.pc = 0x1000;
    _ = try m68k.step();
    if (!m68k.getFlag(cpu.M68k.FLAG_Z)) { // bit 1 of 0xAA is set
        try stdout.print("  ✓ PASS (bit 1 is set, Z=0)\n", .{});
        passed += 1;
    } else {
        try stdout.print("  ✗ FAIL (Z={})\n", .{m68k.getFlag(cpu.M68k.FLAG_Z)});
    }
    
    // Test bit modulo 32
    total += 1;
    try stdout.print("\nTest {}: BSET #40, D7 (bit 40 mod 32 = bit 8)\n", .{total});
    m68k.d[7] = 0x00000000;
    try m68k.memory.write16(0x1000, 0x08C7); // BSET #imm, D7
    try m68k.memory.write16(0x1002, 0x0028); // bit number 40 (0x28)
    m68k.pc = 0x1000;
    _ = try m68k.step();
    if (m68k.d[7] == 0x00000100) { // bit 8 set
        try stdout.print("  ✓ PASS (bit 8 set, result=0x{X})\n", .{m68k.d[7]});
        passed += 1;
    } else {
        try stdout.print("  ✗ FAIL (got 0x{X})\n", .{m68k.d[7]});
    }
    
    // Summary
    try stdout.print("\n" ++ "=" ** 50 ++ "\n", .{});
    try stdout.print("Test Results: {} / {} passed ({d:.1}%)\n", .{
        passed, total, @as(f64, @floatFromInt(passed)) / @as(f64, @floatFromInt(total)) * 100.0
    });
    
    if (passed == total) {
        try stdout.print("\n🎉 All bit operation tests passed!\n", .{});
    } else {
        try stdout.print("\n⚠️  Some tests failed\n", .{});
    }
    
    try stdout.print("\n📊 Implemented Bit Operations:\n", .{});
    try stdout.print("  ✓ BTST - Bit Test (sets Z flag)\n", .{});
    try stdout.print("  ✓ BSET - Bit Set (test then set)\n", .{});
    try stdout.print("  ✓ BCLR - Bit Clear (test then clear)\n", .{});
    try stdout.print("  ✓ BCHG - Bit Change/Toggle (test then flip)\n", .{});
    try stdout.print("\n  Features:\n", .{});
    try stdout.print("    - Immediate bit number (#0-31)\n", .{});
    try stdout.print("    - Register bit number (Dn)\n", .{});
    try stdout.print("    - Modulo 32 for register operands\n", .{});
    try stdout.print("    - Modulo 8 for memory operands\n", .{});
    try stdout.print("    - Z flag reflects bit state BEFORE operation\n", .{});
}
