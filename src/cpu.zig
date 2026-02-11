const std = @import("std");
const memory = @import("memory.zig");
const decoder = @import("decoder.zig");
const executor = @import("executor.zig");

pub const M68k = struct {
    // 데이터 레지스터 (D0-D7)
    d: [8]u32,
    
    // 주소 레지스터 (A0-A7)
    // A7은 스택 포인터(SP)
    a: [8]u32,
    
    // 프로그램 카운터
    pc: u32,
    
    // 상태 레지스터
    sr: u16,
    
    // 68020 전용 레지스터
    vbr: u32,  // Vector Base Register
    cacr: u32, // Cache Control Register
    caar: u32, // Cache Address Register
    
    // 메모리 서브시스템
    memory: memory.Memory,
    
    // 명령어 디코더
    decoder: decoder.Decoder,
    
    // 명령어 실행기
    executor: executor.Executor,
    
    // 사이클 카운터
    cycles: u64,
    
    // 할당자
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) M68k {
        return initWithConfig(allocator, .{});
    }
    
    pub fn initWithConfig(allocator: std.mem.Allocator, config: memory.MemoryConfig) M68k {
        return M68k{
            .d = [_]u32{0} ** 8,
            .a = [_]u32{0} ** 8,
            .pc = 0,
            .sr = 0x2700, // 슈퍼바이저 모드, 인터럽트 비활성화
            .vbr = 0,     // VBR 초기값 0 (68000 호환)
            .cacr = 0,    // 캐시 비활성화
            .caar = 0,
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
        // 모든 레지스터 초기화
        for (&self.d) |*reg| reg.* = 0;
        for (&self.a) |*reg| reg.* = 0;
        
        // VBR 사용하여 예외 벡터 읽기
        // 0x000000(VBR+0)에서 초기 SSP 읽기
        self.a[7] = self.memory.read32(self.getExceptionVector(0)) catch 0;
        
        // 0x000004(VBR+4)에서 초기 PC 읽기
        self.pc = self.memory.read32(self.getExceptionVector(1)) catch 0;
        
        // 슈퍼바이저 모드 설정, 인터럽트 비활성화
        self.sr = 0x2700;
        
        self.cycles = 0;
        
        // VBR은 리셋해도 보존됨 (68020 사양)
    }
    
    // 68020: 예외 벡터 주소 계산 (VBR 기반)
    pub fn getExceptionVector(self: *const M68k, vector_number: u8) u32 {
        return self.vbr + (@as(u32, vector_number) * 4);
    }
    
    pub fn readWord(self: *const M68k, addr: u32) u16 {
        return self.memory.read16(addr) catch 0;
    }
    
    pub fn step(self: *M68k) !u32 {
        // 명령어 페치
        const opcode = try self.memory.read16(self.pc);
        
        // Thread-local 전역 변수 사용 (Zig의 제약)
        M68k.current_instance = self;
        defer M68k.current_instance = null;
        
        const instruction = try self.decoder.decode(opcode, self.pc, &M68k.globalReadWord);
        
        // 명령어 실행
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

test "M68k 68020 registers initialization" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();
    
    // VBR, CACR, CAAR 초기값 확인
    try std.testing.expectEqual(@as(u32, 0), m68k.vbr);
    try std.testing.expectEqual(@as(u32, 0), m68k.cacr);
    try std.testing.expectEqual(@as(u32, 0), m68k.caar);
}

test "M68k VBR exception vector calculation" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();
    
    // VBR = 0 (기본값, 68000 호환)
    try std.testing.expectEqual(@as(u32, 0x0000), m68k.getExceptionVector(0));  // Reset SSP
    try std.testing.expectEqual(@as(u32, 0x0004), m68k.getExceptionVector(1));  // Reset PC
    try std.testing.expectEqual(@as(u32, 0x0008), m68k.getExceptionVector(2));  // Bus Error
    try std.testing.expectEqual(@as(u32, 0x0018), m68k.getExceptionVector(6));  // CHK
    
    // VBR 변경 (68020 기능)
    m68k.vbr = 0x10000;
    try std.testing.expectEqual(@as(u32, 0x10000), m68k.getExceptionVector(0));
    try std.testing.expectEqual(@as(u32, 0x10004), m68k.getExceptionVector(1));
    try std.testing.expectEqual(@as(u32, 0x10008), m68k.getExceptionVector(2));
    
    // VBR 최대값 테스트
    m68k.vbr = 0xFF000000;
    try std.testing.expectEqual(@as(u32, 0xFF000000), m68k.getExceptionVector(0));
    try std.testing.expectEqual(@as(u32, 0xFF0000FC), m68k.getExceptionVector(63));
}

test "M68k MOVEC VBR" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();
    
    // MOVEC D0, VBR (0x4E7B 0x0801)
    m68k.d[0] = 0x12345678;
    try m68k.memory.write16(0x1000, 0x4E7B);  // MOVEC to control
    try m68k.memory.write16(0x1002, 0x0801);  // D0 -> VBR
    m68k.pc = 0x1000;
    
    _ = try m68k.step();
    
    try std.testing.expectEqual(@as(u32, 0x12345678), m68k.vbr);
    try std.testing.expectEqual(@as(u32, 0x1004), m68k.pc);
}

test "M68k MOVEC from VBR" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();
    
    // MOVEC VBR, D1 (0x4E7A 0x1801)
    m68k.vbr = 0xDEADBEEF;
    try m68k.memory.write16(0x1000, 0x4E7A);  // MOVEC from control
    try m68k.memory.write16(0x1002, 0x1801);  // VBR -> D1
    m68k.pc = 0x1000;
    
    _ = try m68k.step();
    
    try std.testing.expectEqual(@as(u32, 0xDEADBEEF), m68k.d[1]);
    try std.testing.expectEqual(@as(u32, 0x1004), m68k.pc);
}

test "M68k MOVEC CACR" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();
    
    // MOVEC D2, CACR (0x4E7B 0x2002)
    m68k.d[2] = 0x00000001;  // Enable cache
    try m68k.memory.write16(0x1000, 0x4E7B);
    try m68k.memory.write16(0x1002, 0x2002);  // D2 -> CACR
    m68k.pc = 0x1000;
    
    _ = try m68k.step();
    
    try std.testing.expectEqual(@as(u32, 0x00000001), m68k.cacr);
    
    // MOVEC CACR, D3 (0x4E7A 0x3002)
    try m68k.memory.write16(0x1004, 0x4E7A);
    try m68k.memory.write16(0x1006, 0x3002);  // CACR -> D3
    
    _ = try m68k.step();
    
    try std.testing.expectEqual(@as(u32, 0x00000001), m68k.d[3]);
}

test "M68k EXTB.L sign extension" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();
    
    // EXTB.L D0 (0x49C0): 양수 byte -> long
    m68k.d[0] = 0xDEADBE42;  // byte = 0x42
    try m68k.memory.write16(0x1000, 0x49C0);  // EXTB.L D0
    m68k.pc = 0x1000;
    
    _ = try m68k.step();
    
    try std.testing.expectEqual(@as(u32, 0x00000042), m68k.d[0]);
    try std.testing.expectEqual(@as(u32, 0x1002), m68k.pc);
    
    // EXTB.L D1 (0x49C1): 음수 byte -> long
    m68k.d[1] = 0x123456FF;  // byte = 0xFF (-1)
    try m68k.memory.write16(0x1002, 0x49C1);  // EXTB.L D1
    
    _ = try m68k.step();
    
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), m68k.d[1]);
    
    // EXTB.L D2 (0x49C2): 0x80 (-128)
    m68k.d[2] = 0x00000080;
    try m68k.memory.write16(0x1004, 0x49C2);  // EXTB.L D2
    
    _ = try m68k.step();
    
    try std.testing.expectEqual(@as(u32, 0xFFFFFF80), m68k.d[2]);
    
    // EXTB.L D3 (0x49C3): 0x7F (127)
    m68k.d[3] = 0xFFFFFF7F;
    try m68k.memory.write16(0x1006, 0x49C3);  // EXTB.L D3
    
    _ = try m68k.step();
    
    try std.testing.expectEqual(@as(u32, 0x0000007F), m68k.d[3]);
}

test "M68k RTR - Return and Restore CCR" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();
    
    // 스택 설정
    m68k.a[7] = 0x2000;
    
    // 스택에 CCR과 PC 저장
    try m68k.memory.write16(0x2000, 0x001F);  // CCR: XNZVC all set
    try m68k.memory.write32(0x2002, 0x00003000);  // Return PC
    
    // RTR 명령어 (0x4E77)
    try m68k.memory.write16(0x1000, 0x4E77);
    m68k.pc = 0x1000;
    m68k.sr = 0x2700;  // Supervisor mode, all flags clear
    
    _ = try m68k.step();
    
    // CCR만 복원되어야 함 (하위 8비트)
    try std.testing.expectEqual(@as(u16, 0x271F), m68k.sr);
    try std.testing.expectEqual(@as(u32, 0x3000), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x2006), m68k.a[7]);
}

test "M68k RTE - Return from Exception" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();
    
    // 스택 설정
    m68k.a[7] = 0x2000;
    
    // 스택에 SR과 PC 저장
    try m68k.memory.write16(0x2000, 0x0015);  // SR: User mode, some flags
    try m68k.memory.write32(0x2002, 0x00004000);  // Return PC
    
    // RTE 명령어 (0x4E73)
    try m68k.memory.write16(0x1000, 0x4E73);
    m68k.pc = 0x1000;
    m68k.sr = 0x2700;  // Supervisor mode
    
    _ = try m68k.step();
    
    // SR 전체 복원
    try std.testing.expectEqual(@as(u16, 0x0015), m68k.sr);
    try std.testing.expectEqual(@as(u32, 0x4000), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x2006), m68k.a[7]);
}

test "M68k TRAP - Software Interrupt" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();
    
    // TRAP vector 설정 (TRAP #0 = vector 32)
    const vector_addr = m68k.getExceptionVector(32);
    try m68k.memory.write32(vector_addr, 0x00005000);  // Trap handler
    
    // 스택 설정
    m68k.a[7] = 0x3000;
    m68k.sr = 0x0000;  // User mode
    
    // TRAP #0 명령어 (0x4E40)
    try m68k.memory.write16(0x1000, 0x4E40);
    m68k.pc = 0x1000;
    
    _ = try m68k.step();
    
    // 스택에 SR과 PC 저장되어야 함
    const saved_sr = try m68k.memory.read16(0x3000 - 6);
    const saved_pc = try m68k.memory.read32(0x3000 - 4);
    
    try std.testing.expectEqual(@as(u16, 0x0000), saved_sr);
    try std.testing.expectEqual(@as(u32, 0x1002), saved_pc);
    try std.testing.expectEqual(@as(u32, 0x5000), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x3000 - 6), m68k.a[7]);
    
    // Supervisor 모드로 전환
    try std.testing.expect((m68k.sr & 0x2000) != 0);
}
