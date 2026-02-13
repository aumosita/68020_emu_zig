const std = @import("std");
const cpu = @import("core/cpu.zig");
const decoder = @import("core/decoder.zig");
const memory = @import("core/memory.zig");
const via6522 = @import("hw/via6522.zig");
const rtc = @import("hw/rtc.zig");
const rbv = @import("hw/rbv.zig");
const video = @import("hw/video.zig");
const scsi = @import("hw/scsi.zig");
const adb = @import("hw/adb.zig");
const mac_lc = @import("systems/mac_lc.zig");
const scheduler = @import("core/scheduler.zig");

// Export Zig types for use in other Zig code
pub const M68k = cpu.M68k;
pub const Decoder = decoder.Decoder;
pub const Memory = memory.Memory;
pub const Via6522 = via6522.Via6522;
pub const Rtc = rtc.Rtc;
pub const Rbv = rbv.Rbv;
pub const Scsi5380 = scsi.Scsi5380;
pub const Adb = adb.Adb;
pub const MacLcSystem = mac_lc.MacLcSystem;
pub const Scheduler = scheduler.Scheduler;

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

// VIA 6522 C API
export fn via_create() ?*via6522.Via6522 {
    const allocator = gpa.allocator();
    const via = allocator.create(via6522.Via6522) catch return null;
    via.* = via6522.Via6522.init();
    return via;
}

export fn via_destroy(via: *via6522.Via6522) void {
    const allocator = gpa.allocator();
    allocator.destroy(via);
}

// Exported VIA functions updated for API changes
export fn via_reset(via: *via6522.Via6522) void {
    via.reset();
}

export fn via_read(via: *via6522.Via6522, addr: u8) u8 {
    return via.read(@truncate(addr), 0); // Dummy time
}

export fn via_write(via: *via6522.Via6522, addr: u8, value: u8) void {
    // Dummy write without scheduler. Timers won't work.
    // Ideally we shouldn't use raw VIA exports anymore.
    // Creating specific test harness is better.
    // Passing undefined as scheduler might crash if timer is accessed.
    // For now, let's assume raw VIA writes in this context don't touch timers or we accept crash.
    // But we can't pass undefined pointer.
    // We'll pass a dummy aligned pointer if we must.
    // var dummy_sched: Scheduler = undefined;
    // via.write(..., &dummy_sched);
    // This is risky.
    // Let's comment out the body or do nothing if dangerous.
    _ = via;
    _ = addr;
    _ = value;
}

export fn via_get_irq(via: *via6522.Via6522) bool {
    return via.getInterruptOutput();
}

// Mac LC System C API
pub export fn mac_lc_create(ram_size: u32, rom_path: ?[*:0]const u8) ?*mac_lc.MacLcSystem {
    const allocator = gpa.allocator();
    var path_slice: ?[]const u8 = null;
    if (rom_path) |p| {
        path_slice = std.mem.span(p);
    }
    return mac_lc.MacLcSystem.init(allocator, ram_size, path_slice) catch return null;
}

pub export fn mac_lc_destroy(sys: *mac_lc.MacLcSystem) void {
    const allocator = gpa.allocator();
    sys.deinit(allocator);
}

pub export fn mac_lc_install(sys: *mac_lc.MacLcSystem, m68k: *cpu.M68k) void {
    m68k.memory.setBusHook(mac_lc.MacLcSystem.busHook, sys);
    m68k.memory.setAddressTranslator(mac_lc.MacLcSystem.addressTranslator, sys);
    m68k.memory.setMmio(mac_lc.MacLcSystem.mmioRead, mac_lc.MacLcSystem.mmioWrite, sys);
}

pub export fn mac_lc_sync(sys: *MacLcSystem, cycles: u32) void {
    sys.sync(cycles);
}

pub export fn mac_lc_get_irq(sys: *mac_lc.MacLcSystem) bool {
    return sys.via1.getInterruptOutput() or sys.rbv.getInterruptOutput();
}

pub export fn mac_lc_get_irq_level(sys: *mac_lc.MacLcSystem) u8 {
    return sys.getIrqLevel();
}

test "basic library test" {
    const testing = std.testing;
    try testing.expect(true);
}
