const std = @import("std");
const bus_cycle = @import("bus_cycle.zig");

pub const MemoryConfig = struct {
    size: u32 = 16 * 1024 * 1024, // Default 16MB
    enforce_alignment: bool = false, // true = 68000 mode, false = 68020 mode
    bus_hook: ?BusHook = null,
    bus_hook_ctx: ?*anyopaque = null,
    address_translator: ?AddressTranslator = null,
    address_translator_ctx: ?*anyopaque = null,
    mmio_read: ?MmioRead = null,
    mmio_write: ?MmioWrite = null,
    mmio_ctx: ?*anyopaque = null,
    default_port_width: PortWidth = .Width32,
    port_regions: []const PortRegion = &[_]PortRegion{},
    bus_cycle_config: bus_cycle.BusCycleConfig = .{}, // 버스 사이클 설정
};

pub const AccessSpace = enum { Program, Data };

pub const BusAccess = struct {
    function_code: u3 = 0,
    space: AccessSpace = .Data,
    is_write: bool = false,
};

pub const BusSignal = enum { ok, retry, halt, bus_error };
pub const BusHook = *const fn (ctx: ?*anyopaque, logical_addr: u32, access: BusAccess) BusSignal;
pub const AddressTranslator = *const fn (ctx: ?*anyopaque, logical_addr: u32, access: BusAccess) anyerror!u32;
pub const MmioRead = *const fn (ctx: ?*anyopaque, logical_addr: u32, size: u8) ?u32;
pub const MmioWrite = *const fn (ctx: ?*anyopaque, logical_addr: u32, size: u8, value: u32) bool;
pub const PortWidth = enum(u8) { Width8 = 1, Width16 = 2, Width32 = 4 };
const TlbEntries = 8;
const TlbPageBits = 12;
const TlbPageSize = @as(u32, 1) << TlbPageBits;
const TlbPageMask = TlbPageSize - 1;
pub const PortRegion = struct {
    start: u32,
    end_exclusive: u32,
    width: PortWidth,
};

const TlbEntry = struct {
    valid: bool = false,
    logical_page: u32 = 0,
    physical_page_base: u32 = 0,
    function_code: u3 = 0,
    space: AccessSpace = .Data,
    is_write: bool = false,
};

pub const Memory = struct {
    // Memory data
    data: []u8,
    size: u32,
    enforce_alignment: bool, // 68000 compatibility mode
    bus_hook: ?BusHook,
    bus_hook_ctx: ?*anyopaque,
    address_translator: ?AddressTranslator,
    address_translator_ctx: ?*anyopaque,
    mmio_read: ?MmioRead,
    mmio_write: ?MmioWrite,
    mmio_ctx: ?*anyopaque,
    default_port_width: PortWidth,
    port_regions: []PortRegion,
    split_cycle_penalty: u32,
    tlb: [TlbEntries]TlbEntry,
    bus_cycle_sm: bus_cycle.BusCycleStateMachine, // 버스 사이클 상태 머신
    bus_cycle_enabled: bool, // 버스 사이클 모델링 활성화 여부
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Memory {
        return initWithConfig(allocator, .{});
    }

    pub fn initWithConfig(allocator: std.mem.Allocator, config: MemoryConfig) Memory {
        const mem_size = config.size;
        const data = allocator.alloc(u8, mem_size) catch {
            return Memory{
                .data = &[_]u8{},
                .size = 0,
                .enforce_alignment = config.enforce_alignment,
                .bus_hook = config.bus_hook,
                .bus_hook_ctx = config.bus_hook_ctx,
                .address_translator = config.address_translator,
                .address_translator_ctx = config.address_translator_ctx,
                .mmio_read = config.mmio_read,
                .mmio_write = config.mmio_write,
                .mmio_ctx = config.mmio_ctx,
                .default_port_width = config.default_port_width,
                .port_regions = &[_]PortRegion{},
                .split_cycle_penalty = 0,
                .tlb = [_]TlbEntry{.{}} ** TlbEntries,
                .bus_cycle_sm = bus_cycle.BusCycleStateMachine.init(config.bus_cycle_config),
                .bus_cycle_enabled = false,
                .allocator = allocator,
            };
        };
        const regions = allocator.alloc(PortRegion, config.port_regions.len) catch {
            allocator.free(data);
            return Memory{
                .data = &[_]u8{},
                .size = 0,
                .enforce_alignment = config.enforce_alignment,
                .bus_hook = config.bus_hook,
                .bus_hook_ctx = config.bus_hook_ctx,
                .address_translator = config.address_translator,
                .address_translator_ctx = config.address_translator_ctx,
                .mmio_read = config.mmio_read,
                .mmio_write = config.mmio_write,
                .mmio_ctx = config.mmio_ctx,
                .default_port_width = config.default_port_width,
                .port_regions = &[_]PortRegion{},
                .split_cycle_penalty = 0,
                .tlb = [_]TlbEntry{.{}} ** TlbEntries,
                .bus_cycle_sm = bus_cycle.BusCycleStateMachine.init(config.bus_cycle_config),
                .bus_cycle_enabled = false,
                .allocator = allocator,
            };
        };
        @memcpy(regions, config.port_regions);

        // Zero out memory
        @memset(data, 0);

        return Memory{
            .data = data,
            .size = mem_size,
            .enforce_alignment = config.enforce_alignment,
            .bus_hook = config.bus_hook,
            .bus_hook_ctx = config.bus_hook_ctx,
            .address_translator = config.address_translator,
            .address_translator_ctx = config.address_translator_ctx,
            .mmio_read = config.mmio_read,
            .mmio_write = config.mmio_write,
            .mmio_ctx = config.mmio_ctx,
            .default_port_width = config.default_port_width,
            .port_regions = regions,
            .split_cycle_penalty = 0,
            .tlb = [_]TlbEntry{.{}} ** TlbEntries,
            .bus_cycle_sm = bus_cycle.BusCycleStateMachine.init(config.bus_cycle_config),
            .bus_cycle_enabled = false,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Memory) void {
        if (self.data.len > 0) {
            self.allocator.free(self.data);
        }
        if (self.port_regions.len > 0) {
            self.allocator.free(self.port_regions);
        }
    }

    pub fn setBusHook(self: *Memory, hook: ?BusHook, ctx: ?*anyopaque) void {
        self.bus_hook = hook;
        self.bus_hook_ctx = ctx;
    }

    pub fn setAddressTranslator(self: *Memory, translator: ?AddressTranslator, ctx: ?*anyopaque) void {
        self.address_translator = translator;
        self.address_translator_ctx = ctx;
        self.invalidateTranslationCache();
    }

    pub fn setMmio(self: *Memory, read: ?MmioRead, write: ?MmioWrite, ctx: ?*anyopaque) void {
        self.mmio_read = read;
        self.mmio_write = write;
        self.mmio_ctx = ctx;
    }

    pub fn invalidateTranslationCache(self: *Memory) void {
        for (&self.tlb) |*entry| {
            entry.* = .{};
        }
    }

    /// 버스 사이클 모델링 활성화/비활성화
    pub fn setBusCycleEnabled(self: *Memory, enabled: bool) void {
        self.bus_cycle_enabled = enabled;
    }

    /// 버스 사이클 통계 조회
    pub fn getBusCycleStats(self: *const Memory) struct { total_wait_cycles: u32 } {
        return .{ .total_wait_cycles = self.bus_cycle_sm.getTotalWaitCycles() };
    }

    /// 버스 사이클 통계 초기화
    pub fn resetBusCycleStats(self: *Memory) void {
        self.bus_cycle_sm.resetStats();
    }

    fn tlbLookup(self: *const Memory, logical_addr: u32, access: BusAccess) ?u32 {
        const logical_page = logical_addr >> TlbPageBits;
        const index: usize = @intCast(logical_page & (TlbEntries - 1));
        const entry = self.tlb[index];
        if (!entry.valid) return null;
        if (entry.logical_page != logical_page) return null;
        if (entry.function_code != access.function_code) return null;
        if (entry.space != access.space) return null;
        if (entry.is_write != access.is_write) return null;
        const page_offset = logical_addr & TlbPageMask;
        return entry.physical_page_base +% page_offset;
    }

    fn tlbInsert(self: *Memory, logical_addr: u32, physical_addr: u32, access: BusAccess) void {
        const logical_page = logical_addr >> TlbPageBits;
        const page_offset = logical_addr & TlbPageMask;
        const index: usize = @intCast(logical_page & (TlbEntries - 1));
        self.tlb[index] = .{
            .valid = true,
            .logical_page = logical_page,
            .physical_page_base = physical_addr -% page_offset,
            .function_code = access.function_code,
            .space = access.space,
            .is_write = access.is_write,
        };
    }

    fn resolveBusAddress(self: *Memory, logical_addr: u32, access: BusAccess) !u32 {
        if (self.bus_hook) |hook| {
            switch (hook(self.bus_hook_ctx, logical_addr, access)) {
                .ok => {},
                .retry => return error.BusRetry,
                .halt => return error.BusHalt,
                .bus_error => return error.BusError,
            }
        }
        if (self.address_translator) |translator| {
            if (self.tlbLookup(logical_addr, access)) |translated| {
                return translated;
            }
            const translated = translator(self.address_translator_ctx, logical_addr, access) catch return error.BusError;
            self.tlbInsert(logical_addr, translated, access);
            return translated;
        }
        return logical_addr;
    }

    fn addSplitCyclePenalty(self: *Memory, extra_cycles: u32) void {
        self.split_cycle_penalty +|= extra_cycles;
    }

    pub fn takeSplitCyclePenalty(self: *Memory) u32 {
        const penalty = self.split_cycle_penalty;
        self.split_cycle_penalty = 0;
        return penalty;
    }

    fn portWidthFor(self: *const Memory, logical_addr: u32) PortWidth {
        for (self.port_regions) |region| {
            if (logical_addr >= region.start and logical_addr < region.end_exclusive) return region.width;
        }
        return self.default_port_width;
    }

    fn read8BusRaw(self: *const Memory, logical_addr: u32, access: BusAccess) !u8 {
        if (self.mmio_read) |read| {
            if (read(self.mmio_ctx, logical_addr, 1)) |val| return @truncate(val);
        }
        const addr = try @constCast(self).resolveBusAddress(logical_addr, access);
        if (addr >= self.size) return error.BusError;
        return self.data[addr];
    }

    fn read16BusRaw(self: *const Memory, logical_addr: u32, access: BusAccess) !u16 {
        if (self.mmio_read) |read| {
            if (read(self.mmio_ctx, logical_addr, 2)) |val| return @truncate(val);
        }
        const addr = try @constCast(self).resolveBusAddress(logical_addr, access);
        if (self.enforce_alignment and (addr & 1) != 0) return error.AddressError;
        if (addr + 1 >= self.size) return error.BusError;
        const high: u16 = self.data[addr];
        const low: u16 = self.data[addr + 1];
        return (high << 8) | low;
    }

    fn read32BusRaw(self: *const Memory, logical_addr: u32, access: BusAccess) !u32 {
        if (self.mmio_read) |read| {
            if (read(self.mmio_ctx, logical_addr, 4)) |val| return val;
        }
        const addr = try @constCast(self).resolveBusAddress(logical_addr, access);
        if (self.enforce_alignment and (addr & 1) != 0) return error.AddressError;
        if (addr + 3 >= self.size) return error.BusError;
        const b0: u32 = self.data[addr];
        const b1: u32 = self.data[addr + 1];
        const b2: u32 = self.data[addr + 2];
        const b3: u32 = self.data[addr + 3];
        return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3;
    }

    fn write8BusRaw(self: *Memory, logical_addr: u32, value: u8, access: BusAccess) !void {
        if (self.mmio_write) |write| {
            if (write(self.mmio_ctx, logical_addr, 1, value)) return;
        }
        const addr = try self.resolveBusAddress(logical_addr, access);
        if (addr >= self.size) return error.BusError;
        self.data[addr] = value;
    }

    fn write16BusRaw(self: *Memory, logical_addr: u32, value: u16, access: BusAccess) !void {
        if (self.mmio_write) |write| {
            if (write(self.mmio_ctx, logical_addr, 2, value)) return;
        }
        const addr = try self.resolveBusAddress(logical_addr, access);
        if (self.enforce_alignment and (addr & 1) != 0) return error.AddressError;
        if (addr + 1 >= self.size) return error.BusError;
        self.data[addr] = @truncate(value >> 8);
        self.data[addr + 1] = @truncate(value & 0xFF);
    }

    fn write32BusRaw(self: *Memory, logical_addr: u32, value: u32, access: BusAccess) !void {
        if (self.mmio_write) |write| {
            if (write(self.mmio_ctx, logical_addr, 4, value)) return;
        }
        const addr = try self.resolveBusAddress(logical_addr, access);
        if (self.enforce_alignment and (addr & 1) != 0) return error.AddressError;
        if (addr + 3 >= self.size) return error.BusError;
        self.data[addr] = @truncate(value >> 24);
        self.data[addr + 1] = @truncate((value >> 16) & 0xFF);
        self.data[addr + 2] = @truncate((value >> 8) & 0xFF);
        self.data[addr + 3] = @truncate(value & 0xFF);
    }

    pub fn read8Bus(self: *const Memory, logical_addr: u32, access: BusAccess) !u8 {
        if (self.bus_cycle_enabled) {
            const wait = bus_cycle.calculateBusCycles(logical_addr, 1, &self.bus_cycle_sm.config);
            if (wait > 4) @constCast(self).addSplitCyclePenalty(wait - 4);
        }
        return self.read8BusRaw(logical_addr, access);
    }

    pub fn read16Bus(self: *const Memory, logical_addr: u32, access: BusAccess) !u16 {
        if (self.bus_cycle_enabled) {
            const wait = bus_cycle.calculateBusCycles(logical_addr, 2, &self.bus_cycle_sm.config);
            if (wait > 4) @constCast(self).addSplitCyclePenalty(wait - 4);
        }
        return switch (self.portWidthFor(logical_addr)) {
            .Width8 => {
                @constCast(self).addSplitCyclePenalty(1);
                const high = try self.read8BusRaw(logical_addr, access);
                const low = try self.read8BusRaw(logical_addr + 1, access);
                return (@as(u16, high) << 8) | low;
            },
            else => self.read16BusRaw(logical_addr, access),
        };
    }

    pub fn read32Bus(self: *const Memory, logical_addr: u32, access: BusAccess) !u32 {
        if (self.bus_cycle_enabled) {
            const wait = bus_cycle.calculateBusCycles(logical_addr, 4, &self.bus_cycle_sm.config);
            if (wait > 4) @constCast(self).addSplitCyclePenalty(wait - 4);
        }
        return switch (self.portWidthFor(logical_addr)) {
            .Width8 => {
                @constCast(self).addSplitCyclePenalty(3);
                const b0 = try self.read8BusRaw(logical_addr, access);
                const b1 = try self.read8BusRaw(logical_addr + 1, access);
                const b2 = try self.read8BusRaw(logical_addr + 2, access);
                const b3 = try self.read8BusRaw(logical_addr + 3, access);
                return (@as(u32, b0) << 24) | (@as(u32, b1) << 16) | (@as(u32, b2) << 8) | b3;
            },
            .Width16 => {
                @constCast(self).addSplitCyclePenalty(1);
                const hi = try self.read16BusRaw(logical_addr, access);
                const lo = try self.read16BusRaw(logical_addr + 2, access);
                return (@as(u32, hi) << 16) | lo;
            },
            .Width32 => self.read32BusRaw(logical_addr, access),
        };
    }

    pub fn write8Bus(self: *Memory, logical_addr: u32, value: u8, access: BusAccess) !void {
        if (self.bus_cycle_enabled) {
            const wait = bus_cycle.calculateBusCycles(logical_addr, 1, &self.bus_cycle_sm.config);
            if (wait > 4) self.addSplitCyclePenalty(wait - 4);
        }
        try self.write8BusRaw(logical_addr, value, access);
    }

    pub fn write16Bus(self: *Memory, logical_addr: u32, value: u16, access: BusAccess) !void {
        if (self.bus_cycle_enabled) {
            const wait = bus_cycle.calculateBusCycles(logical_addr, 2, &self.bus_cycle_sm.config);
            if (wait > 4) self.addSplitCyclePenalty(wait - 4);
        }
        switch (self.portWidthFor(logical_addr)) {
            .Width8 => {
                self.addSplitCyclePenalty(1);
                try self.write8BusRaw(logical_addr, @truncate(value >> 8), access);
                try self.write8BusRaw(logical_addr + 1, @truncate(value & 0xFF), access);
            },
            else => try self.write16BusRaw(logical_addr, value, access),
        }
    }

    pub fn write32Bus(self: *Memory, logical_addr: u32, value: u32, access: BusAccess) !void {
        if (self.bus_cycle_enabled) {
            const wait = bus_cycle.calculateBusCycles(logical_addr, 4, &self.bus_cycle_sm.config);
            if (wait > 4) self.addSplitCyclePenalty(wait - 4);
        }
        switch (self.portWidthFor(logical_addr)) {
            .Width8 => {
                self.addSplitCyclePenalty(3);
                try self.write8BusRaw(logical_addr, @truncate(value >> 24), access);
                try self.write8BusRaw(logical_addr + 1, @truncate((value >> 16) & 0xFF), access);
                try self.write8BusRaw(logical_addr + 2, @truncate((value >> 8) & 0xFF), access);
                try self.write8BusRaw(logical_addr + 3, @truncate(value & 0xFF), access);
            },
            .Width16 => {
                self.addSplitCyclePenalty(1);
                try self.write16BusRaw(logical_addr, @truncate(value >> 16), access);
                try self.write16BusRaw(logical_addr + 2, @truncate(value & 0xFFFF), access);
            },
            .Width32 => try self.write32BusRaw(logical_addr, value, access),
        }
    }

    pub fn read8(self: *const Memory, addr: u32) !u8 {
        // 68020: Full 32-bit addressing (no mask)
        if (addr >= self.size) {
            return error.InvalidAddress;
        }
        return self.data[addr];
    }

    pub fn read16(self: *const Memory, addr: u32) !u16 {
        // 68000 compatibility: check alignment
        if (self.enforce_alignment and (addr & 1) != 0) {
            return error.AddressError;
        }

        // 68020: Full 32-bit addressing
        if (addr + 1 >= self.size) {
            return error.InvalidAddress;
        }
        // Big-endian (Motorola byte order)
        const high: u16 = self.data[addr];
        const low: u16 = self.data[addr + 1];
        return (high << 8) | low;
    }

    pub fn read32(self: *const Memory, addr: u32) !u32 {
        // 68000 compatibility: check alignment
        if (self.enforce_alignment and (addr & 1) != 0) {
            return error.AddressError;
        }

        // 68020: Full 32-bit addressing
        if (addr + 3 >= self.size) {
            return error.InvalidAddress;
        }
        // Big-endian
        const b0: u32 = self.data[addr];
        const b1: u32 = self.data[addr + 1];
        const b2: u32 = self.data[addr + 2];
        const b3: u32 = self.data[addr + 3];
        return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3;
    }

    pub fn write8(self: *Memory, addr: u32, value: u8) !void {
        // 68020: Full 32-bit addressing
        if (addr >= self.size) {
            return error.InvalidAddress;
        }
        self.data[addr] = value;
    }

    pub fn write16(self: *Memory, addr: u32, value: u16) !void {
        // 68000 compatibility: check alignment
        if (self.enforce_alignment and (addr & 1) != 0) {
            return error.AddressError;
        }

        // 68020: Full 32-bit addressing
        if (addr + 1 >= self.size) {
            return error.InvalidAddress;
        }
        // Big-endian
        self.data[addr] = @truncate(value >> 8);
        self.data[addr + 1] = @truncate(value & 0xFF);
    }

    pub fn write32(self: *Memory, addr: u32, value: u32) !void {
        // 68000 compatibility: check alignment
        if (self.enforce_alignment and (addr & 1) != 0) {
            return error.AddressError;
        }

        // 68020: Full 32-bit addressing
        if (addr + 3 >= self.size) {
            return error.InvalidAddress;
        }
        // Big-endian
        self.data[addr] = @truncate(value >> 24);
        self.data[addr + 1] = @truncate((value >> 16) & 0xFF);
        self.data[addr + 2] = @truncate((value >> 8) & 0xFF);
        self.data[addr + 3] = @truncate(value & 0xFF);
    }

    pub fn loadBinary(self: *Memory, data: []const u8, start_addr: u32) !void {
        // 68020: Full 32-bit addressing
        if (start_addr + data.len > self.size) {
            return error.InvalidAddress;
        }
        @memcpy(self.data[start_addr .. start_addr + data.len], data);
    }
};
