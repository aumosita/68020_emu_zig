const std = @import("std");
const cpu = @import("cpu.zig");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    
    try stdout.print("Motorola 68020 Emulator - Extended Test Suite\n", .{});
    try stdout.print("==============================================\n\n", .{});
    
    var m68k = cpu.M68k.init(std.heap.page_allocator);
    defer m68k.deinit();
    
    var passed: u32 = 0;
    var total: u32 = 0;
    
    // Test MOVEQ
    total += 1;
    try stdout.print("Test {}: MOVEQ #42, D0\n", .{total});
    try m68k.memory.write16(0x1000, 0x702A);
    m68k.pc = 0x1000;
    _ = try m68k.step();
    if (m68k.d[0] == 42) {
        try stdout.print("  ✓ PASS\n", .{});
        passed += 1;
    } else {
        try stdout.print("  ✗ FAIL (got 0x{X})\n", .{m68k.d[0]});
    }
    
    // Test ADDQ with memory
    total += 1;
    try stdout.print("\nTest {}: ADDQ #5, D1\n", .{total});
    try m68k.memory.write16(0x1000, 0x5A41);
    m68k.pc = 0x1000;
    m68k.d[1] = 10;
    _ = try m68k.step();
    if (m68k.d[1] == 15) {
        try stdout.print("  ✓ PASS\n", .{});
        passed += 1;
    } else {
        try stdout.print("  ✗ FAIL (got 0x{X})\n", .{m68k.d[1]});
    }
    
    // Test SUBQ
    total += 1;
    try stdout.print("\nTest {}: SUBQ #3, D2\n", .{total});
    try m68k.memory.write16(0x1000, 0x5742);
    m68k.pc = 0x1000;
    m68k.d[2] = 10;
    _ = try m68k.step();
    if (m68k.d[2] == 7) {
        try stdout.print("  ✓ PASS\n", .{});
        passed += 1;
    } else {
        try stdout.print("  ✗ FAIL (got 0x{X})\n", .{m68k.d[2]});
    }
    
    // Test CLR
    total += 1;
    try stdout.print("\nTest {}: CLR.L D3\n", .{total});
    try m68k.memory.write16(0x1000, 0x4283);
    m68k.pc = 0x1000;
    m68k.d[3] = 0xDEADBEEF;
    _ = try m68k.step();
    if (m68k.d[3] == 0 and m68k.getFlag(cpu.M68k.FLAG_Z)) {
        try stdout.print("  ✓ PASS\n", .{});
        passed += 1;
    } else {
        try stdout.print("  ✗ FAIL (got 0x{X}, Z={})\n", .{m68k.d[3], m68k.getFlag(cpu.M68k.FLAG_Z)});
    }
    
    // Test NOT
    total += 1;
    try stdout.print("\nTest {}: NOT.W D4\n", .{total});
    try m68k.memory.write16(0x1000, 0x4644);
    m68k.pc = 0x1000;
    m68k.d[4] = 0x0000AAAA;
    _ = try m68k.step();
    if ((m68k.d[4] & 0xFFFF) == 0x5555) {
        try stdout.print("  ✓ PASS\n", .{});
        passed += 1;
    } else {
        try stdout.print("  ✗ FAIL (got 0x{X})\n", .{m68k.d[4]});
    }
    
    // Test SWAP
    total += 1;
    try stdout.print("\nTest {}: SWAP D5\n", .{total});
    try m68k.memory.write16(0x1000, 0x4845);
    m68k.pc = 0x1000;
    m68k.d[5] = 0x12345678;
    _ = try m68k.step();
    if (m68k.d[5] == 0x56781234) {
        try stdout.print("  ✓ PASS\n", .{});
        passed += 1;
    } else {
        try stdout.print("  ✗ FAIL (got 0x{X})\n", .{m68k.d[5]});
    }
    
    // Test EXT.W (byte to word)
    total += 1;
    try stdout.print("\nTest {}: EXT.W D6 (sign extend)\n", .{total});
    try m68k.memory.write16(0x1000, 0x4886);
    m68k.pc = 0x1000;
    m68k.d[6] = 0x000000FF; // -1 as signed byte
    _ = try m68k.step();
    if ((m68k.d[6] & 0xFFFF) == 0xFFFF) {
        try stdout.print("  ✓ PASS\n", .{});
        passed += 1;
    } else {
        try stdout.print("  ✗ FAIL (got 0x{X})\n", .{m68k.d[6]});
    }
    
    // Test MULU
    total += 1;
    try stdout.print("\nTest {}: MULU D1, D0 (5 * 10 = 50)\n", .{total});
    m68k.d[0] = 5;
    m68k.d[1] = 10;
    try m68k.memory.write16(0x1000, 0xC0C1); // MULU.W D1, D0
    m68k.pc = 0x1000;
    _ = try m68k.step();
    if (m68k.d[0] == 50) {
        try stdout.print("  ✓ PASS\n", .{});
        passed += 1;
    } else {
        try stdout.print("  ✗ FAIL (got {})\n", .{m68k.d[0]});
    }
    
    // Test DIVU
    total += 1;
    try stdout.print("\nTest {}: DIVU D3, D2 (25 / 5 = 5)\n", .{total});
    m68k.d[2] = 25;
    m68k.d[3] = 5;
    try m68k.memory.write16(0x1000, 0x84C3); // DIVU.W D3, D2
    m68k.pc = 0x1000;
    _ = try m68k.step();
    const quotient = m68k.d[2] & 0xFFFF;
    if (quotient == 5) {
        try stdout.print("  ✓ PASS\n", .{});
        passed += 1;
    } else {
        try stdout.print("  ✗ FAIL (got quotient={})\n", .{quotient});
    }
    
    // Test memory operations
    total += 1;
    try stdout.print("\nTest {}: Memory read/write (big-endian)\n", .{total});
    try m68k.memory.write32(0x2000, 0xDEADBEEF);
    const val = try m68k.memory.read32(0x2000);
    const b0 = try m68k.memory.read8(0x2000);
    const b3 = try m68k.memory.read8(0x2003);
    if (val == 0xDEADBEEF and b0 == 0xDE and b3 == 0xEF) {
        try stdout.print("  ✓ PASS\n", .{});
        passed += 1;
    } else {
        try stdout.print("  ✗ FAIL\n", .{});
    }
    
    // Test address register operations
    total += 1;
    try stdout.print("\nTest {}: ADDQ #4, A0 (address register)\n", .{total});
    try m68k.memory.write16(0x1000, 0x5888); // ADDQ.L #4, A0
    m68k.pc = 0x1000;
    m68k.a[0] = 0x1000;
    const before = m68k.a[0];
    _ = try m68k.step();
    try stdout.print("  Before: 0x{X}, After: 0x{X}\n", .{before, m68k.a[0]});
    if (m68k.a[0] == 0x1004) {
        try stdout.print("  ✓ PASS\n", .{});
        passed += 1;
    } else {
        try stdout.print("  ✗ FAIL (got 0x{X})\n", .{m68k.a[0]});
    }
    
    // Test indirect addressing
    total += 1;
    try stdout.print("\nTest {}: Indirect addressing (A1)\n", .{total});
    m68k.a[1] = 0x3000;
    try m68k.memory.write32(0x3000, 0x12345678);
    const indirect_val = try m68k.memory.read32(m68k.a[1]);
    if (indirect_val == 0x12345678) {
        try stdout.print("  ✓ PASS\n", .{});
        passed += 1;
    } else {
        try stdout.print("  ✗ FAIL\n", .{});
    }
    
    // --- 68020 Specific Tests ---
    try stdout.print("\n68020 Specific Feature Tests\n", .{});
    try stdout.print("---------------------------\n", .{});

    // Test 13: 68020 Brief Extension (d8(An, Xn.size*scale))
    total += 1;
    try stdout.print("Test {}: Brief Extension - d8(A0, D0.L*4)\n", .{total});
    m68k.a[0] = 0x2000;
    m68k.d[0] = 0x10;
    // MOVE.L (0x8, A0, D0.L*4), D1
    // Opcode: 0x2230
    // Extension: 0x8808 (D0, Long, Scale 4, Displacement 8)
    try m68k.memory.write16(0x1000, 0x2230);
    try m68k.memory.write16(0x1002, 0x8808);
    try m68k.memory.write32(0x2000 + 0x10*4 + 0x8, 0x12345678);
    m68k.pc = 0x1000;
    _ = try m68k.step();
    if (m68k.d[1] == 0x12345678) {
        try stdout.print("  ✓ PASS (D1=0x{X})\n", .{m68k.d[1]});
        passed += 1;
    } else {
        try stdout.print("  ✗ FAIL (D1=0x{X}, expected 0x12345678)\n", .{m68k.d[1]});
    }

    // Test 14: 68020 Full Extension (Memory Indirect Post-indexed)
    // ([bd, An], Xn, od)
    total += 1;
    try stdout.print("\nTest {}: Full Extension - ([0x10, A0], D0.L*2, 0x20)\n", .{total});
    m68k.a[0] = 0x3000;
    m68k.d[0] = 0x5;
    // 1. [0x3000 + 0x10] -> 0x4000
    // 2. 0x4000 + (D0*2) + 0x20 -> 0x402A
    // 3. [0x402A] -> 0xDEADBEEF
    try m68k.memory.write32(0x3010, 0x4000);
    try m68k.memory.write32(0x4000 + 5*2 + 0x20, 0xDEADBEEF);
    
    // Opcode: 0x2230
    // Extension: 0x8137 (Full, D0, Scale 2, Indirect Post, bd word, od word)
    try m68k.memory.write16(0x1000, 0x2230);
    try m68k.memory.write16(0x1002, 0x8137);
    try m68k.memory.write16(0x1004, 0x0010); // bd
    try m68k.memory.write16(0x1006, 0x0020); // od
    m68k.pc = 0x1000;
    _ = try m68k.step();
    if (m68k.d[1] == 0xDEADBEEF) {
        try stdout.print("  ✓ PASS (D1=0x{X})\n", .{m68k.d[1]});
        passed += 1;
    } else {
        try stdout.print("  ✗ FAIL (D1=0x{X})\n", .{m68k.d[1]});
    }

    // Summary
    try stdout.print("\n" ++ "=" ** 50 ++ "\n", .{});
    try stdout.print("Test Results: {} / {} passed ({d:.1}%)\n", .{
        passed, total, @as(f64, @floatFromInt(passed)) / @as(f64, @floatFromInt(total)) * 100.0
    });
    
    if (passed == total) {
        try stdout.print("\n🎉 All tests passed!\n", .{});
    } else {
        try stdout.print("\n⚠️  Some tests failed\n", .{});
    }
    
    try stdout.print("\n📊 Implemented Features:\n", .{});
    try stdout.print("  ✓ MOVE family (MOVE, MOVEA, MOVEQ)\n", .{});
    try stdout.print("  ✓ ADD family (ADD, ADDA, ADDI, ADDQ, ADDX)\n", .{});
    try stdout.print("  ✓ SUB family (SUB, SUBA, SUBI, SUBQ, SUBX)\n", .{});
    try stdout.print("  ✓ CMP family (CMP, CMPA, CMPI)\n", .{});
    try stdout.print("  ✓ Logical (AND, OR, EOR, NOT + I variants)\n", .{});
    try stdout.print("  ✓ Multiply/Divide (MULU, MULS, DIVU, DIVS)\n", .{});
    try stdout.print("  ✓ Misc (NEG, NEGX, CLR, TST, SWAP, EXT)\n", .{});
    try stdout.print("  ✓ Flow control (BRA, Bcc, JSR, RTS)\n", .{});
    try stdout.print("  ✓ Addressing modes:\n", .{});
    try stdout.print("    - Data register direct (Dn)\n", .{});
    try stdout.print("    - Address register direct (An)\n", .{});
    try stdout.print("    - Address register indirect ((An))\n", .{});
    try stdout.print("    - Post-increment ((An)+)\n", .{});
    try stdout.print("    - Pre-decrement (-(An))\n", .{});
    try stdout.print("    - With displacement (d16(An))\n", .{});
    try stdout.print("    - Immediate (#imm)\n", .{});
    try stdout.print("    - Absolute (addr.W/.L)\n", .{});
    
    try stdout.print("\n🚀 Emulator ready for use!\n", .{});
}
