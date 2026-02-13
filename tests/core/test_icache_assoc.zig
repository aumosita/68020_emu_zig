const std = @import("std");
const cpu = @import("../../src/core/cpu.zig");
const memory = @import("../../src/core/memory.zig");

test "I-Cache 2-way associativity" {
    const allocator = std.testing.allocator;
    var m68k = cpu.M68k.initWithConfig(allocator, .{});
    defer m68k.deinit();

    m68k.setCacr(1); // Enable cache
    
    // 68020 cache is 256 bytes, 64 entries of 4-byte lines.
    // In our implementation: 32 sets * 2 ways = 64 entries.
    // Address format: [Tag:25] [Set:5] [Offset:2]
    
    // 1. Two addresses mapping to the same set (Set 0)
    const set_offset = 32 * 4; // 128 bytes
    const a1: u32 = 0x1000;
    const a2: u32 = a1 + set_offset;
    const a3: u32 = a2 + set_offset; // Conflict with both
    
    try m68k.memory.write16(a1, 0x4E71); // NOP
    try m68k.memory.write16(a2, 0x4E71); // NOP
    try m68k.memory.write16(a3, 0x4E71); // NOP
    
    m68k.clearICacheStats();
    
    // Fetch a1 -> Miss, Load into Way 0
    m68k.pc = a1;
    _ = try m68k.step();
    try std.testing.expectEqual(@as(u64, 1), m68k.getICacheStats().misses);
    
    // Fetch a2 -> Miss, Load into Way 1 (Associativity test: should NOT evict a1)
    m68k.pc = a2;
    _ = try m68k.step();
    try std.testing.expectEqual(@as(u64, 2), m68k.getICacheStats().misses);
    
    // Fetch a1 again -> Hit! (Associativity success)
    m68k.pc = a1;
    _ = try m68k.step();
    try std.testing.expectEqual(@as(u64, 1), m68k.getICacheStats().hits);
    
    // Fetch a3 -> Miss, should evict LRU (which is a2 because we just hit a1)
    m68k.pc = a3;
    _ = try m68k.step();
    try std.testing.expectEqual(@as(u64, 3), m68k.getICacheStats().misses);
    
    // a1 should still be a Hit
    m68k.pc = a1;
    _ = try m68k.step();
    try std.testing.expectEqual(@as(u64, 2), m68k.getICacheStats().hits);
    
    // a2 should be a Miss (it was evicted by a3)
    m68k.pc = a2;
    _ = try m68k.step();
    try std.testing.expectEqual(@as(u64, 4), m68k.getICacheStats().misses);
}
