const std = @import("std");

const cpu = @import("cpu.zig");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    
    try stdout.print("Motorola 68020 Emulator Test\n", .{});
    try stdout.print("============================\n\n", .{});
    
    // Create CPU instance with custom memory size
    var m68k = cpu.M68k.initWithConfig(std.heap.page_allocator, .{
        .size = 16 * 1024 * 1024  // 16MB
    });
    defer m68k.deinit();
    
    try stdout.print("CPU initialized successfully\n", .{});
    try stdout.print("Memory size: {} MB\n", .{m68k.memory.size / (1024 * 1024)});
    try stdout.print("PC: 0x{X:0>8}\n", .{m68k.pc});
    try stdout.print("SR: 0x{X:0>4}\n\n", .{m68k.sr});
    
    // Display data registers
    try stdout.print("Data Registers:\n", .{});
    for (m68k.d, 0..) |reg, i| {
        try stdout.print("  D{}: 0x{X:0>8}\n", .{i, reg});
    }
    
    // Display address registers
    try stdout.print("\nAddress Registers:\n", .{});
    for (m68k.a, 0..) |reg, i| {
        try stdout.print("  A{}: 0x{X:0>8}\n", .{i, reg});
    }
    
    // Test memory operations
    try stdout.print("\nTesting memory operations...\n", .{});
    try m68k.memory.write32(0x1000, 0x12345678);
    const value = try m68k.memory.read32(0x1000);
    try stdout.print("Wrote 0x12345678 to 0x1000, read back: 0x{X:0>8}\n", .{value});
    
    // Write a simple program: MOVEQ #42, D0 ; NOP ; ILLEGAL
    try stdout.print("\nLoading test program...\n", .{});
    try m68k.memory.write16(0x1000, 0x702A);  // MOVEQ #42, D0
    try m68k.memory.write16(0x1002, 0x4E71);  // NOP
    try m68k.memory.write16(0x1004, 0x4AFC);  // ILLEGAL
    
    m68k.pc = 0x1000;
    
    try stdout.print("Executing program...\n", .{});
    
    // Execute MOVEQ
    _ = m68k.step() catch |err| {
        try stdout.print("Error executing instruction: {}\n", .{err});
    };
    try stdout.print("After MOVEQ #42, D0: D0 = 0x{X:0>8}\n", .{m68k.d[0]});
    
    // Execute NOP
    _ = m68k.step() catch |err| {
        try stdout.print("Error executing instruction: {}\n", .{err});
    };
    try stdout.print("After NOP: PC = 0x{X:0>8}\n", .{m68k.pc});
    
    try stdout.print("\nEmulator ready.\n", .{});
}
