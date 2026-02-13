const std = @import("std");
const cpu = @import("cpu.zig");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Running BCD tests (ABCD, SBCD, NBCD)...\n", .{});
    
    var passed: u32 = 0;
    var total: u32 = 0;
    
    // Test ABCD
    total += 1;
    testAbcd() catch |err| {
        try stdout.print("  ❌ ABCD test failed: {}\n", .{err});
        total -= 1;
    };
    if (total == 1) {
        try stdout.print("  ✅ ABCD test passed\n", .{});
        passed += 1;
    }
    
    // Test SBCD
    total += 1;
    testSbcd() catch |err| {
        try stdout.print("  ❌ SBCD test failed: {}\n", .{err});
        total -= 1;
    };
    if (total == 2) {
        try stdout.print("  ✅ SBCD test passed\n", .{});
        passed += 1;
    }
    
    // Test NBCD
    total += 1;
    testNbcd() catch |err| {
        try stdout.print("  ❌ NBCD test failed: {}\n", .{err});
        total -= 1;
    };
    if (total == 3) {
        try stdout.print("  ✅ NBCD test passed\n", .{});
        passed += 1;
    }
    
    const failed = total - passed;
    try stdout.print("\n", .{});
    try stdout.print("Results: {} passed, {} failed\n", .{passed, failed});
    
    if (failed > 0) {
        std.process.exit(1);
    }
}

fn testAbcd() !void {
    var m68k = cpu.M68k.init(std.heap.page_allocator);
    defer m68k.deinit();
    
    const stdout = std.io.getStdOut().writer();
    
    // ABCD D1, D0 - Add BCD
    // Format: 1100 Rx 1 00 0 RM Ry
    // Rx=0 (dest), RM=0 (data reg), Ry=1 (source)
    // 1100 000 1 00 0 0 001 = C101
    try m68k.memory.write16(0x400, 0xC101);
    const opcode = try m68k.memory.read16(0x400);
    try stdout.print("    Opcode check:\n", .{});
    try stdout.print("      Raw: 0x{X:0>4}\n", .{opcode});
    try stdout.print("      & 0x1F0: 0x{X:0>3}\n", .{opcode & 0x1F0});
    try stdout.print("      Rx (dest): {}\n", .{(opcode >> 9) & 0x7});
    try stdout.print("      Ry (source): {}\n", .{opcode & 0x7});
    
    // Test: 0x25 + 0x17 = 0x42 (BCD)
    m68k.d[0] = 0x25; // Destination
    m68k.d[1] = 0x17; // Source
    m68k.sr &= ~@as(u16, 0x10); // Clear X flag
    
    m68k.pc = 0x400;
    
    try stdout.print("    Before: D0=0x{X}, D1=0x{X}\n", .{m68k.d[0], m68k.d[1]});
    
    _ = try m68k.step();
    
    try stdout.print("    After: D0=0x{X}, D1=0x{X}\n", .{m68k.d[0], m68k.d[1]});
    try stdout.print("    Expected D0 low byte: 0x42, got: 0x{X:0>2}\n", .{m68k.d[0] & 0xFF});
    
    // Result should be 0x42
    const result = m68k.d[0] & 0xFF;
    if (result != 0x42) return error.WrongResult;
}

fn testSbcd() !void {
    var m68k = cpu.M68k.init(std.heap.page_allocator);
    defer m68k.deinit();
    
    // SBCD D1, D0 - Subtract BCD
    // Format: 1000 Rx 1 00 0 RM Ry
    // Rx=0, RM=0, Ry=1
    // 1000 000 1 00 0 0 001 = 8101
    m68k.d[0] = 0x42; // Destination
    m68k.d[1] = 0x17; // Source
    m68k.sr &= ~@as(u16, 0x10); // Clear X flag
    
    // SBCD D1, D0 -> 8101
    try m68k.memory.write16(0x400, 0x8101);
    m68k.pc = 0x400;
    
    _ = try m68k.step();
    
    // Result should be 0x25 (0x42 - 0x17)
    const result = m68k.d[0] & 0xFF;
    if (result != 0x25) return error.WrongResult;
}

fn testNbcd() !void {
    var m68k = cpu.M68k.init(std.heap.page_allocator);
    defer m68k.deinit();
    
    const stdout = std.io.getStdOut().writer();
    
    // NBCD D0 - Negate BCD
    m68k.d[0] = 0x25;
    m68k.sr &= ~@as(u16, 0x10); // Clear X flag
    
    // NBCD D0 -> 4800
    try m68k.memory.write16(0x400, 0x4800);
    m68k.pc = 0x400;
    
    try stdout.print("    Before: D0=0x{X}\n", .{m68k.d[0]});
    
    _ = try m68k.step();
    
    try stdout.print("    After: D0=0x{X}\n", .{m68k.d[0]});
    try stdout.print("    Expected: 0x75, got: 0x{X:0>2}\n", .{m68k.d[0] & 0xFF});
    
    // Result should be 0x75 (100 - 25 in BCD = 75)
    const result = m68k.d[0] & 0xFF;
    if (result != 0x75) return error.WrongResult;
}
