const std = @import("std");
const cpu = @import("cpu.zig");
const decoder = @import("decoder.zig");
const memory = @import("memory.zig");

// Export Zig types for use in other Zig code
pub const M68k = cpu.M68k;
pub const Decoder = decoder.Decoder;
pub const Memory = memory.Memory;

// Export C API for use in other languages (Python, C, etc.)
// Global page allocator for C API
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
var gpa_mutex = std.Thread.Mutex{};

const STATUS_OK: c_int = 0;
const STATUS_INVALID_ARG: c_int = -1;
const STATUS_MEMORY_ERROR: c_int = -2;

pub const M68kApiContext = struct {
    const AllocMode = enum { gpa, callback };

    gpa: std.heap.GeneralPurposeAllocator(.{}) = .{},
    mutex: std.Thread.Mutex = .{},
    alloc_mode: AllocMode = .gpa,
    callback_ctx: ?*anyopaque = null,
    alloc_cb: ?M68kAllocCallback = null,
    free_cb: ?M68kFreeCallback = null,

    fn allocator(self: *M68kApiContext) std.mem.Allocator {
        return switch (self.alloc_mode) {
            .gpa => self.gpa.allocator(),
            .callback => .{
                .ptr = self,
                .vtable = &callback_allocator_vtable,
            },
        };
    }
};

pub const M68kAllocCallback = *const fn (ctx: ?*anyopaque, size: usize, alignment: usize) callconv(.C) ?*anyopaque;
pub const M68kFreeCallback = *const fn (ctx: ?*anyopaque, ptr: ?*anyopaque, size: usize, alignment: usize) callconv(.C) void;

const callback_allocator_vtable = std.mem.Allocator.VTable{
    .alloc = callbackAlloc,
    .resize = std.mem.Allocator.noResize,
    .free = callbackFree,
};

fn callbackAlloc(raw_ctx: *anyopaque, len: usize, ptr_align: u8, _: usize) ?[*]u8 {
    const ctx: *M68kApiContext = @ptrCast(@alignCast(raw_ctx));
    const alloc_cb = ctx.alloc_cb orelse return null;
    const alignment: usize = @as(usize, 1) << @intCast(ptr_align);
    const p = alloc_cb(ctx.callback_ctx, len, alignment) orelse return null;
    return @ptrCast(p);
}

fn callbackFree(raw_ctx: *anyopaque, buf: []u8, buf_align: u8, _: usize) void {
    const ctx: *M68kApiContext = @ptrCast(@alignCast(raw_ctx));
    const free_cb = ctx.free_cb orelse return;
    const alignment: usize = @as(usize, 1) << @intCast(buf_align);
    free_cb(ctx.callback_ctx, @ptrCast(buf.ptr), buf.len, alignment);
}

fn mapMemoryError(err: anyerror) c_int {
    return switch (err) {
        error.InvalidAddress, error.BusError, error.AddressError, error.BusRetry, error.BusHalt => STATUS_MEMORY_ERROR,
        else => STATUS_MEMORY_ERROR,
    };
}

export fn m68k_create() ?*cpu.M68k {
    return m68k_create_with_memory(16 * 1024 * 1024);
}

export fn m68k_create_with_memory(memory_size: u32) ?*cpu.M68k {
    gpa_mutex.lock();
    defer gpa_mutex.unlock();
    const allocator = gpa.allocator();
    const m68k = allocator.create(cpu.M68k) catch return null;
    m68k.* = cpu.M68k.initWithConfig(allocator, .{ .size = memory_size });
    return m68k;
}

export fn m68k_context_create() ?*M68kApiContext {
    const allocator = std.heap.page_allocator;
    const ctx = allocator.create(M68kApiContext) catch return null;
    ctx.* = .{};
    return ctx;
}

export fn m68k_context_destroy(ctx: ?*M68kApiContext) c_int {
    const c = ctx orelse return STATUS_INVALID_ARG;
    if (c.alloc_mode == .gpa) {
        _ = c.gpa.deinit();
    }
    std.heap.page_allocator.destroy(c);
    return STATUS_OK;
}

export fn m68k_context_set_allocator_callbacks(
    ctx: ?*M68kApiContext,
    alloc_cb: ?M68kAllocCallback,
    free_cb: ?M68kFreeCallback,
    callback_ctx: ?*anyopaque,
) c_int {
    const c = ctx orelse return STATUS_INVALID_ARG;

    c.mutex.lock();
    defer c.mutex.unlock();

    if (alloc_cb == null and free_cb == null) {
        c.alloc_mode = .gpa;
        c.callback_ctx = null;
        c.alloc_cb = null;
        c.free_cb = null;
        return STATUS_OK;
    }
    if (alloc_cb == null or free_cb == null) return STATUS_INVALID_ARG;

    c.alloc_mode = .callback;
    c.callback_ctx = callback_ctx;
    c.alloc_cb = alloc_cb;
    c.free_cb = free_cb;
    return STATUS_OK;
}

export fn m68k_create_in_context(ctx: ?*M68kApiContext, memory_size: u32) ?*cpu.M68k {
    const c = ctx orelse return null;
    c.mutex.lock();
    defer c.mutex.unlock();
    const allocator = c.allocator();
    const m68k = allocator.create(cpu.M68k) catch return null;
    m68k.* = cpu.M68k.initWithConfig(allocator, .{ .size = memory_size });
    return m68k;
}

export fn m68k_destroy_in_context(ctx: ?*M68kApiContext, m68k: ?*cpu.M68k) c_int {
    const c = ctx orelse return STATUS_INVALID_ARG;
    const inst = m68k orelse return STATUS_INVALID_ARG;
    c.mutex.lock();
    defer c.mutex.unlock();
    const allocator = inst.allocator;
    inst.deinit();
    allocator.destroy(inst);
    return STATUS_OK;
}

export fn m68k_destroy(m68k: *cpu.M68k) void {
    const allocator = m68k.allocator;
    m68k.deinit();
    allocator.destroy(m68k);
}

export fn m68k_reset(m68k: *cpu.M68k) void {
    m68k.reset();
}

export fn m68k_step(m68k: *cpu.M68k) c_int {
    const result = m68k.step() catch return -1;
    return @intCast(result);
}

export fn m68k_execute(m68k: *cpu.M68k, cycles: c_uint) c_int {
    const result = m68k.execute(cycles) catch return -1;
    return @intCast(result);
}

export fn m68k_set_irq(m68k: *cpu.M68k, level: u8) void {
    if (level <= 7) {
        m68k.setInterruptLevel(@truncate(level));
    }
}

export fn m68k_set_irq_vector(m68k: *cpu.M68k, level: u8, vector: u8) void {
    if (level <= 7) {
        m68k.setInterruptVector(@truncate(level), vector);
    }
}

export fn m68k_set_spurious_irq(m68k: *cpu.M68k, level: u8) void {
    if (level <= 7) {
        m68k.setSpuriousInterrupt(@truncate(level));
    }
}

export fn m68k_invalidate_translation_cache(m68k: *cpu.M68k) void {
    m68k.memory.invalidateTranslationCache();
}

export fn m68k_set_pmmu_compat(m68k: *cpu.M68k, enabled: bool) void {
    m68k.setPmmuCompatEnabled(enabled);
}

export fn m68k_set_icache_fetch_miss_penalty(m68k: *cpu.M68k, penalty_cycles: u32) void {
    m68k.setICacheFetchMissPenalty(penalty_cycles);
}

export fn m68k_get_icache_fetch_miss_penalty(m68k: *cpu.M68k) u32 {
    return m68k.getICacheFetchMissPenalty();
}

export fn m68k_get_icache_hit_count(m68k: *cpu.M68k) u64 {
    return m68k.getICacheStats().hits;
}

export fn m68k_get_icache_miss_count(m68k: *cpu.M68k) u64 {
    return m68k.getICacheStats().misses;
}

export fn m68k_clear_icache_stats(m68k: *cpu.M68k) void {
    m68k.clearICacheStats();
}

export fn m68k_set_pipeline_mode(m68k: *cpu.M68k, mode: u8) void {
    const pipeline_mode: cpu.M68k.PipelineMode = switch (mode) {
        1 => .approx,
        2 => .detailed,
        else => .off,
    };
    m68k.setPipelineMode(pipeline_mode);
}

export fn m68k_get_pipeline_mode(m68k: *cpu.M68k) u8 {
    return @intFromEnum(m68k.getPipelineMode());
}

export fn m68k_set_pc(m68k: *cpu.M68k, pc: u32) void {
    m68k.pc = pc;
}

export fn m68k_get_pc(m68k: *cpu.M68k) u32 {
    return m68k.pc;
}

export fn m68k_set_reg_d(m68k: *cpu.M68k, reg: u8, value: u32) void {
    if (reg < 8) m68k.d[reg] = value;
}

export fn m68k_get_reg_d(m68k: *cpu.M68k, reg: u8) u32 {
    return if (reg < 8) m68k.d[reg] else 0;
}

export fn m68k_set_reg_a(m68k: *cpu.M68k, reg: u8, value: u32) void {
    if (reg < 8) m68k.a[reg] = value;
}

export fn m68k_get_reg_a(m68k: *cpu.M68k, reg: u8) u32 {
    return if (reg < 8) m68k.a[reg] else 0;
}

export fn m68k_write_memory_8(m68k: *cpu.M68k, addr: u32, value: u8) void {
    m68k.memory.write8(addr, value) catch {};
}

export fn m68k_write_memory_16(m68k: *cpu.M68k, addr: u32, value: u16) void {
    m68k.memory.write16(addr, value) catch {};
}

export fn m68k_write_memory_32(m68k: *cpu.M68k, addr: u32, value: u32) void {
    m68k.memory.write32(addr, value) catch {};
}

export fn m68k_read_memory_8(m68k: *cpu.M68k, addr: u32) u8 {
    return m68k.memory.read8(addr) catch 0;
}

export fn m68k_read_memory_16(m68k: *cpu.M68k, addr: u32) u16 {
    return m68k.memory.read16(addr) catch 0;
}

export fn m68k_read_memory_32(m68k: *cpu.M68k, addr: u32) u32 {
    return m68k.memory.read32(addr) catch 0;
}

export fn m68k_get_memory_size(m68k: *cpu.M68k) u32 {
    return m68k.memory.size;
}

export fn m68k_load_binary(m68k: *cpu.M68k, data: [*]const u8, length: u32, start_addr: u32) c_int {
    const slice = data[0..length];
    m68k.memory.loadBinary(slice, start_addr) catch return -1;
    return 0;
}

// Status-code based C API v2 for memory access.
// Returns:
//   0  : success
//  -1  : invalid argument (e.g. null output pointer)
//  -2  : memory/bus/alignment related error
export fn m68k_read_memory_8_status(m68k: *cpu.M68k, addr: u32, out_value: ?*u8) c_int {
    const out = out_value orelse return STATUS_INVALID_ARG;
    const access: memory.BusAccess = .{ .function_code = m68k.dfc, .space = .Data, .is_write = false };
    out.* = m68k.memory.read8Bus(addr, access) catch |err| return mapMemoryError(err);
    return STATUS_OK;
}

export fn m68k_read_memory_16_status(m68k: *cpu.M68k, addr: u32, out_value: ?*u16) c_int {
    const out = out_value orelse return STATUS_INVALID_ARG;
    const access: memory.BusAccess = .{ .function_code = m68k.dfc, .space = .Data, .is_write = false };
    out.* = m68k.memory.read16Bus(addr, access) catch |err| return mapMemoryError(err);
    return STATUS_OK;
}

export fn m68k_read_memory_32_status(m68k: *cpu.M68k, addr: u32, out_value: ?*u32) c_int {
    const out = out_value orelse return STATUS_INVALID_ARG;
    const access: memory.BusAccess = .{ .function_code = m68k.dfc, .space = .Data, .is_write = false };
    out.* = m68k.memory.read32Bus(addr, access) catch |err| return mapMemoryError(err);
    return STATUS_OK;
}

export fn m68k_write_memory_8_status(m68k: *cpu.M68k, addr: u32, value: u8) c_int {
    const access: memory.BusAccess = .{ .function_code = m68k.dfc, .space = .Data, .is_write = true };
    m68k.memory.write8Bus(addr, value, access) catch |err| return mapMemoryError(err);
    return STATUS_OK;
}

export fn m68k_write_memory_16_status(m68k: *cpu.M68k, addr: u32, value: u16) c_int {
    const access: memory.BusAccess = .{ .function_code = m68k.dfc, .space = .Data, .is_write = true };
    m68k.memory.write16Bus(addr, value, access) catch |err| return mapMemoryError(err);
    return STATUS_OK;
}

export fn m68k_write_memory_32_status(m68k: *cpu.M68k, addr: u32, value: u32) c_int {
    const access: memory.BusAccess = .{ .function_code = m68k.dfc, .space = .Data, .is_write = true };
    m68k.memory.write32Bus(addr, value, access) catch |err| return mapMemoryError(err);
    return STATUS_OK;
}

test "basic library test" {
    const testing = std.testing;
    try testing.expect(true);
}

test "root API IRQ autovector integration" {
    const m68k = m68k_create_with_memory(64 * 1024) orelse return error.OutOfMemory;
    defer m68k_destroy(m68k);

    // level-3 autovector (27) handler at 0x4000
    m68k_write_memory_32(m68k, 27 * 4, 0x4000);
    m68k_write_memory_16(m68k, 0x1000, 0x4E71); // NOP

    m68k_set_pc(m68k, 0x1000);
    m68k_set_reg_a(m68k, 7, 0x3000);
    m68k.sr = 0x2000; // supervisor, mask 0

    m68k_set_irq(m68k, 3);
    const cycles = m68k_step(m68k);

    try std.testing.expectEqual(@as(c_int, 44), cycles);
    try std.testing.expectEqual(@as(u32, 0x4000), m68k_get_pc(m68k));
    try std.testing.expectEqual(@as(u32, 0x2FF8), m68k_get_reg_a(m68k, 7));
    try std.testing.expectEqual(@as(u16, 27 * 4), m68k_read_memory_16(m68k, 0x2FFE));
}

test "root API IRQ vector override and spurious integration" {
    const m68k = m68k_create_with_memory(64 * 1024) orelse return error.OutOfMemory;
    defer m68k_destroy(m68k);

    // Explicit vector 0x64 path.
    m68k_write_memory_32(m68k, 0x64 * 4, 0x4800);
    m68k_write_memory_16(m68k, 0x1200, 0x4E71); // NOP
    m68k_set_pc(m68k, 0x1200);
    m68k_set_reg_a(m68k, 7, 0x3400);
    m68k.sr = 0x2000;
    m68k_set_irq_vector(m68k, 2, 0x64);

    try std.testing.expectEqual(@as(c_int, 44), m68k_step(m68k));
    try std.testing.expectEqual(@as(u32, 0x4800), m68k_get_pc(m68k));
    try std.testing.expectEqual(@as(u16, 0x64 * 4), m68k_read_memory_16(m68k, 0x33FE));

    // Spurious vector (24) path.
    m68k_write_memory_32(m68k, 24 * 4, 0x4900);
    m68k_write_memory_16(m68k, 0x1300, 0x4E71); // NOP
    m68k_set_pc(m68k, 0x1300);
    m68k_set_reg_a(m68k, 7, 0x3500);
    m68k.sr = 0x2000;
    m68k_set_spurious_irq(m68k, 2);

    try std.testing.expectEqual(@as(c_int, 44), m68k_step(m68k));
    try std.testing.expectEqual(@as(u32, 0x4900), m68k_get_pc(m68k));
    try std.testing.expectEqual(@as(u16, 24 * 4), m68k_read_memory_16(m68k, 0x34FE));
}

test "root API STOP resumes on IRQ with expected cycle PC and SR" {
    const m68k = m68k_create_with_memory(64 * 1024) orelse return error.OutOfMemory;
    defer m68k_destroy(m68k);

    m68k_write_memory_16(m68k, 0x0800, 0x4E72); // STOP
    m68k_write_memory_16(m68k, 0x0802, 0x2000); // keep supervisor
    m68k_write_memory_16(m68k, 0x0804, 0x4E71); // NOP
    m68k_write_memory_32(m68k, 26 * 4, 0x0900); // level-2 autovector handler

    m68k_set_pc(m68k, 0x0800);
    m68k_set_reg_a(m68k, 7, 0x4200);
    m68k.sr = 0x2000;

    try std.testing.expectEqual(@as(c_int, 4), m68k_step(m68k)); // STOP executes
    try std.testing.expectEqual(@as(u32, 0x0804), m68k_get_pc(m68k));
    try std.testing.expect(m68k.stopped);

    try std.testing.expectEqual(@as(c_int, 4), m68k_step(m68k)); // still stopped
    try std.testing.expectEqual(@as(u32, 0x0804), m68k_get_pc(m68k));
    try std.testing.expect(m68k.stopped);

    m68k_set_irq(m68k, 2);
    try std.testing.expectEqual(@as(c_int, 44), m68k_step(m68k)); // IRQ wakes STOP
    try std.testing.expectEqual(@as(u32, 0x0900), m68k_get_pc(m68k));
    try std.testing.expect(!m68k.stopped);
    try std.testing.expectEqual(@as(u16, 0x2200), m68k.sr & 0x2700); // supervisor + IPL=2
}

test "root API status memory access surfaces error codes" {
    const m68k = m68k_create_with_memory(0x1000) orelse return error.OutOfMemory;
    defer m68k_destroy(m68k);

    var b: u8 = 0;
    var w: u16 = 0;
    var l: u32 = 0;

    try std.testing.expectEqual(@as(c_int, 0), m68k_write_memory_8_status(m68k, 0x20, 0xAB));
    try std.testing.expectEqual(@as(c_int, 0), m68k_read_memory_8_status(m68k, 0x20, &b));
    try std.testing.expectEqual(@as(u8, 0xAB), b);

    try std.testing.expectEqual(@as(c_int, -1), m68k_read_memory_16_status(m68k, 0x20, null));
    try std.testing.expectEqual(@as(c_int, -2), m68k_read_memory_32_status(m68k, 0x0FFF, &l)); // out of range

    m68k.memory.enforce_alignment = true;
    try std.testing.expectEqual(@as(c_int, -2), m68k_read_memory_16_status(m68k, 0x21, &w)); // odd alignment
}

const RootTranslatorCtx = struct {
    calls: usize = 0,
    delta: u32 = 0,
};

fn rootCountingTranslator(ctx: ?*anyopaque, logical_addr: u32, _: memory.BusAccess) !u32 {
    const c: *RootTranslatorCtx = @ptrCast(@alignCast(ctx.?));
    c.calls += 1;
    return logical_addr + c.delta;
}

test "root API can invalidate translation cache" {
    const m68k = m68k_create_with_memory(0x8000) orelse return error.OutOfMemory;
    defer m68k_destroy(m68k);

    var ctx = RootTranslatorCtx{ .delta = 0x1000 };
    m68k.memory.setAddressTranslator(rootCountingTranslator, &ctx);
    try m68k.memory.write8(0x1100, 0x5A);
    try m68k.memory.write8(0x1104, 0x5B);
    try m68k.memory.write8(0x1108, 0x5C);

    const access = memory.BusAccess{ .function_code = 0b001, .space = .Data, .is_write = false };
    try std.testing.expectEqual(@as(u8, 0x5A), try m68k.memory.read8Bus(0x0100, access));
    try std.testing.expectEqual(@as(usize, 1), ctx.calls);
    try std.testing.expectEqual(@as(u8, 0x5B), try m68k.memory.read8Bus(0x0104, access));
    try std.testing.expectEqual(@as(usize, 1), ctx.calls);

    m68k_invalidate_translation_cache(m68k);
    try std.testing.expectEqual(@as(u8, 0x5C), try m68k.memory.read8Bus(0x0108, access));
    try std.testing.expectEqual(@as(usize, 2), ctx.calls);
}

test "root API context-based create/destroy lifecycle" {
    const ctx = m68k_context_create() orelse return error.OutOfMemory;
    defer _ = m68k_context_destroy(ctx);

    const m1 = m68k_create_in_context(ctx, 0x2000) orelse return error.OutOfMemory;
    const m2 = m68k_create_in_context(ctx, 0x3000) orelse return error.OutOfMemory;
    defer _ = m68k_destroy_in_context(ctx, m2);
    defer _ = m68k_destroy_in_context(ctx, m1);

    try std.testing.expectEqual(@as(u32, 0x2000), m68k_get_memory_size(m1));
    try std.testing.expectEqual(@as(u32, 0x3000), m68k_get_memory_size(m2));

    try std.testing.expectEqual(@as(c_int, 0), m68k_write_memory_32_status(m1, 0x100, 0xDEADBEEF));
    var v: u32 = 0;
    try std.testing.expectEqual(@as(c_int, 0), m68k_read_memory_32_status(m1, 0x100, &v));
    try std.testing.expectEqual(@as(u32, 0xDEADBEEF), v);
}

test "root API context functions validate arguments" {
    try std.testing.expectEqual(@as(c_int, -1), m68k_context_destroy(null));
    try std.testing.expectEqual(@as(c_int, -1), m68k_destroy_in_context(null, null));

    const ctx = m68k_context_create() orelse return error.OutOfMemory;
    defer _ = m68k_context_destroy(ctx);

    try std.testing.expectEqual(@as(c_int, -1), m68k_destroy_in_context(ctx, null));
}

test "root API exposes icache stats miss penalty and pipeline mode controls" {
    const m68k = m68k_create_with_memory(64 * 1024 * 1024) orelse return error.OutOfMemory;
    defer m68k_destroy(m68k);

    m68k_write_memory_16(m68k, 0x2000, 0x4E7B); // MOVEC D0,CACR
    m68k_write_memory_16(m68k, 0x2002, 0x0002);
    m68k_set_reg_d(m68k, 0, 0x1); // enable cache
    m68k_set_pc(m68k, 0x2000);
    _ = m68k_step(m68k);

    m68k_write_memory_16(m68k, 0x2100, 0x4E71); // NOP

    m68k_set_icache_fetch_miss_penalty(m68k, 5);
    try std.testing.expectEqual(@as(u32, 5), m68k_get_icache_fetch_miss_penalty(m68k));

    m68k_set_pc(m68k, 0x2100);
    try std.testing.expectEqual(@as(c_int, 9), m68k_step(m68k)); // miss
    m68k_set_pc(m68k, 0x2100);
    try std.testing.expectEqual(@as(c_int, 4), m68k_step(m68k)); // hit

    try std.testing.expectEqual(@as(u64, 1), m68k_get_icache_hit_count(m68k));
    try std.testing.expectEqual(@as(u64, 1), m68k_get_icache_miss_count(m68k));
    m68k_clear_icache_stats(m68k);
    try std.testing.expectEqual(@as(u64, 0), m68k_get_icache_hit_count(m68k));
    try std.testing.expectEqual(@as(u64, 0), m68k_get_icache_miss_count(m68k));

    try std.testing.expectEqual(@as(u8, 0), m68k_get_pipeline_mode(m68k));
    m68k_set_pipeline_mode(m68k, 1);
    try std.testing.expectEqual(@as(u8, 1), m68k_get_pipeline_mode(m68k));
    m68k_set_pipeline_mode(m68k, 2);
    try std.testing.expectEqual(@as(u8, 2), m68k_get_pipeline_mode(m68k));
    m68k_set_pipeline_mode(m68k, 99); // fallback to off
    try std.testing.expectEqual(@as(u8, 0), m68k_get_pipeline_mode(m68k));
}

const CallbackAllocStats = struct {
    alloc_count: usize = 0,
    free_count: usize = 0,
};

fn callbackAllocTest(ctx: ?*anyopaque, size: usize, alignment: usize) callconv(.C) ?*anyopaque {
    const stats: *CallbackAllocStats = @ptrCast(@alignCast(ctx orelse return null));
    if (alignment == 0 or !std.math.isPowerOfTwo(alignment)) return null;
    const log2_align: u8 = @intCast(@ctz(alignment));
    const mem = std.heap.page_allocator.rawAlloc(size, log2_align, @returnAddress()) orelse return null;
    stats.alloc_count += 1;
    return @ptrCast(mem);
}

fn callbackFreeTest(ctx: ?*anyopaque, ptr: ?*anyopaque, size: usize, alignment: usize) callconv(.C) void {
    const stats: *CallbackAllocStats = @ptrCast(@alignCast(ctx orelse return));
    const p = ptr orelse return;
    if (alignment == 0 or !std.math.isPowerOfTwo(alignment)) return;
    const log2_align: u8 = @intCast(@ctz(alignment));
    const buf: []u8 = (@as([*]u8, @ptrCast(p)))[0..size];
    std.heap.page_allocator.rawFree(buf, log2_align, @returnAddress());
    stats.free_count += 1;
}

test "root API context allocator callbacks are used for instance lifecycle" {
    const ctx = m68k_context_create() orelse return error.OutOfMemory;
    defer _ = m68k_context_destroy(ctx);

    var stats = CallbackAllocStats{};
    try std.testing.expectEqual(
        @as(c_int, 0),
        m68k_context_set_allocator_callbacks(ctx, callbackAllocTest, callbackFreeTest, &stats),
    );

    const m68k = m68k_create_in_context(ctx, 0x4000) orelse return error.OutOfMemory;
    try std.testing.expect(stats.alloc_count > 0);

    try std.testing.expectEqual(@as(c_int, 0), m68k_destroy_in_context(ctx, m68k));
    try std.testing.expect(stats.free_count > 0);
    try std.testing.expect(stats.alloc_count == stats.free_count);
}
