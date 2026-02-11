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

export fn m68k_create() ?*cpu.M68k {
    return m68k_create_with_memory(16 * 1024 * 1024);
}

export fn m68k_create_with_memory(memory_size: u32) ?*cpu.M68k {
    const allocator = gpa.allocator();
    const m68k = allocator.create(cpu.M68k) catch return null;
    m68k.* = cpu.M68k.initWithConfig(allocator, .{ .size = memory_size });
    return m68k;
}

export fn m68k_destroy(m68k: *cpu.M68k) void {
    const allocator = gpa.allocator();
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

test "basic library test" {
    const testing = std.testing;
    try testing.expect(true);
}
