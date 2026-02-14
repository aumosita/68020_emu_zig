const std = @import("std");
const cpu = @import("../../src/core/cpu.zig");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Running Phase 1 tests (JMP, BSR, DBcc, Scc)...\n", .{});
    
    var passed: u32 = 0;
    var total: u32 = 0;
    
    // Test JMP
    total += 1;
    testJmp() catch |err| {
        try stdout.print("  ❌ JMP test failed: {}\n", .{err});
    };
    if (total == 1) {
        try stdout.print("  ✅ JMP test passed\n", .{});
        passed += 1;
    }
    
    // Test BSR
    total += 1;
    testBsr() catch |err| {
        try stdout.print("  ❌ BSR test failed: {}\n", .{err});
        total -= 1;
    };
    if (total == 2) {
        try stdout.print("  ✅ BSR test passed\n", .{});
        passed += 1;
    }
    
    // Test DBcc
    total += 1;
    testDbcc() catch |err| {
        try stdout.print("  ❌ DBcc test failed: {}\n", .{err});
        total -= 1;
    };
    if (total == 3) {
        try stdout.print("  ✅ DBcc test passed\n", .{});
        passed += 1;
    }
    
    // Test Scc
    total += 1;
    testScc() catch |err| {
        try stdout.print("  ❌ Scc test failed: {}\n", .{err});
        total -= 1;
    };
    if (total == 4) {
        try stdout.print("  ✅ Scc test passed\n", .{});
        passed += 1;
    }
    
    // Test complete loop
    total += 1;
    testCompleteLoop() catch |err| {
        try stdout.print("  ❌ Complete loop test failed: {}\n", .{err});
        total -= 1;
    };
    if (total == 5) {
        try stdout.print("  ✅ Complete loop test passed\n", .{});
        passed += 1;
    }
    
    const failed = total - passed;
    try stdout.print("\n", .{});
    try stdout.print("Results: {} passed, {} failed\n", .{passed, failed});
    
    if (failed > 0) {
        std.process.exit(1);
    }
}

fn testJmp() !void {
    var m68k = cpu.M68k.init(std.heap.page_allocator);
    defer m68k.deinit();
    
    // JMP $1000  -> 4EF9 0000 1000 (JMP (xxx).L)
    try m68k.memory.write16(0x400, 0x4EF9); // JMP (xxx).L
    try m68k.memory.write16(0x402, 0x0000);
    try m68k.memory.write16(0x404, 0x1000);
    
    m68k.pc = 0x400;
    _ = try m68k.step();
    
    // PC should jump to $1000
    if (m68k.pc != 0x1000) return error.WrongPC;
}

fn testBsr() !void {
    var m68k = cpu.M68k.init(std.heap.page_allocator);
    defer m68k.deinit();
    
    // BSR.B $10  -> 6110 (displacement = +16)
    try m68k.memory.write16(0x400, 0x6110);
    
    m68k.pc = 0x400;
    m68k.a[7] = 0x2000; // Set stack pointer
    
    _ = try m68k.step();
    
    // PC should be at $400 + 2 + $10 = $412
    if (m68k.pc != 0x412) return error.WrongPC;
    
    // Return address ($402) should be pushed on stack
    if (m68k.a[7] != 0x1FFC) return error.WrongStackPointer;
    const return_addr = try m68k.memory.read32(m68k.a[7]);
    if (return_addr != 0x402) return error.WrongReturnAddress;
}

fn testDbcc() !void {
    var m68k = cpu.M68k.init(std.heap.page_allocator);
    defer m68k.deinit();
    
    // DBRA D0, -10  -> 51C8 FFF6
    try m68k.memory.write16(0x400, 0x51C8); // DBRA D0
    try m68k.memory.write16(0x402, 0xFFF6); // displacement = -10
    
    m68k.pc = 0x400;
    m68k.d[0] = 3; // Counter = 3
    
    // First iteration: counter = 3 -> 2, should branch
    _ = try m68k.step();
    if ((m68k.d[0] & 0xFFFF) != 2) return error.WrongCounter;
    if (m68k.pc != 0x3F8) return error.WrongPC; // 0x400 + 2 + (-10)
    
    // Second iteration: counter = 2 -> 1, should branch
    m68k.pc = 0x400;
    _ = try m68k.step();
    if ((m68k.d[0] & 0xFFFF) != 1) return error.WrongCounter;
    if (m68k.pc != 0x3F8) return error.WrongPC;
    
    // Third iteration: counter = 1 -> 0, should branch
    m68k.pc = 0x400;
    _ = try m68k.step();
    if ((m68k.d[0] & 0xFFFF) != 0) return error.WrongCounter;
    if (m68k.pc != 0x3F8) return error.WrongPC;
    
    // Fourth iteration: counter = 0 -> -1, should NOT branch
    m68k.pc = 0x400;
    _ = try m68k.step();
    if ((m68k.d[0] & 0xFFFF) != 0xFFFF) return error.WrongCounter;
    if (m68k.pc != 0x404) return error.WrongPC; // Should fall through
}

fn testScc() !void {
    var m68k = cpu.M68k.init(std.heap.page_allocator);
    defer m68k.deinit();
    
    // SEQ D0  -> 57C0 (Set if Equal, i.e., Z flag set)
    try m68k.memory.write16(0x400, 0x57C0);
    
    m68k.pc = 0x400;
    m68k.d[0] = 0x12345678;
    
    // Z flag = 0, condition false -> D0.B should be 0x00
    m68k.sr &= ~@as(u16, 0x04); // Clear Z flag
    _ = try m68k.step();
    if (m68k.d[0] != 0x12345600) return error.WrongValue;
    
    // Z flag = 1, condition true -> D0.B should be 0xFF
    m68k.pc = 0x400;
    m68k.sr |= 0x04; // Set Z flag
    _ = try m68k.step();
    if (m68k.d[0] != 0x123456FF) return error.WrongValue;
}

fn testCompleteLoop() !void {
    var m68k = cpu.M68k.init(std.heap.page_allocator);
    defer m68k.deinit();
    
    // Simple loop:
    //   MOVE.W #5, D0       ; Counter
    //   MOVEQ #0, D1        ; Accumulator
    // loop:
    //   ADDQ.W #1, D1
    //   DBRA D0, loop
    
    try m68k.memory.write16(0x400, 0x303C); // MOVE.W #5, D0
    try m68k.memory.write16(0x402, 0x0005);
    try m68k.memory.write16(0x404, 0x7200); // MOVEQ #0, D1
    try m68k.memory.write16(0x406, 0x5241); // ADDQ.W #1, D1
    try m68k.memory.write16(0x408, 0x51C8); // DBRA D0, -6
    try m68k.memory.write16(0x40A, 0xFFFA); // displacement = -6
    
    m68k.pc = 0x400;
    
    // Execute MOVE.W #5, D0
    _ = try m68k.step();
    if ((m68k.d[0] & 0xFFFF) != 5) return error.WrongValue;
    
    // Execute MOVEQ #0, D1
    _ = try m68k.step();
    if (m68k.d[1] != 0) return error.WrongValue;
    
    // Execute loop 6 times
    var i: u32 = 0;
    while (i < 6) : (i += 1) {
        // ADDQ.W #1, D1
        _ = try m68k.step();
        
        // DBRA D0, loop
        _ = try m68k.step();
    }
    
    // D1 should be 6
    if ((m68k.d[1] & 0xFFFF) != 6) return error.WrongValue;
    
    // D0 should be -1 (0xFFFF)
    if ((m68k.d[0] & 0xFFFF) != 0xFFFF) return error.WrongValue;
    
    // PC should be at 0x40C (after the loop)
    if (m68k.pc != 0x40C) return error.WrongPC;
}
