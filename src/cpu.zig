const std = @import("std");
const memory = @import("memory.zig");
const decoder = @import("decoder.zig");
const executor = @import("executor.zig");

pub const M68k = struct {
    // Data registers (D0-D7)
    d: [8]u32,
    
    // Address registers (A0-A7)
    // A7 is the stack pointer (SP)
    a: [8]u32,
    
    // Program counter
    pc: u32,
    
    // Status register
    sr: u16,
    
    // Memory subsystem
    memory: memory.Memory,
    
    // Instruction decoder
    decoder: decoder.Decoder,
    
    // Instruction executor
    executor: executor.Executor,
    
    // Cycle counter
    cycles: u64,
    
    // Allocator
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) M68k {
        return initWithConfig(allocator, .{});
    }
    
    pub fn initWithConfig(allocator: std.mem.Allocator, config: memory.MemoryConfig) M68k {
        return M68k{
            .d = [_]u32{0} ** 8,
            .a = [_]u32{0} ** 8,
            .pc = 0,
            .sr = 0x2700, // Supervisor mode, interrupts disabled
            .memory = memory.Memory.initWithConfig(allocator, config),
            .decoder = decoder.Decoder.init(),
            .executor = executor.Executor.init(),
            .cycles = 0,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *M68k) void {
        self.memory.deinit();
    }
    
    pub fn reset(self: *M68k) void {
        // Reset all registers
        for (&self.d) |*reg| reg.* = 0;
        for (&self.a) |*reg| reg.* = 0;
        
        // Read initial SSP from 0x000000
        self.a[7] = self.memory.read32(0x000000) catch 0;
        
        // Read initial PC from 0x000004
        self.pc = self.memory.read32(0x000004) catch 0;
        
        // Set supervisor mode, interrupts disabled
        self.sr = 0x2700;
        
        self.cycles = 0;
    }
    
    pub fn step(self: *M68k) !u32 {
        // Fetch instruction
        const opcode = try self.memory.read16(self.pc);
        
        // Decode instruction (simplified for now)
        const instruction = try self.decoder.decode(opcode, self.pc, &dummyRead);
        
        // Execute instruction
        const cycles_used = try self.executor.execute(self, &instruction);
        
        self.cycles += cycles_used;
        return cycles_used;
    }
    
    fn dummyRead(_: u32) u16 {
        return 0;
    }
    
    pub fn execute(self: *M68k, target_cycles: u32) !u32 {
        var executed: u32 = 0;
        
        while (executed < target_cycles) {
            const cycles_used = try self.step();
            executed += cycles_used;
        }
        
        return executed;
    }
    
    // Condition code helpers
    pub inline fn getFlag(self: *const M68k, comptime flag: u16) bool {
        return (self.sr & flag) != 0;
    }
    
    pub inline fn setFlag(self: *M68k, comptime flag: u16, value: bool) void {
        if (value) {
            self.sr |= flag;
        } else {
            self.sr &= ~flag;
        }
    }
    
    pub inline fn setFlags(self: *M68k, result: u32, size: decoder.DataSize) void {
        const mask: u32 = switch (size) {
            .Byte => 0xFF,
            .Word => 0xFFFF,
            .Long => 0xFFFFFFFF,
        };
        const masked = result & mask;
        
        // Zero flag
        self.setFlag(FLAG_Z, masked == 0);
        
        // Negative flag
        const sign_bit: u32 = switch (size) {
            .Byte => 0x80,
            .Word => 0x8000,
            .Long => 0x80000000,
        };
        self.setFlag(FLAG_N, (masked & sign_bit) != 0);
        
        // Clear V and C for most data operations
        self.setFlag(FLAG_V, false);
        self.setFlag(FLAG_C, false);
    }
    
    // Flag bit positions
    pub const FLAG_C: u16 = 1 << 0;  // Carry
    pub const FLAG_V: u16 = 1 << 1;  // Overflow
    pub const FLAG_Z: u16 = 1 << 2;  // Zero
    pub const FLAG_N: u16 = 1 << 3;  // Negative
    pub const FLAG_X: u16 = 1 << 4;  // Extend
};

test "M68k initialization" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();
    
    try std.testing.expectEqual(@as(u32, 0), m68k.pc);
    try std.testing.expectEqual(@as(u16, 0x2700), m68k.sr);
}

test "M68k custom memory size" {
    const allocator = std.testing.allocator;
    var m68k = M68k.initWithConfig(allocator, .{ .size = 1024 * 1024 });
    defer m68k.deinit();
    
    try std.testing.expectEqual(@as(u32, 1024 * 1024), m68k.memory.size);
}
