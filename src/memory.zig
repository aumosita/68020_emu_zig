const std = @import("std");

pub const MemoryConfig = struct {
    size: u32 = 16 * 1024 * 1024,  // Default 16MB
    enforce_alignment: bool = false,  // true = 68000 mode, false = 68020 mode
    bus_hook: ?BusHook = null,
    bus_hook_ctx: ?*anyopaque = null,
    address_translator: ?AddressTranslator = null,
    address_translator_ctx: ?*anyopaque = null,
    default_port_width: PortWidth = .Width32,
    port_regions: []const PortRegion = &[_]PortRegion{},
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
    enforce_alignment: bool,  // 68000 compatibility mode
    bus_hook: ?BusHook,
    bus_hook_ctx: ?*anyopaque,
    address_translator: ?AddressTranslator,
    address_translator_ctx: ?*anyopaque,
    default_port_width: PortWidth,
    port_regions: []PortRegion,
    split_cycle_penalty: u32,
    tlb: [TlbEntries]TlbEntry,
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
                .default_port_width = config.default_port_width,
                .port_regions = &[_]PortRegion{},
                .split_cycle_penalty = 0,
                .tlb = [_]TlbEntry{.{}} ** TlbEntries,
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
                .default_port_width = config.default_port_width,
                .port_regions = &[_]PortRegion{},
                .split_cycle_penalty = 0,
                .tlb = [_]TlbEntry{.{}} ** TlbEntries,
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
            .default_port_width = config.default_port_width,
            .port_regions = regions,
            .split_cycle_penalty = 0,
            .tlb = [_]TlbEntry{.{}} ** TlbEntries,
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

    pub fn invalidateTranslationCache(self: *Memory) void {
        for (&self.tlb) |*entry| {
            entry.* = .{};
        }
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
        const addr = try @constCast(self).resolveBusAddress(logical_addr, access);
        if (addr >= self.size) return error.BusError;
        return self.data[addr];
    }

    fn read16BusRaw(self: *const Memory, logical_addr: u32, access: BusAccess) !u16 {
        const addr = try @constCast(self).resolveBusAddress(logical_addr, access);
        if (self.enforce_alignment and (addr & 1) != 0) return error.AddressError;
        if (addr + 1 >= self.size) return error.BusError;
        const high: u16 = self.data[addr];
        const low: u16 = self.data[addr + 1];
        return (high << 8) | low;
    }

    fn read32BusRaw(self: *const Memory, logical_addr: u32, access: BusAccess) !u32 {
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
        const addr = try self.resolveBusAddress(logical_addr, access);
        if (addr >= self.size) return error.BusError;
        self.data[addr] = value;
    }

    fn write16BusRaw(self: *Memory, logical_addr: u32, value: u16, access: BusAccess) !void {
        const addr = try self.resolveBusAddress(logical_addr, access);
        if (self.enforce_alignment and (addr & 1) != 0) return error.AddressError;
        if (addr + 1 >= self.size) return error.BusError;
        self.data[addr] = @truncate(value >> 8);
        self.data[addr + 1] = @truncate(value & 0xFF);
    }

    fn write32BusRaw(self: *Memory, logical_addr: u32, value: u32, access: BusAccess) !void {
        const addr = try self.resolveBusAddress(logical_addr, access);
        if (self.enforce_alignment and (addr & 1) != 0) return error.AddressError;
        if (addr + 3 >= self.size) return error.BusError;
        self.data[addr] = @truncate(value >> 24);
        self.data[addr + 1] = @truncate((value >> 16) & 0xFF);
        self.data[addr + 2] = @truncate((value >> 8) & 0xFF);
        self.data[addr + 3] = @truncate(value & 0xFF);
    }

    pub fn read8Bus(self: *const Memory, logical_addr: u32, access: BusAccess) !u8 {
        return self.read8BusRaw(logical_addr, access);
    }

    pub fn read16Bus(self: *const Memory, logical_addr: u32, access: BusAccess) !u16 {
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
        try self.write8BusRaw(logical_addr, value, access);
    }

    pub fn write16Bus(self: *Memory, logical_addr: u32, value: u16, access: BusAccess) !void {
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
        @memcpy(self.data[start_addr..start_addr + data.len], data);
    }
};

test "Memory read/write byte" {
    const allocator = std.testing.allocator;
    var mem = Memory.init(allocator);
    defer mem.deinit();
    
    try mem.write8(0x1000, 0x42);
    const value = try mem.read8(0x1000);
    try std.testing.expectEqual(@as(u8, 0x42), value);
}

test "Memory read/write word (big-endian)" {
    const allocator = std.testing.allocator;
    var mem = Memory.init(allocator);
    defer mem.deinit();
    
    try mem.write16(0x1000, 0x1234);
    const value = try mem.read16(0x1000);
    try std.testing.expectEqual(@as(u16, 0x1234), value);
    
    // Verify byte order
    const b0 = try mem.read8(0x1000);
    const b1 = try mem.read8(0x1001);
    try std.testing.expectEqual(@as(u8, 0x12), b0);
    try std.testing.expectEqual(@as(u8, 0x34), b1);
}

test "Memory read/write long (big-endian)" {
    const allocator = std.testing.allocator;
    var mem = Memory.init(allocator);
    defer mem.deinit();
    
    try mem.write32(0x1000, 0x12345678);
    const value = try mem.read32(0x1000);
    try std.testing.expectEqual(@as(u32, 0x12345678), value);
}

test "Memory custom size" {
    const allocator = std.testing.allocator;
    var mem = Memory.initWithConfig(allocator, .{ .size = 1024 * 1024 }); // 1MB
    defer mem.deinit();
    
    try std.testing.expectEqual(@as(u32, 1024 * 1024), mem.size);
}

test "Memory 32-bit addressing (68020)" {
    const allocator = std.testing.allocator;
    var mem = Memory.initWithConfig(allocator, .{ 
        .size = 32 * 1024 * 1024  // 32MB
    });
    defer mem.deinit();
    
    // Test address beyond 24-bit range (0xFFFFFF)
    const test_addr: u32 = 0x01ABCDEF;
    try mem.write32(test_addr, 0x12345678);
    const value = try mem.read32(test_addr);
    try std.testing.expectEqual(@as(u32, 0x12345678), value);
    
    // Verify it's not masked to 24-bit
    try mem.write8(0x01000000, 0xAA);
    const byte_val = try mem.read8(0x01000000);
    try std.testing.expectEqual(@as(u8, 0xAA), byte_val);
}

test "Memory alignment check (68000 mode)" {
    const allocator = std.testing.allocator;
    var mem = Memory.initWithConfig(allocator, .{ 
        .enforce_alignment = true 
    });
    defer mem.deinit();
    
    // Even address: should succeed
    try mem.write16(0x1000, 0x1234);
    const val1 = try mem.read16(0x1000);
    try std.testing.expectEqual(@as(u16, 0x1234), val1);
    
    // Odd address: should fail
    const result = mem.write16(0x1001, 0x5678);
    try std.testing.expectError(error.AddressError, result);
    
    const result2 = mem.read16(0x1001);
    try std.testing.expectError(error.AddressError, result2);
    
    // Long word alignment
    try mem.write32(0x2000, 0xDEADBEEF);
    const result3 = mem.write32(0x2001, 0x12345678);
    try std.testing.expectError(error.AddressError, result3);
}

test "Memory unaligned access (68020 mode)" {
    const allocator = std.testing.allocator;
    var mem = Memory.init(allocator);  // enforce_alignment = false by default
    defer mem.deinit();
    
    // Odd address: should succeed in 68020 mode
    try mem.write16(0x1001, 0x5678);
    const value = try mem.read16(0x1001);
    try std.testing.expectEqual(@as(u16, 0x5678), value);
    
    // Odd address long word
    try mem.write32(0x2001, 0xDEADBEEF);
    const value2 = try mem.read32(0x2001);
    try std.testing.expectEqual(@as(u32, 0xDEADBEEF), value2);
}

fn denyProgramFetch(_: ?*anyopaque, _: u32, access: BusAccess) BusSignal {
    if (access.space == .Program) return .bus_error;
    return .ok;
}

fn addTranslator(_: ?*anyopaque, logical_addr: u32, _: BusAccess) !u32 {
    return logical_addr + 0x1000;
}

const CountingTranslatorCtx = struct {
    calls: usize = 0,
    delta: u32 = 0,
};

fn countingTranslator(ctx: ?*anyopaque, logical_addr: u32, _: BusAccess) !u32 {
    const c: *CountingTranslatorCtx = @ptrCast(@alignCast(ctx.?));
    c.calls += 1;
    return logical_addr + c.delta;
}

const BusCallRecorder = struct {
    calls: usize = 0,
    addrs: [8]u32 = [_]u32{0} ** 8,

    fn reset(self: *BusCallRecorder) void {
        self.calls = 0;
        @memset(&self.addrs, 0);
    }
};

fn recordBusCalls(ctx: ?*anyopaque, logical_addr: u32, _: BusAccess) BusSignal {
    const recorder: *BusCallRecorder = @ptrCast(@alignCast(ctx.?));
    recorder.addrs[recorder.calls] = logical_addr;
    recorder.calls += 1;
    return .ok;
}

test "Memory bus hook and translator abstraction" {
    const allocator = std.testing.allocator;
    var mem = Memory.initWithConfig(allocator, .{
        .size = 0x4000,
        .bus_hook = denyProgramFetch,
        .address_translator = addTranslator,
    });
    defer mem.deinit();

    try mem.write8(0x1100, 0xAA); // physical write via legacy path

    // Program fetch denied by hook.
    const prg = mem.read8Bus(0x100, .{
        .function_code = 0b010,
        .space = .Program,
        .is_write = false,
    });
    try std.testing.expectError(error.BusError, prg);

    // Data read translated: logical 0x100 -> physical 0x1100.
    const data_val = try mem.read8Bus(0x100, .{
        .function_code = 0b001,
        .space = .Data,
        .is_write = false,
    });
    try std.testing.expectEqual(@as(u8, 0xAA), data_val);
}

test "Memory bus alignment violation returns address error" {
    const allocator = std.testing.allocator;
    var mem = Memory.initWithConfig(allocator, .{ .enforce_alignment = true });
    defer mem.deinit();

    const access = BusAccess{
        .function_code = 0b010,
        .space = .Data,
        .is_write = false,
    };
    try std.testing.expectError(error.AddressError, mem.read16Bus(0x1001, access));
}

test "Memory translation cache reduces address translator callback calls" {
    const allocator = std.testing.allocator;
    var ctx = CountingTranslatorCtx{ .delta = 0x1000 };
    var mem = Memory.initWithConfig(allocator, .{
        .size = 0x5000,
        .address_translator = countingTranslator,
        .address_translator_ctx = &ctx,
    });
    defer mem.deinit();

    try mem.write8(0x1100, 0xAA);
    try mem.write8(0x1110, 0xAB);
    try mem.write8(0x2100, 0xBB);

    const access = BusAccess{ .function_code = 0b001, .space = .Data, .is_write = false };

    // First access to page 0x0: translator called.
    try std.testing.expectEqual(@as(u8, 0xAA), try mem.read8Bus(0x0100, access));
    // Same page: must hit TLB without translator callback.
    try std.testing.expectEqual(@as(u8, 0xAB), try mem.read8Bus(0x0110, access));
    // Different page: translator called again.
    try std.testing.expectEqual(@as(u8, 0xBB), try mem.read8Bus(0x1100, access));

    try std.testing.expectEqual(@as(usize, 2), ctx.calls);
}

test "Memory translation cache flush restores translator callback path" {
    const allocator = std.testing.allocator;
    var ctx = CountingTranslatorCtx{ .delta = 0x1000 };
    var mem = Memory.initWithConfig(allocator, .{
        .size = 0x5000,
        .address_translator = countingTranslator,
        .address_translator_ctx = &ctx,
    });
    defer mem.deinit();

    try mem.write8(0x1100, 0xCC);
    try mem.write8(0x1104, 0xCD);
    try mem.write8(0x1108, 0xCE);

    const access = BusAccess{ .function_code = 0b001, .space = .Data, .is_write = false };
    try std.testing.expectEqual(@as(u8, 0xCC), try mem.read8Bus(0x0100, access));
    try std.testing.expectEqual(@as(usize, 1), ctx.calls);

    // Cached read: no additional translator callback.
    try std.testing.expectEqual(@as(u8, 0xCD), try mem.read8Bus(0x0104, access));
    try std.testing.expectEqual(@as(usize, 1), ctx.calls);

    mem.invalidateTranslationCache();
    try std.testing.expectEqual(@as(u8, 0xCE), try mem.read8Bus(0x0108, access));
    try std.testing.expectEqual(@as(usize, 2), ctx.calls);
}

test "Memory setAddressTranslator invalidates translation cache and uses new mapping" {
    const allocator = std.testing.allocator;
    var ctx = CountingTranslatorCtx{ .delta = 0x1000 };
    var mem = Memory.initWithConfig(allocator, .{
        .size = 0x6000,
        .address_translator = countingTranslator,
        .address_translator_ctx = &ctx,
    });
    defer mem.deinit();

    try mem.write8(0x1100, 0x11);
    try mem.write8(0x2100, 0x22);

    const access = BusAccess{ .function_code = 0b001, .space = .Data, .is_write = false };
    try std.testing.expectEqual(@as(u8, 0x11), try mem.read8Bus(0x0100, access));
    try std.testing.expectEqual(@as(usize, 1), ctx.calls);

    ctx.delta = 0x2000;
    mem.setAddressTranslator(countingTranslator, &ctx);
    try std.testing.expectEqual(@as(u8, 0x22), try mem.read8Bus(0x0100, access));
    try std.testing.expectEqual(@as(usize, 2), ctx.calls);
}

test "Memory dynamic bus sizing splits read access by port width" {
    const allocator = std.testing.allocator;
    const regions = [_]PortRegion{
        .{ .start = 0x0000, .end_exclusive = 0x0010, .width = .Width8 },
        .{ .start = 0x0010, .end_exclusive = 0x0020, .width = .Width16 },
    };
    var recorder = BusCallRecorder{};
    var mem = Memory.initWithConfig(allocator, .{
        .size = 0x100,
        .default_port_width = .Width32,
        .port_regions = &regions,
        .bus_hook = recordBusCalls,
        .bus_hook_ctx = &recorder,
    });
    defer mem.deinit();

    const read_access = BusAccess{
        .function_code = 0b001,
        .space = .Data,
        .is_write = false,
    };

    try mem.write32(0x0000, 0x11223344);
    recorder.reset();
    try std.testing.expectEqual(@as(u32, 0x11223344), try mem.read32Bus(0x0000, read_access));
    try std.testing.expectEqual(@as(usize, 4), recorder.calls);
    try std.testing.expectEqual(@as(u32, 0x0000), recorder.addrs[0]);
    try std.testing.expectEqual(@as(u32, 0x0001), recorder.addrs[1]);
    try std.testing.expectEqual(@as(u32, 0x0002), recorder.addrs[2]);
    try std.testing.expectEqual(@as(u32, 0x0003), recorder.addrs[3]);

    try mem.write32(0x0010, 0x55667788);
    recorder.reset();
    try std.testing.expectEqual(@as(u32, 0x55667788), try mem.read32Bus(0x0010, read_access));
    try std.testing.expectEqual(@as(usize, 2), recorder.calls);
    try std.testing.expectEqual(@as(u32, 0x0010), recorder.addrs[0]);
    try std.testing.expectEqual(@as(u32, 0x0012), recorder.addrs[1]);

    try mem.write32(0x0020, 0x99AABBCC);
    recorder.reset();
    try std.testing.expectEqual(@as(u32, 0x99AABBCC), try mem.read32Bus(0x0020, read_access));
    try std.testing.expectEqual(@as(usize, 1), recorder.calls);
    try std.testing.expectEqual(@as(u32, 0x0020), recorder.addrs[0]);
}

test "Memory dynamic bus sizing splits write access by port width" {
    const allocator = std.testing.allocator;
    const regions = [_]PortRegion{
        .{ .start = 0x0000, .end_exclusive = 0x0010, .width = .Width8 },
        .{ .start = 0x0010, .end_exclusive = 0x0020, .width = .Width16 },
    };
    var recorder = BusCallRecorder{};
    var mem = Memory.initWithConfig(allocator, .{
        .size = 0x100,
        .default_port_width = .Width32,
        .port_regions = &regions,
        .bus_hook = recordBusCalls,
        .bus_hook_ctx = &recorder,
    });
    defer mem.deinit();

    const write_access = BusAccess{
        .function_code = 0b001,
        .space = .Data,
        .is_write = true,
    };

    recorder.reset();
    try mem.write32Bus(0x0000, 0xA1B2C3D4, write_access);
    try std.testing.expectEqual(@as(usize, 4), recorder.calls);
    try std.testing.expectEqual(@as(u32, 0x0000), recorder.addrs[0]);
    try std.testing.expectEqual(@as(u32, 0x0001), recorder.addrs[1]);
    try std.testing.expectEqual(@as(u32, 0x0002), recorder.addrs[2]);
    try std.testing.expectEqual(@as(u32, 0x0003), recorder.addrs[3]);
    try std.testing.expectEqual(@as(u32, 0xA1B2C3D4), try mem.read32(0x0000));

    recorder.reset();
    try mem.write32Bus(0x0010, 0x11223344, write_access);
    try std.testing.expectEqual(@as(usize, 2), recorder.calls);
    try std.testing.expectEqual(@as(u32, 0x0010), recorder.addrs[0]);
    try std.testing.expectEqual(@as(u32, 0x0012), recorder.addrs[1]);
    try std.testing.expectEqual(@as(u32, 0x11223344), try mem.read32(0x0010));

    recorder.reset();
    try mem.write32Bus(0x0020, 0x55667788, write_access);
    try std.testing.expectEqual(@as(usize, 1), recorder.calls);
    try std.testing.expectEqual(@as(u32, 0x0020), recorder.addrs[0]);
    try std.testing.expectEqual(@as(u32, 0x55667788), try mem.read32(0x0020));
}
