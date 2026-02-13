const std = @import("std");
const cpu = @import("cpu.zig");
const decoder = @import("decoder.zig");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Cycle-Accurate Demo\n", .{});
    try stdout.print("====================\n\n", .{});
    
    var m68k = cpu.M68k.init(std.heap.page_allocator);
    defer m68k.deinit();
    
    // Test 1: MOVEQ #42, D0 (should be 4 cycles)
    try stdout.print("Test 1: MOVEQ #42, D0\n", .{});
    try m68k.memory.write16(0x400, 0x7029); // MOVEQ #41, D0 (0x7029 = %0111 0000 0010 1001)
    m68k.pc = 0x400;
    const cycles1 = try m68k.step();
    try stdout.print("  Cycles: {} (expected 4)\n", .{cycles1});
    try stdout.print("  D0 = 0x{X} (expected 0x29 sign-extended)\n\n", .{m68k.d[0]});
    
    // Test 2: MOVE.L D0, D1 (should be 4 cycles)
    try stdout.print("Test 2: MOVE.L D0, D1\n", .{});
    m68k.d[0] = 0x12345678;
    try m68k.memory.write16(0x402, 0x2200); // MOVE.L D0, D1
    m68k.pc = 0x402;
    const cycles2 = try m68k.step();
    try stdout.print("  Cycles: {} (expected 4)\n", .{cycles2});
    try stdout.print("  D1 = 0x{X} (expected 0x12345678)\n\n", .{m68k.d[1]});
    
    // Test 3: ADD.L D0, D1 (should be 6 cycles for Long)
    try stdout.print("Test 3: ADD.L D0, D1\n", .{});
    m68k.d[0] = 100;
    m68k.d[1] = 200;
    try m68k.memory.write16(0x404, 0xD280); // ADD.L D0, D1
    m68k.pc = 0x404;
    const cycles3 = try m68k.step();
    try stdout.print("  Cycles: {} (expected 6 for ADD.L)\n", .{cycles3});
    try stdout.print("  D1 = {} (expected 300)\n\n", .{m68k.d[1]});
    
    // Summary
    try stdout.print("Summary:\n", .{});
    try stdout.print("  Total cycles executed: {}\n", .{m68k.cycles});
    try stdout.print("  Expected: ~14 cycles\n", .{});
    
    // Show cycle breakdown
    try stdout.print("\nCycle Breakdown:\n", .{});
    try stdout.print("  MOVEQ: {} cycles\n", .{cycles1});
    try stdout.print("  MOVE.L: {} cycles\n", .{cycles2});
    try stdout.print("  ADD.L: {} cycles\n", .{cycles3});
}
