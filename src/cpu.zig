const std = @import("std");
const memory = @import("memory.zig");
const decoder = @import("decoder.zig");
const executor = @import("executor.zig");

pub const M68k = struct {
    d: [8]u32,
    a: [8]u32,
    pc: u32,
    sr: u16,
    vbr: u32,
    cacr: u32,
    caar: u32,
    usp: u32,
    sfc: u3,
    dfc: u3,
    memory: memory.Memory,
    decoder: decoder.Decoder,
    executor: executor.Executor,
    cycles: u64,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) M68k {
        return initWithConfig(allocator, .{});
    }
    
    pub fn initWithConfig(allocator: std.mem.Allocator, config: memory.MemoryConfig) M68k {
        return M68k{
            .d = [_]u32{0} ** 8,
            .a = [_]u32{0} ** 8,
            .pc = 0,
            .sr = 0x2700,
            .vbr = 0,
            .cacr = 0,
            .caar = 0,
            .usp = 0,
            .sfc = 0,
            .dfc = 0,
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
        for (&self.d) |*reg| reg.* = 0;
        for (&self.a) |*reg| reg.* = 0;
        self.a[7] = self.memory.read32(self.getExceptionVector(0)) catch 0;
        self.pc = self.memory.read32(self.getExceptionVector(1)) catch 0;
        self.sr = 0x2700;
        self.cycles = 0;
    }
    
    pub fn getExceptionVector(self: *const M68k, vector_number: u8) u32 {
        return self.vbr + (@as(u32, vector_number) * 4);
    }
    
    pub fn readWord(self: *const M68k, addr: u32) u16 {
        return self.memory.read16(addr) catch 0;
    }
    
    pub fn step(self: *M68k) !u32 {
        const opcode = try self.memory.read16(self.pc);
        M68k.current_instance = self;
        defer M68k.current_instance = null;
        const instruction = try self.decoder.decode(opcode, self.pc, &M68k.globalReadWord);
        const cycles_used = try self.executor.execute(self, &instruction);
        self.cycles += cycles_used;
        return cycles_used;
    }
    
    threadlocal var current_instance: ?*const M68k = null;
    
    fn globalReadWord(addr: u32) u16 {
        if (M68k.current_instance) |inst| {
            return inst.memory.read16(addr) catch 0;
        }
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
    
    pub inline fn getFlag(self: *const M68k, comptime flag: u16) bool {
        return (self.sr & flag) != 0;
    }
    
    pub inline fn setFlag(self: *M68k, comptime flag: u16, value: bool) void {
        if (value) { self.sr |= flag; } else { self.sr &= ~flag; }
    }
    
    pub inline fn setFlags(self: *M68k, result: u32, size: decoder.DataSize) void {
        const mask: u32 = switch (size) {
            .Byte => 0xFF,
            .Word => 0xFFFF,
            .Long => 0xFFFFFFFF,
        };
        const masked = result & mask;
        self.setFlag(FLAG_Z, masked == 0);
        const sign_bit: u32 = switch (size) {
            .Byte => 0x80,
            .Word => 0x8000,
            .Long => 0x80000000,
        };
        self.setFlag(FLAG_N, (masked & sign_bit) != 0);
        self.setFlag(FLAG_V, false);
        self.setFlag(FLAG_C, false);
    }
    
    pub const FLAG_C: u16 = 1 << 0;
    pub const FLAG_V: u16 = 1 << 1;
    pub const FLAG_Z: u16 = 1 << 2;
    pub const FLAG_N: u16 = 1 << 3;
    pub const FLAG_X: u16 = 1 << 4;
};

test "M68k initialization" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();
    try std.testing.expectEqual(@as(u32, 0), m68k.pc);
    try std.testing.expectEqual(@as(u16, 0x2700), m68k.sr);
}

test "M68k MOVEC VBR" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();
    m68k.d[0] = 0x12345678;
    try m68k.memory.write16(0x1000, 0x4E7B);
    try m68k.memory.write16(0x1002, 0x0801);
    m68k.pc = 0x1000;
    _ = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0x12345678), m68k.vbr);
}

test "M68k RTE - Return from Exception" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();
    m68k.a[7] = 0x2000;
    try m68k.memory.write16(0x2000, 0x0015);
    try m68k.memory.write32(0x2002, 0x00004000);
    try m68k.memory.write16(0x2006, 0x0000);
    try m68k.memory.write16(0x1000, 0x4E73);
    m68k.pc = 0x1000;
    _ = try m68k.step();
    try std.testing.expectEqual(@as(u16, 0x0015), m68k.sr);
    try std.testing.expectEqual(@as(u32, 0x4000), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x2008), m68k.a[7]);
}

test "M68k TRAP - Software Interrupt" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();
    const vector_addr = m68k.getExceptionVector(32);
    try m68k.memory.write32(vector_addr, 0x00005000);
    m68k.a[7] = 0x3000;
    m68k.sr = 0x0000;
    try m68k.memory.write16(0x1000, 0x4E40);
    m68k.pc = 0x1000;
    _ = try m68k.step();
    const sp = 0x3000 - 8;
    try std.testing.expectEqual(@as(u16, 0x0000), try m68k.memory.read16(sp));
    try std.testing.expectEqual(@as(u32, 0x1002), try m68k.memory.read32(sp + 2));
    try std.testing.expectEqual(@as(u32, 0x5000), m68k.pc);
}

test "M68k ABCD - Add BCD" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();
    m68k.d[0] = 0x25;
    m68k.d[1] = 0x17;
    try m68k.memory.write16(0x1000, 0xC101);
    m68k.pc = 0x1000;
    _ = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0x42), m68k.d[0] & 0xFF);
}

test "M68k MOVEP - Move Peripheral" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();
    m68k.d[0] = 0x12345678;
    m68k.a[0] = 0x2000;
    try m68k.memory.write16(0x1000, 0x01C8);
    try m68k.memory.write16(0x1002, 0x0000);
    m68k.pc = 0x1000;
    _ = try m68k.step();
    try std.testing.expectEqual(@as(u8, 0x12), try m68k.memory.read8(0x2000));
    try std.testing.expectEqual(@as(u8, 0x34), try m68k.memory.read8(0x2002));
}

test "M68k CAS2 - Dual Compare and Swap" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();
    try m68k.memory.write32(0x2000, 100);
    try m68k.memory.write32(0x3000, 200);
    m68k.d[0] = 100; // Dc1
    m68k.d[1] = 200; // Dc2
    m68k.d[2] = 888; // Du1
    m68k.d[3] = 999; // Du2
    m68k.a[0] = 0x2000;
    m68k.a[1] = 0x3000;
    try m68k.memory.write16(0x1000, 0x0EFC);
    try m68k.memory.write16(0x1002, 0x8200); // A0, Du2, Dc0
    try m68k.memory.write16(0x1004, 0x9301); // A1, Du3, Dc1
    m68k.pc = 0x1000;
    _ = try m68k.step();
    try std.testing.expectEqual(@as(u32, 888), try m68k.memory.read32(0x2000));
    try std.testing.expectEqual(@as(u32, 999), try m68k.memory.read32(0x3000));
}

test "M68k CMPM - Compare Memory with Post-Increment" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();
    
    // Test CMPM.L (Ay)+,(Ax)+
    // Setup: A0 points to value 0x12345678, A1 points to value 0x12345678 (equal)
    m68k.a[0] = 0x1000;
    m68k.a[1] = 0x2000;
    try m68k.memory.write32(0x1000, 0x12345678);
    try m68k.memory.write32(0x2000, 0x12345678);
    
    // CMPM.L (A1)+,(A0)+ - opcode: 0xB189 (size=10, Ax=0, Ay=1)
    try m68k.memory.write16(0x100, 0xB189);
    m68k.pc = 0x100;
    _ = try m68k.step();
    
    // Check: Z flag should be set (equal), both pointers incremented by 4
    try std.testing.expect((m68k.sr & M68k.FLAG_Z) != 0);
    try std.testing.expectEqual(@as(u32, 0x1004), m68k.a[0]);
    try std.testing.expectEqual(@as(u32, 0x2004), m68k.a[1]);
    
    // Test CMPM.W with different values
    m68k.a[2] = 0x3000;
    m68k.a[3] = 0x4000;
    try m68k.memory.write16(0x3000, 0x1234);
    try m68k.memory.write16(0x4000, 0x5678);
    
    // CMPM.W (A3)+,(A2)+ - opcode: 0xB54B (size=01, Ax=2, Ay=3)
    try m68k.memory.write16(0x102, 0xB54B);
    m68k.pc = 0x102;
    _ = try m68k.step();
    
    // Check: Z flag should be clear (not equal), N flag set (negative result)
    try std.testing.expect((m68k.sr & M68k.FLAG_Z) == 0);
    try std.testing.expect((m68k.sr & M68k.FLAG_N) != 0);
    try std.testing.expectEqual(@as(u32, 0x3002), m68k.a[2]);
    try std.testing.expectEqual(@as(u32, 0x4002), m68k.a[3]);
}

test "M68k ABCD - Add BCD with Extend" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();
    
    // Test ABCD D1,D0 - Add BCD digits
    // 0x29 + 0x48 = 0x77 in BCD
    m68k.d[0] = 0x29;
    m68k.d[1] = 0x48;
    m68k.sr &= ~M68k.FLAG_X; // Clear X flag
    
    // ABCD D1,D0 - opcode: 0xC101 (Dx=0, Dy=1, mode=register)
    try m68k.memory.write16(0x100, 0xC101);
    m68k.pc = 0x100;
    _ = try m68k.step();
    
    try std.testing.expectEqual(@as(u8, 0x77), @as(u8, @truncate(m68k.d[0])));
    try std.testing.expect((m68k.sr & M68k.FLAG_C) == 0); // No carry
    
    // Test with carry: 0x99 + 0x01 = 0x00 with carry
    m68k.d[2] = 0x99;
    m68k.d[3] = 0x01;
    m68k.sr &= ~M68k.FLAG_X;
    
    // ABCD D3,D2 - opcode: 0xC503
    try m68k.memory.write16(0x102, 0xC503);
    m68k.pc = 0x102;
    _ = try m68k.step();
    
    try std.testing.expectEqual(@as(u8, 0x00), @as(u8, @truncate(m68k.d[2])));
    try std.testing.expect((m68k.sr & M68k.FLAG_C) != 0); // Carry set
    try std.testing.expect((m68k.sr & M68k.FLAG_X) != 0); // Extend set
}

test "M68k SBCD - Subtract BCD with Extend" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();
    
    // Test SBCD D1,D0 - Subtract BCD
    // 0x77 - 0x48 = 0x29 in BCD
    m68k.d[0] = 0x77;
    m68k.d[1] = 0x48;
    m68k.sr &= ~M68k.FLAG_X;
    
    // SBCD D1,D0 - opcode: 0x8101
    try m68k.memory.write16(0x100, 0x8101);
    m68k.pc = 0x100;
    _ = try m68k.step();
    
    try std.testing.expectEqual(@as(u8, 0x29), @as(u8, @truncate(m68k.d[0])));
    try std.testing.expect((m68k.sr & M68k.FLAG_C) == 0); // No borrow
}

test "M68k NBCD - Negate BCD with Extend" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();
    
    // Test NBCD D0 - Negate BCD
    // 0x00 - 0x48 = 0x52 in BCD (with borrow)
    m68k.d[0] = 0x48;
    m68k.sr &= ~M68k.FLAG_X;
    
    // NBCD D0 - opcode: 0x4800
    try m68k.memory.write16(0x100, 0x4800);
    m68k.pc = 0x100;
    _ = try m68k.step();
    
    try std.testing.expectEqual(@as(u8, 0x52), @as(u8, @truncate(m68k.d[0])));
    try std.testing.expect((m68k.sr & M68k.FLAG_C) != 0); // Borrow set
}

test "M68k MOVEC - Control Register Access" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();
    
    // Test MOVEC D0,SFC - Move to SFC (Source Function Code)
    m68k.d[0] = 5;
    // MOVEC D0,SFC - opcode: 0x4E7B 0x0000 (D0=0x0000, SFC=0)
    try m68k.memory.write16(0x100, 0x4E7B);
    try m68k.memory.write16(0x102, 0x0000);
    m68k.pc = 0x100;
    _ = try m68k.step();
    
    try std.testing.expectEqual(@as(u3, 5), m68k.sfc);
    
    // Test MOVEC D1,DFC - Move to DFC (Destination Function Code)
    m68k.d[1] = 3;
    // MOVEC D1,DFC - opcode: 0x4E7B 0x1001 (D1=0x1000, DFC=1)
    try m68k.memory.write16(0x104, 0x4E7B);
    try m68k.memory.write16(0x106, 0x1001);
    m68k.pc = 0x104;
    _ = try m68k.step();
    
    try std.testing.expectEqual(@as(u3, 3), m68k.dfc);
    
    // Test MOVEC A0,USP - Move to USP (User Stack Pointer)
    m68k.a[0] = 0x12345678;
    // MOVEC A0,USP - opcode: 0x4E7B 0x8800 (A0=0x8000, USP=0x800)
    try m68k.memory.write16(0x108, 0x4E7B);
    try m68k.memory.write16(0x10A, 0x8800);
    m68k.pc = 0x108;
    _ = try m68k.step();
    
    try std.testing.expectEqual(@as(u32, 0x12345678), m68k.usp);
    
    // Test MOVEC VBR,D2 - Move from VBR
    m68k.vbr = 0xABCDEF00;
    // MOVEC VBR,D2 - opcode: 0x4E7A 0x2801 (D2=0x2000, VBR=0x801)
    try m68k.memory.write16(0x10C, 0x4E7A);
    try m68k.memory.write16(0x10E, 0x2801);
    m68k.pc = 0x10C;
    _ = try m68k.step();
    
    try std.testing.expectEqual(@as(u32, 0xABCDEF00), m68k.d[2]);
    
    // Test MOVEC CACR,D3 - Move from CACR (Cache Control Register)
    m68k.cacr = 0x00000101;
    // MOVEC CACR,D3 - opcode: 0x4E7A 0x3002 (D3=0x3000, CACR=2)
    try m68k.memory.write16(0x110, 0x4E7A);
    try m68k.memory.write16(0x112, 0x3002);
    m68k.pc = 0x110;
    _ = try m68k.step();
    
    try std.testing.expectEqual(@as(u32, 0x00000101), m68k.d[3]);
}

test "M68k MOVEP - Move Peripheral Data" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();
    
    // Test MOVEP.W (d16,Ay),Dx - Memory to Register (Word)
    try m68k.memory.write8(0x1000, 0x12);
    try m68k.memory.write8(0x1002, 0x34);
    m68k.a[0] = 0x1000;
    
    // MOVEP.W 0(A0),D0 - opcode: 0x0148 0x0000
    try m68k.memory.write16(0x100, 0x0148);
    try m68k.memory.write16(0x102, 0x0000);
    m68k.pc = 0x100;
    
    const cycles = try m68k.step();
    
    try std.testing.expectEqual(@as(u32, 16), cycles);
    try std.testing.expectEqual(@as(u32, 0x104), m68k.pc);
    try std.testing.expectEqual(@as(u16, 0x1234), @as(u16, @truncate(m68k.d[0])));
}

test "M68k BFCHG - Bit Field Change" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();
    
    // Test BFCHG D0{4:8} - Change bits 4-11 (8 bits starting at offset 4)
    m68k.d[0] = 0x00000F00; // Bits 8-11 set (0x0F00)
    
    // BFCHG D0{4:8} - opcode: 0xEAC0 ext: 0x0108 (offset=4, width=8)
    try m68k.memory.write16(0x100, 0xEAC0);
    try m68k.memory.write16(0x102, 0x0108); // offset=4 (bits 10-6), width=8 (bits 4-0)
    m68k.pc = 0x100;
    _ = try m68k.step();
    
    // Bits 4-11 flipped: bits 4-7 (0->1=0xF0), bits 8-11 (1->0=0x00)
    try std.testing.expectEqual(@as(u32, 0x000000F0), m68k.d[0]);
}

test "M68k BFSET - Bit Field Set" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();
    
    // Test BFSET D0{0:16} - Set bits 0-15
    m68k.d[0] = 0x00000000;
    
    // BFSET D0{0:16} - opcode: 0xEEC0 ext: 0x0010 (offset=0, width=16)
    try m68k.memory.write16(0x100, 0xEEC0);
    try m68k.memory.write16(0x102, 0x0010);
    m68k.pc = 0x100;
    _ = try m68k.step();
    
    try std.testing.expectEqual(@as(u32, 0x0000FFFF), m68k.d[0]);
}

test "M68k BFCLR - Bit Field Clear" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();
    
    // Test BFCLR D1{8:8} - Clear bits 8-15
    m68k.d[1] = 0xFFFFFFFF;
    
    // BFCLR D1{8:8} - opcode: 0xECC1 ext: 0x0208 (offset=8, width=8)
    try m68k.memory.write16(0x100, 0xECC1);
    try m68k.memory.write16(0x102, 0x0208);
    m68k.pc = 0x100;
    _ = try m68k.step();
    
    try std.testing.expectEqual(@as(u32, 0xFFFF00FF), m68k.d[1]);
}

test "M68k RTE - Return from Exception with 68020 Stack Frame" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();
    
    // Test Format 0 (short format, 8 bytes)
    m68k.a[7] = 0x2000;
    try m68k.memory.write16(0x2000, 0x2700); // SR (supervisor mode)
    try m68k.memory.write32(0x2002, 0x1000); // PC
    try m68k.memory.write16(0x2006, 0x0018); // Format 0, Vector 6 (CHK)
    
    // RTE - opcode: 0x4E73
    try m68k.memory.write16(0x100, 0x4E73);
    m68k.pc = 0x100;
    _ = try m68k.step();
    
    try std.testing.expectEqual(@as(u16, 0x2700), m68k.sr);
    try std.testing.expectEqual(@as(u32, 0x1000), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x2008), m68k.a[7]); // SP += 8 (format 0)
    
    // Test Format 2 (6-word format, 12 bytes)
    m68k.a[7] = 0x3000;
    try m68k.memory.write16(0x3000, 0x2000); // SR
    try m68k.memory.write32(0x3002, 0x2000); // PC
    try m68k.memory.write16(0x3006, 0x201C); // Format 2, Vector 7 (TRAPV)
    
    m68k.pc = 0x100;
    _ = try m68k.step();
    
    try std.testing.expectEqual(@as(u16, 0x2000), m68k.sr);
    try std.testing.expectEqual(@as(u32, 0x2000), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x300C), m68k.a[7]); // SP += 12 (format 2)
}

test "M68k TRAP - Exception with Format/Vector Word" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();
    
    // Setup exception vector for TRAP #5 (vector 37 = 0x94)
    try m68k.memory.write32(37 * 4, 0x5000); // Exception handler at 0x5000
    
    m68k.a[7] = 0x2000; // Stack pointer
    m68k.sr = 0x2700;
    
    // TRAP #5 - opcode: 0x4E45
    try m68k.memory.write16(0x100, 0x4E45);
    m68k.pc = 0x100;
    _ = try m68k.step();
    
    // Check stack frame
    try std.testing.expectEqual(@as(u16, 0x2700), try m68k.memory.read16(0x1FF8)); // SR
    try std.testing.expectEqual(@as(u32, 0x0102), try m68k.memory.read32(0x1FFA)); // PC (after TRAP)
    const fv = try m68k.memory.read16(0x1FFE); // Format/Vector
    const format = fv >> 12;
    const vector = (fv & 0xFFF) / 4;
    try std.testing.expectEqual(@as(u4, 0), format); // Format 0
    try std.testing.expectEqual(@as(u8, 37), @as(u8, @truncate(vector))); // Vector 37 (TRAP #5)
    
    // Check PC jumped to exception handler
    try std.testing.expectEqual(@as(u32, 0x5000), m68k.pc);
    // Check supervisor mode
    try std.testing.expect((m68k.sr & 0x2000) != 0);
}





