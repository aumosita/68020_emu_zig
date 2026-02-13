const std = @import("std");
const memory_mod = @import("memory.zig");

const CountingCtx = struct {
    calls: usize = 0,
    delta: u32 = 0x1000,
};

fn countingTranslator(ctx: ?*anyopaque, logical_addr: u32, _: memory_mod.BusAccess) !u32 {
    const c: *CountingCtx = @ptrCast(@alignCast(ctx.?));
    c.calls += 1;
    return logical_addr + c.delta;
}

fn runWorkload(mem: *memory_mod.Memory, iterations: usize, flush_each_access: bool) !u64 {
    var timer = try std.time.Timer.start();
    const access = memory_mod.BusAccess{ .function_code = 0b001, .space = .Data, .is_write = false };

    var i: usize = 0;
    while (i < iterations) : (i += 1) {
        // Reuse a small page window to maximize TLB hit potential.
        const logical = @as(u32, @intCast((i & 0xFF) * 4));
        if (flush_each_access) mem.invalidateTranslationCache();
        _ = try mem.read32Bus(logical, access);
    }
    return timer.read();
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var ctx = CountingCtx{};
    var mem = memory_mod.Memory.initWithConfig(allocator, .{
        .size = 2 * 1024 * 1024,
        .address_translator = countingTranslator,
        .address_translator_ctx = &ctx,
    });
    defer mem.deinit();

    // Seed physical memory region used by translated reads.
    var addr: u32 = 0x1000;
    while (addr < 0x2000) : (addr += 4) {
        try mem.write32(addr, 0xDEADBEEF);
    }

    const iterations: usize = 2_000_000;

    ctx.calls = 0;
    const uncached_ns = try runWorkload(&mem, iterations, true);
    const uncached_calls = ctx.calls;

    ctx.calls = 0;
    mem.invalidateTranslationCache();
    const cached_ns = try runWorkload(&mem, iterations, false);
    const cached_calls = ctx.calls;

    const stdout = std.io.getStdOut().writer();
    try stdout.print("iterations={d}\n", .{iterations});
    try stdout.print("uncached_ns={d} uncached_translator_calls={d}\n", .{ uncached_ns, uncached_calls });
    try stdout.print("cached_ns={d} cached_translator_calls={d}\n", .{ cached_ns, cached_calls });
}
