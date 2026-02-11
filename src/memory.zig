const std = @import("std");

pub const MemoryConfig = struct {
    size: u32 = 16 * 1024 * 1024,  // Default 16MB
    enforce_alignment: bool = false,  // true = 68000 mode, false = 68020 mode
    bus_hook: ?BusHook = null,
    bus_hook_ctx: ?*anyopaque = null,
    address_translator: ?AddressTranslator = null,
    address_translator_ctx: ?*anyopaque = null,
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

pub const Memory = struct {
    // Memory data
    data: []u8,
    size: u32,
    enforce_alignment: bool,  // 68000 compatibility mode
    bus_hook: ?BusHook,
    bus_hook_ctx: ?*anyopaque,
    address_translator: ?AddressTranslator,
    address_translator_ctx: ?*anyopaque,
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
                .allocator = allocator,
            };
        };
        
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
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *Memory) void {
        if (self.data.len > 0) {
            self.allocator.free(self.data);
        }
    }

    pub fn setBusHook(self: *Memory, hook: ?BusHook, ctx: ?*anyopaque) void {
        self.bus_hook = hook;
        self.bus_hook_ctx = ctx;
    }

    pub fn setAddressTranslator(self: *Memory, translator: ?AddressTranslator, ctx: ?*anyopaque) void {
        self.address_translator = translator;
        self.address_translator_ctx = ctx;
    }

    fn resolveBusAddress(self: *const Memory, logical_addr: u32, access: BusAccess) !u32 {
        if (self.bus_hook) |hook| {
            switch (hook(self.bus_hook_ctx, logical_addr, access)) {
                .ok => {},
                .retry => return error.BusRetry,
                .halt => return error.BusHalt,
                .bus_error => return error.BusError,
            }
        }
        if (self.address_translator) |translator| {
            return translator(self.address_translator_ctx, logical_addr, access) catch return error.BusError;
        }
        return logical_addr;
    }

    pub fn read8Bus(self: *const Memory, logical_addr: u32, access: BusAccess) !u8 {
        const addr = try self.resolveBusAddress(logical_addr, access);
        if (addr >= self.size) return error.BusError;
        return self.data[addr];
    }

    pub fn read16Bus(self: *const Memory, logical_addr: u32, access: BusAccess) !u16 {
        const addr = try self.resolveBusAddress(logical_addr, access);
        if (self.enforce_alignment and (addr & 1) != 0) return error.BusError;
        if (addr + 1 >= self.size) return error.BusError;
        const high: u16 = self.data[addr];
        const low: u16 = self.data[addr + 1];
        return (high << 8) | low;
    }

    pub fn read32Bus(self: *const Memory, logical_addr: u32, access: BusAccess) !u32 {
        const addr = try self.resolveBusAddress(logical_addr, access);
        if (self.enforce_alignment and (addr & 1) != 0) return error.BusError;
        if (addr + 3 >= self.size) return error.BusError;
        const b0: u32 = self.data[addr];
        const b1: u32 = self.data[addr + 1];
        const b2: u32 = self.data[addr + 2];
        const b3: u32 = self.data[addr + 3];
        return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3;
    }

    pub fn write8Bus(self: *Memory, logical_addr: u32, value: u8, access: BusAccess) !void {
        const addr = try self.resolveBusAddress(logical_addr, access);
        if (addr >= self.size) return error.BusError;
        self.data[addr] = value;
    }

    pub fn write16Bus(self: *Memory, logical_addr: u32, value: u16, access: BusAccess) !void {
        const addr = try self.resolveBusAddress(logical_addr, access);
        if (self.enforce_alignment and (addr & 1) != 0) return error.BusError;
        if (addr + 1 >= self.size) return error.BusError;
        self.data[addr] = @truncate(value >> 8);
        self.data[addr + 1] = @truncate(value & 0xFF);
    }

    pub fn write32Bus(self: *Memory, logical_addr: u32, value: u32, access: BusAccess) !void {
        const addr = try self.resolveBusAddress(logical_addr, access);
        if (self.enforce_alignment and (addr & 1) != 0) return error.BusError;
        if (addr + 3 >= self.size) return error.BusError;
        self.data[addr] = @truncate(value >> 24);
        self.data[addr + 1] = @truncate((value >> 16) & 0xFF);
        self.data[addr + 2] = @truncate((value >> 8) & 0xFF);
        self.data[addr + 3] = @truncate(value & 0xFF);
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
