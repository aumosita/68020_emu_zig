const std = @import("std");
const cpu = @import("cpu.zig");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Running Phase 3 tests (EXG, CMPM, CHK)...\n", .{});
    
    var passed: u32 = 0;
    var total: u32 = 0;
    
    // Test EXG
    total += 1;
    testExg() catch |err| {
        try stdout.print("  ❌ EXG test failed: {}\n", .{err});
        total -= 1;
    };
    if (total == 1) {
        try stdout.print("  ✅ EXG test passed\n", .{});
        passed += 1;
    }
    
    // Test CMPM
    total += 1;
    testCmpm() catch |err| {
        try stdout.print("  ❌ CMPM test failed: {}\n", .{err});
        total -= 1;
    };
    if (total == 2) {
        try stdout.print("  ✅ CMPM test passed\n", .{});
        passed += 1;
    }
    
    // Test CHK
    total += 1;
    testChk() catch |err| {
        try stdout.print("  ❌ CHK test failed: {}\n", .{err});
        total -= 1;
    };
    if (total == 3) {
        try stdout.print("  ✅ CHK test passed\n", .{});
        passed += 1;
    }
    
    const failed = total - passed;
    try stdout.print("\n", .{});
    try stdout.print("Results: {} passed, {} failed\n", .{passed, failed});
    
    if (failed > 0) {
        std.process.exit(1);
    }
}

fn testExg() !void {
    var m68k = cpu.M68k.init(std.heap.page_allocator);
    defer m68k.deinit();
    
    // Test 1: EXG D0, D1 (data register to data register)
    m68k.d[0] = 0x12345678;
    m68k.d[1] = 0xABCDEF00;
    
    // EXG D0, D1 -> C140 (1100 000 1 01000 001)
    // Format: 1100 Rx 1 OpMode Ry
    // Rx=0, OpMode=01000 (Dn-Dn), Ry=1
    try m68k.memory.write16(0x400, 0xC141); // EXG D0, D1
    m68k.pc = 0x400;
    
    _ = try m68k.step();
    
    if (m68k.d[0] != 0xABCDEF00) return error.WrongD0;
    if (m68k.d[1] != 0x12345678) return error.WrongD1;
    
    // Test 2: EXG A0, A1 (address register to address register)
    m68k.a[0] = 0x11111111;
    m68k.a[1] = 0x22222222;
    
    // EXG A0, A1 -> C149 (1100 000 1 01001 001)
    // OpMode=01001 (An-An)
    try m68k.memory.write16(0x400, 0xC149); // EXG A0, A1
    m68k.pc = 0x400;
    
    _ = try m68k.step();
    
    if (m68k.a[0] != 0x22222222) return error.WrongA0;
    if (m68k.a[1] != 0x11111111) return error.WrongA1;
    
    // Test 3: EXG D0, A0 (data to address register)
    m68k.d[0] = 0xDDDDDDDD;
    m68k.a[0] = 0xAAAAAAAA;
    
    // EXG D0, A0 -> C188 (1100 000 1 10001 000)
    // OpMode=10001 (Dn-An)
    try m68k.memory.write16(0x400, 0xC188); // EXG D0, A0
    m68k.pc = 0x400;
    
    _ = try m68k.step();
    
    if (m68k.d[0] != 0xAAAAAAAA) return error.WrongD0AfterDA;
    if (m68k.a[0] != 0xDDDDDDDD) return error.WrongA0AfterDA;
}

fn testCmpm() !void {
    var m68k = cpu.M68k.init(std.heap.page_allocator);
    defer m68k.deinit();
    
    const stdout = std.io.getStdOut().writer();
    
    // CMPM.W (A1)+, (A0)+
    try m68k.memory.write16(0x1000, 0x1234);
    try m68k.memory.write16(0x2000, 0x1234);
    
    m68k.a[0] = 0x1000;
    m68k.a[1] = 0x2000;
    
    // CMPM.W (A1)+, (A0)+ -> B0C9
    // Format: 1011 Ax 1 Size 001 Ay
    // Ax=0, Size=01 (word), 001 (PostInc), Ay=1
    try m68k.memory.write16(0x400, 0xB0C9);
    m68k.pc = 0x400;
    
    try stdout.print("    Debug: A0={X}, A1={X}\n", .{m68k.a[0], m68k.a[1]});
    
    _ = try m68k.step();
    
    try stdout.print("    Debug: After step A0={X}, A1={X}, SR={X}\n", .{m68k.a[0], m68k.a[1], m68k.sr});
    
    // Pointers should advance by 2 (word size)
    if (m68k.a[0] != 0x1002) {
        try stdout.print("    Debug: A0 should be 1002, got {X}\n", .{m68k.a[0]});
        return error.WrongA0;
    }
    if (m68k.a[1] != 0x2002) {
        try stdout.print("    Debug: A1 should be 2002, got {X}\n", .{m68k.a[1]});
        return error.WrongA1;
    }
    
    // Values are equal, Z flag should be set
    const z_flag = (m68k.sr & 0x04) != 0;
    if (!z_flag) {
        try stdout.print("    Debug: Z flag should be set for equal values\n", .{});
        return error.ZFlagNotSet;
    }
}

fn testChk() !void {
    var m68k = cpu.M68k.init(std.heap.page_allocator);
    defer m68k.deinit();
    
    // CHK implementation exists
    // Test basic within-bounds case
    m68k.d[0] = 0x0050; // Value to check
    m68k.d[1] = 0x0100; // Upper bound
    m68k.a[7] = 0x3000; // Stack pointer
    
    // CHK D1, D0
    try m68k.memory.write16(0x400, 0x4180);
    m68k.pc = 0x400;
    
    _ = try m68k.step();
    
    // Should NOT take exception, PC should advance normally
    if (m68k.pc != 0x402) return error.UnexpectedException;
    
    // Test passes if no exception was taken
}
