const std = @import("std");
const cpu = @import("../../src/core/cpu.zig");
const memory = @import("../../src/core/memory.zig");

test "Cycle Profiler basic tracking" {
    const allocator = std.testing.allocator;
    var m68k = cpu.M68k.initWithConfig(allocator, .{});
    defer m68k.deinit();

    try m68k.enableProfiler();
    
    // NOP (0x4E71)
    try m68k.memory.write16(0x1000, 0x4E71);
    // ADDI.L #1, D0 (0x0680 0000 0001)
    try m68k.memory.write16(0x1002, 0x0680);
    try m68k.memory.write32(0x1004, 1);
    
    m68k.pc = 0x1000;
    
    _ = try m68k.step(); // NOP
    _ = try m68k.step(); // ADDI
    
    const data = m68k.getProfilerData().?;
    
    // NOP is group 0x4E
    try std.testing.expect(data.instruction_counts[0x4E] >= 1);
    // ADDI is group 0x06
    try std.testing.expect(data.instruction_counts[0x06] >= 1);
    
    try std.testing.expectEqual(@as(u64, 2), data.total_steps);
    try std.testing.expect(data.total_cycles > 0);
}

test "Profiler Top 10 Report" {
    const allocator = std.testing.allocator;
    var m68k = cpu.M68k.initWithConfig(allocator, .{});
    defer m68k.deinit();

    try m68k.enableProfiler();
    
    // Run some random instructions
    try m68k.memory.write16(0, 0x4E71); // NOP
    m68k.pc = 0;
    for (0..100) |_| {
        m68k.pc = 0;
        _ = try m68k.step();
    }
    
    const data = m68k.getProfilerData().?;
    
    // Simple report generation logic check
    var count: usize = 0;
    for (data.instruction_counts) |c| {
        if (c > 0) count += 1;
    }
    try std.testing.expect(count >= 1);
}
