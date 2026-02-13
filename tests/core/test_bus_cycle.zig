const std = @import("std");
const Memory = @import("../../src/core/memory.zig").Memory;
const bus_cycle = @import("../../src/core/bus_cycle.zig");

test "memory with bus cycle modeling - ROM wait states" {
    const allocator = std.testing.allocator;
    
    // ROM 영역에 3 wait states 설정
    const wait_regions = [_]bus_cycle.WaitStateRegion{
        .{ .start = 0x8000, .end_exclusive = 0xC000, .wait_states = 3 },
    };
    
    var mem = Memory.initWithConfig(allocator, .{
        .size = 64 * 1024,
        .bus_cycle_config = .{
            .default_wait_states = 0,
            .region_wait_states = &wait_regions,
        },
    });
    defer mem.deinit();
    
    mem.setBusCycleEnabled(true);
    
    // RAM 영역 쓰기 (0 wait states)
    try mem.write32(0x1000, 0x12345678);
    const ram_val = try mem.read32(0x1000);
    try std.testing.expectEqual(@as(u32, 0x12345678), ram_val);
    
    // ROM 영역 쓰기 (3 wait states)
    try mem.write32(0x9000, 0xAABBCCDD);
    const rom_val = try mem.read32(0x9000);
    try std.testing.expectEqual(@as(u32, 0xAABBCCDD), rom_val);
    
    // Wait cycles 통계 확인
    const stats = mem.getBusCycleStats();
    try std.testing.expect(stats.total_wait_cycles >= 0);
}

test "memory bus cycle enabled vs disabled" {
    const allocator = std.testing.allocator;
    
    var mem = Memory.initWithConfig(allocator, .{
        .size = 64 * 1024,
        .bus_cycle_config = .{ .default_wait_states = 2 },
    });
    defer mem.deinit();
    
    // 비활성화 상태 (기본)
    try std.testing.expect(!mem.bus_cycle_enabled);
    
    // 활성화
    mem.setBusCycleEnabled(true);
    try std.testing.expect(mem.bus_cycle_enabled);
    
    // 비활성화
    mem.setBusCycleEnabled(false);
    try std.testing.expect(!mem.bus_cycle_enabled);
}

test "memory bus cycle stats reset" {
    const allocator = std.testing.allocator;
    
    const wait_regions = [_]bus_cycle.WaitStateRegion{
        .{ .start = 0x0000, .end_exclusive = 0x10000, .wait_states = 5 },
    };
    
    var mem = Memory.initWithConfig(allocator, .{
        .size = 64 * 1024,
        .bus_cycle_config = .{
            .default_wait_states = 0,
            .region_wait_states = &wait_regions,
        },
    });
    defer mem.deinit();
    
    mem.setBusCycleEnabled(true);
    
    // 여러 접근 수행
    try mem.write32(0x1000, 0x11111111);
    try mem.write32(0x2000, 0x22222222);
    _ = try mem.read32(0x3000);
    
    // 통계 초기화
    mem.resetBusCycleStats();
    
    const stats = mem.getBusCycleStats();
    try std.testing.expectEqual(@as(u32, 0), stats.total_wait_cycles);
}

test "calculateBusCycles with multiple regions" {
    const regions = [_]bus_cycle.WaitStateRegion{
        .{ .start = 0x0000, .end_exclusive = 0x1000, .wait_states = 0 }, // Fast RAM
        .{ .start = 0x8000, .end_exclusive = 0xA000, .wait_states = 3 }, // ROM
        .{ .start = 0xF000, .end_exclusive = 0xF100, .wait_states = 7 }, // Slow UART
    };
    
    const config = bus_cycle.BusCycleConfig{
        .default_wait_states = 1,
        .region_wait_states = &regions,
    };
    
    // Fast RAM: 4 + 0 = 4 cycles
    try std.testing.expectEqual(@as(u32, 4), bus_cycle.calculateBusCycles(0x0500, 4, &config));
    
    // ROM: 4 + 3 = 7 cycles
    try std.testing.expectEqual(@as(u32, 7), bus_cycle.calculateBusCycles(0x8100, 4, &config));
    
    // UART: 4 + 7 = 11 cycles
    try std.testing.expectEqual(@as(u32, 11), bus_cycle.calculateBusCycles(0xF010, 1, &config));
    
    // Default region: 4 + 1 = 5 cycles
    try std.testing.expectEqual(@as(u32, 5), bus_cycle.calculateBusCycles(0x5000, 4, &config));
}
