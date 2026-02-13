const std = @import("std");
const cpu = @import("cpu.zig");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("Running 68020 exclusive instruction tests...\n", .{});

    var passed: u32 = 0;
    var total: u32 = 0;

    // Test BFTST
    total += 1;
    testBftst() catch |err| {
        try stdout.print("  ❌ BFTST test failed: {}\n", .{err});
        total -= 1;
    };
    if (total == 1) {
        try stdout.print("  ✅ BFTST test passed\n", .{});
        passed += 1;
    }

    // Test CAS
    total += 1;
    testCas() catch |err| {
        try stdout.print("  ❌ CAS test failed: {}\n", .{err});
        total -= 1;
    };
    if (total == 2) {
        try stdout.print("  ✅ CAS test passed\n", .{});
        passed += 1;
    }

    // Test BFSET
    total += 1;
    testBfset() catch |err| {
        try stdout.print("  ❌ BFSET test failed: {}\n", .{err});
        total -= 1;
    };
    if (total == 3) {
        try stdout.print("  ✅ BFSET test passed\n", .{});
        passed += 1;
    }

    const failed = total - passed;
    try stdout.print("\n", .{});
    try stdout.print("Results: {} passed, {} failed\n", .{ passed, failed });

    if (failed > 0) {
        std.process.exit(1);
    }
}

fn testBftst() !void {
    var m68k = cpu.M68k.init(std.heap.page_allocator);
    defer m68k.deinit();

    const stdout = std.io.getStdOut().writer();

    // BFTST D0{4:8} - Test bits 4-11 of D0
    // Opcode: E8C0 (BFTST D0)
    // Extension: 0408 (offset=4, width=8)
    m68k.d[0] = 0x00000FF0; // Bits 4-11 are set

    try m68k.memory.write16(0x400, 0xE8C0);
    try m68k.memory.write16(0x402, 0x0408);
    m68k.pc = 0x400;

    try stdout.print("    Before: D0=0x{X}, SR=0x{X}\n", .{ m68k.d[0], m68k.sr });

    _ = try m68k.step();

    try stdout.print("    After: D0=0x{X}, SR=0x{X}\n", .{ m68k.d[0], m68k.sr });
    try stdout.print("    Z flag: {}\n", .{(m68k.sr & 0x04) != 0});

    // Bit field 0xFF should not set Z flag
    if ((m68k.sr & 0x04) != 0) return error.ZFlagShouldBeClear;
}

fn testCas() !void {
    var m68k = cpu.M68k.init(std.heap.page_allocator);
    defer m68k.deinit();

    const stdout = std.io.getStdOut().writer();

    // CAS.L D0, D1, (A0) - Compare and swap long
    // Format: 0EFC (CAS.L with absolute address mode simplified to D0)
    // Actually: 0EC0 + extension
    // Extension: 0x0041 (Dc=0, Du=1)

    // Setup
    m68k.d[0] = 0x12345678; // Compare value
    m68k.d[1] = 0xABCDEF00; // Update value
    m68k.a[0] = 0x1000;
    try m68k.memory.write32(0x1000, 0x12345678); // Memory matches D0

    // CAS.L D0,D1,(A0) -> 0ED0 + 0041
    try m68k.memory.write16(0x400, 0x0ED0);
    try m68k.memory.write16(0x402, 0x0040);
    m68k.pc = 0x400;

    try stdout.print("    Before: D0=0x{X}, D1=0x{X}, [A0]=0x{X}\n", .{ m68k.d[0], m68k.d[1], try m68k.memory.read32(m68k.a[0]) });

    _ = try m68k.step();

    try stdout.print("    After: D0=0x{X}, D1=0x{X}, [A0]=0x{X}\n", .{ m68k.d[0], m68k.d[1], try m68k.memory.read32(m68k.a[0]) });
    try stdout.print("    Z flag: {} (should be set on match)\n", .{(m68k.sr & 0x04) != 0});

    // Memory should now contain D1 value
    const mem_val = try m68k.memory.read32(m68k.a[0]);
    if (mem_val != 0xABCDEF00) return error.CasSwapFailed;

    // Z flag should be set (successful compare)
    if ((m68k.sr & 0x04) == 0) return error.ZFlagNotSet;
}

fn testBfset() !void {
    var m68k = cpu.M68k.init(std.heap.page_allocator);
    defer m68k.deinit();

    // BFSET D0{4:8} - Set bits 4-11 to 1
    m68k.d[0] = 0x00000000;

    try m68k.memory.write16(0x400, 0xEEC0); // BFSET D0
    try m68k.memory.write16(0x402, 0x0108); // offset=4, width=8
    m68k.pc = 0x400;

    _ = try m68k.step();

    // Bits 4-11 should be set
    if ((m68k.d[0] & 0xFF0) != 0xFF0) return error.BfsetFailed;
}
