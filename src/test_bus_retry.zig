const std = @import("std");
const cpu = @import("cpu.zig");
const memory = @import("memory.zig");

var retry_calls: u32 = 0;

fn retryHook(_: ?*anyopaque, _: u32, _: memory.BusAccess) memory.BusSignal {
    retry_calls += 1;
    return .retry;
}

test "Bus retry mechanism" {
    const allocator = std.testing.allocator;
    var m68k = cpu.M68k.initWithConfig(allocator, .{
        .bus_hook = retryHook,
    });
    defer m68k.deinit();

    retry_calls = 0;
    m68k.setBusRetryLimit(5);
    m68k.setStackPointer(.Interrupt, 0x1000);
    
    // We expect the first fetch to fail after 5 retries (6 total calls)
    var result: anyerror!u32 = error.BusRetry;
    while (result == error.BusRetry or (result catch 0) == 4) {
        if (m68k.getBusRetryCount() == 0 and retry_calls > 0) break;
        result = m68k.step();
    }
    
    // Total calls = 1 (initial) + 5 (retries) = 6
    try std.testing.expectEqual(@as(u32, 6), retry_calls);
    try std.testing.expect(result != error.BusRetry); // Should enter exception instead
    
    // Check if exception frame contains the retry count (5)
    // SP should have moved by 24 bytes (Format $A)
    const sp = m68k.getStackPointer(.Interrupt);
    const retry_count_in_frame = try m68k.memory.read16(sp + 16);
    try std.testing.expectEqual(@as(u16, 5), retry_count_in_frame);
}

test "Bus retry reset on success" {
    const allocator = std.testing.allocator;
    
    const SuccessAfterRetryCtx = struct {
        calls: u32 = 0,
        fail_until: u32 = 3,
    };
    
    var ctx = SuccessAfterRetryCtx{};
    
    const hook = struct {
        fn h(p: ?*anyopaque, _: u32, _: memory.BusAccess) memory.BusSignal {
            const c: *SuccessAfterRetryCtx = @ptrCast(@alignCast(p.?));
            c.calls += 1;
            if (c.calls <= c.fail_until) return .retry;
            return .ok;
        }
    }.h;

    var m68k = cpu.M68k.initWithConfig(allocator, .{
        .bus_hook = hook,
        .bus_hook_ctx = &ctx,
    });
    defer m68k.deinit();

    // Set NOP at PC
    try m68k.memory.write16(0, 0x4E71);
    m68k.pc = 0;
    m68k.setStackPointer(.Interrupt, 0x1000);
    
    var result: anyerror!u32 = error.BusRetry;
    while (m68k.pc == 0) {
        result = m68k.step();
        if (result == error.BusError) break;
    }
    
    try std.testing.expectEqual(@as(u32, 4), ctx.calls); // 3 fails + 1 success
    try std.testing.expectEqual(@as(u8, 0), m68k.getBusRetryCount());
    try std.testing.expectEqual(@as(u32, 2), m68k.pc); // Should have advanced past NOP
}
