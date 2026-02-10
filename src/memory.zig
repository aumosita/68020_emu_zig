const std = @import("std");

pub const MemoryConfig = struct {
    size: u32 = 16 * 1024 * 1024,  // Default 16MB
};

pub const Memory = struct {
    // Memory data
    data: []u8,
    size: u32,
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
                .allocator = allocator,
            };
        };
        
        // Zero out memory
        @memset(data, 0);
        
        return Memory{
            .data = data,
            .size = mem_size,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *Memory) void {
        if (self.data.len > 0) {
            self.allocator.free(self.data);
        }
    }
    
    pub fn read8(self: *const Memory, addr: u32) !u8 {
        const effective_addr = addr & 0xFFFFFF; // 24-bit address mask
        if (effective_addr >= self.size) {
            return error.InvalidAddress;
        }
        return self.data[effective_addr];
    }
    
    pub fn read16(self: *const Memory, addr: u32) !u16 {
        const effective_addr = addr & 0xFFFFFF;
        if (effective_addr + 1 >= self.size) {
            return error.InvalidAddress;
        }
        // Big-endian (Motorola byte order)
        const high: u16 = self.data[effective_addr];
        const low: u16 = self.data[effective_addr + 1];
        return (high << 8) | low;
    }
    
    pub fn read32(self: *const Memory, addr: u32) !u32 {
        const effective_addr = addr & 0xFFFFFF;
        if (effective_addr + 3 >= self.size) {
            return error.InvalidAddress;
        }
        // Big-endian
        const b0: u32 = self.data[effective_addr];
        const b1: u32 = self.data[effective_addr + 1];
        const b2: u32 = self.data[effective_addr + 2];
        const b3: u32 = self.data[effective_addr + 3];
        return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3;
    }
    
    pub fn write8(self: *Memory, addr: u32, value: u8) !void {
        const effective_addr = addr & 0xFFFFFF;
        if (effective_addr >= self.size) {
            return error.InvalidAddress;
        }
        self.data[effective_addr] = value;
    }
    
    pub fn write16(self: *Memory, addr: u32, value: u16) !void {
        const effective_addr = addr & 0xFFFFFF;
        if (effective_addr + 1 >= self.size) {
            return error.InvalidAddress;
        }
        // Big-endian
        self.data[effective_addr] = @truncate(value >> 8);
        self.data[effective_addr + 1] = @truncate(value & 0xFF);
    }
    
    pub fn write32(self: *Memory, addr: u32, value: u32) !void {
        const effective_addr = addr & 0xFFFFFF;
        if (effective_addr + 3 >= self.size) {
            return error.InvalidAddress;
        }
        // Big-endian
        self.data[effective_addr] = @truncate(value >> 24);
        self.data[effective_addr + 1] = @truncate((value >> 16) & 0xFF);
        self.data[effective_addr + 2] = @truncate((value >> 8) & 0xFF);
        self.data[effective_addr + 3] = @truncate(value & 0xFF);
    }
    
    pub fn loadBinary(self: *Memory, data: []const u8, start_addr: u32) !void {
        const effective_addr = start_addr & 0xFFFFFF;
        if (effective_addr + data.len > self.size) {
            return error.InvalidAddress;
        }
        @memcpy(self.data[effective_addr..effective_addr + data.len], data);
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
