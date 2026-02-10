# 68020 마이그레이션 계획

## 목표
현재 68000 기반 에뮬레이터를 진정한 68020 에뮬레이터로 업그레이드

---

## Phase 1: 핵심 68020 아키텍처 (우선순위: 최고)

### 1.1 32비트 주소 공간
**파일**: `src/memory.zig`

**변경 사항**:
```zig
// BEFORE (68000 - 24비트)
pub fn read8(self: *const Memory, addr: u32) !u8 {
    const effective_addr = addr & 0xFFFFFF; // ❌ 24비트 마스크
    if (effective_addr >= self.size) {
        return error.InvalidAddress;
    }
    return self.data[effective_addr];
}

// AFTER (68020 - 32비트)
pub fn read8(self: *const Memory, addr: u32) !u8 {
    if (addr >= self.size) {
        return error.InvalidAddress;
    }
    return self.data[addr];
}
```

**모든 메모리 함수 수정**:
- `read8`, `read16`, `read32`
- `write8`, `write16`, `write32`
- `loadBinary`

**테스트 추가**:
```zig
test "Memory 32-bit addressing" {
    var mem = Memory.initWithConfig(allocator, .{ 
        .size = 32 * 1024 * 1024  // 32MB
    });
    defer mem.deinit();
    
    // 24비트 이상 주소 테스트
    try mem.write32(0x01ABCDEF, 0x12345678);
    const value = try mem.read32(0x01ABCDEF);
    try std.testing.expectEqual(@as(u32, 0x12345678), value);
}
```

---

### 1.2 선택적 정렬 체크 (68000 호환성)
**파일**: `src/memory.zig`

**MemoryConfig 확장**:
```zig
pub const MemoryConfig = struct {
    size: u32 = 16 * 1024 * 1024,
    enforce_alignment: bool = false,  // true = 68000 모드
};

pub const Memory = struct {
    data: []u8,
    size: u32,
    enforce_alignment: bool,  // 새 필드
    allocator: std.mem.Allocator,
    
    pub fn initWithConfig(allocator: std.mem.Allocator, config: MemoryConfig) Memory {
        // ...
        return Memory{
            .data = data,
            .size = mem_size,
            .enforce_alignment = config.enforce_alignment,
            .allocator = allocator,
        };
    }
    
    pub fn read16(self: *const Memory, addr: u32) !u16 {
        // 68000 모드: 홀수 주소 체크
        if (self.enforce_alignment and (addr & 1) != 0) {
            return error.AddressError;
        }
        
        if (addr + 1 >= self.size) {
            return error.InvalidAddress;
        }
        
        const high: u16 = self.data[addr];
        const low: u16 = self.data[addr + 1];
        return (high << 8) | low;
    }
    
    pub fn read32(self: *const Memory, addr: u32) !u32 {
        if (self.enforce_alignment and (addr & 1) != 0) {
            return error.AddressError;
        }
        // ...
    }
    
    // write16, write32도 동일하게 수정
};
```

**테스트**:
```zig
test "Memory alignment check (68000 mode)" {
    var mem = Memory.initWithConfig(allocator, .{ 
        .enforce_alignment = true 
    });
    defer mem.deinit();
    
    // 짝수 주소: 성공
    try mem.write16(0x1000, 0x1234);
    
    // 홀수 주소: 에러
    try std.testing.expectError(
        error.AddressError,
        mem.write16(0x1001, 0x5678)
    );
}

test "Memory unaligned access (68020 mode)" {
    var mem = Memory.init(allocator);  // enforce_alignment = false
    defer mem.deinit();
    
    // 홀수 주소: 성공 (68020)
    try mem.write16(0x1001, 0x5678);
    const value = try mem.read16(0x1001);
    try std.testing.expectEqual(@as(u16, 0x5678), value);
}
```

---

### 1.3 VBR (Vector Base Register) 추가
**파일**: `src/cpu.zig`

**CPU 구조체 확장**:
```zig
pub const M68k = struct {
    // 기존 레지스터
    d: [8]u32,
    a: [8]u32,
    pc: u32,
    sr: u16,
    
    // 68020 새 레지스터
    vbr: u32,  // Vector Base Register
    cacr: u32, // Cache Control Register (Phase 3)
    caar: u32, // Cache Address Register (Phase 3)
    
    // 기존 필드...
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
            .vbr = 0,     // VBR 초기값 0 (68000 호환)
            .cacr = 0,
            .caar = 0,
            .memory = memory.Memory.initWithConfig(allocator, config),
            .decoder = decoder.Decoder.init(),
            .executor = executor.Executor.init(),
            .cycles = 0,
            .allocator = allocator,
        };
    }
    
    pub fn reset(self: *M68k) void {
        // 기존 리셋 코드...
        
        // VBR은 리셋해도 0으로 초기화 안됨 (68020 사양)
        // 명시적으로 초기화하려면 MOVEC 사용
    }
    
    // 예외 벡터 주소 계산
    pub fn getExceptionVector(self: *const M68k, vector_number: u8) u32 {
        return self.vbr + (@as(u32, vector_number) * 4);
    }
};
```

**테스트**:
```zig
test "VBR exception vector calculation" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();
    
    // VBR = 0 (기본값)
    try std.testing.expectEqual(@as(u32, 0x0000), m68k.getExceptionVector(0));  // Reset SSP
    try std.testing.expectEqual(@as(u32, 0x0004), m68k.getExceptionVector(1));  // Reset PC
    try std.testing.expectEqual(@as(u32, 0x0008), m68k.getExceptionVector(2));  // Bus Error
    
    // VBR 변경
    m68k.vbr = 0x10000;
    try std.testing.expectEqual(@as(u32, 0x10000), m68k.getExceptionVector(0));
    try std.testing.expectEqual(@as(u32, 0x10004), m68k.getExceptionVector(1));
}
```

---

### 1.4 MOVEC 명령어 구현 (VBR 제어용)
**파일**: `src/decoder.zig`, `src/executor.zig`

**디코더 추가**:
```zig
// decoder.zig
pub const Instruction = struct {
    // 기존 필드...
    kind: InstructionKind,
    
    // MOVEC용 필드
    control_register: ?u16 = null,  // VBR=0x801, CACR=0x002 등
    direction: ?MovecDirection = null,
};

pub const MovecDirection = enum {
    ToControlReg,    // Rc <- Rn
    FromControlReg,  // Rn <- Rc
};

pub const InstructionKind = enum {
    // 기존 명령어...
    MOVEC,  // 새 명령어
};

// MOVEC opcode: 0x4E7A (Rc <- Rn), 0x4E7B (Rn <- Rc)
fn decodeMOVEC(opcode: u16, pc: u32, readNext: ReadNextFn) !Instruction {
    const ext_word = readNext(pc + 2);
    
    const direction: MovecDirection = if (opcode == 0x4E7B)
        .ToControlReg
    else
        .FromControlReg;
    
    const reg_num = @as(u8, @truncate((ext_word >> 12) & 0xF));
    const is_address = ((ext_word >> 15) & 1) != 0;
    const control_reg = ext_word & 0xFFF;
    
    return Instruction{
        .kind = .MOVEC,
        .size = .Long,  // MOVEC는 항상 Long
        .src_mode = if (is_address) .AddressRegDirect else .DataRegDirect,
        .src_reg = reg_num,
        .control_register = control_reg,
        .direction = direction,
        .length = 4,  // opcode (2) + extension (2)
    };
}
```

**실행기 추가**:
```zig
// executor.zig
fn executeMOVEC(self: *Executor, cpu: *M68k, inst: *const Instruction) !u32 {
    const control_reg = inst.control_register orelse return error.InvalidInstruction;
    
    switch (inst.direction.?) {
        .ToControlReg => {
            // Rc <- Rn
            const value = if (inst.src_mode == .DataRegDirect)
                cpu.d[inst.src_reg]
            else
                cpu.a[inst.src_reg];
            
            switch (control_reg) {
                0x801 => cpu.vbr = value,
                0x002 => cpu.cacr = value,
                0x802 => cpu.caar = value,
                // 기타 컨트롤 레지스터...
                else => return error.InvalidControlRegister,
            }
        },
        .FromControlReg => {
            // Rn <- Rc
            const value: u32 = switch (control_reg) {
                0x801 => cpu.vbr,
                0x002 => cpu.cacr,
                0x802 => cpu.caar,
                else => return error.InvalidControlRegister,
            };
            
            if (inst.src_mode == .DataRegDirect) {
                cpu.d[inst.src_reg] = value;
            } else {
                cpu.a[inst.src_reg] = value;
            }
        },
    }
    
    cpu.pc += inst.length;
    return 12;  // 12 사이클 (68020 사양)
}
```

**테스트**:
```zig
test "MOVEC VBR" {
    // MOVEC VBR, D0  (VBR -> D0)
    // MOVEC D1, VBR  (D1 -> VBR)
}
```

---

### 1.5 EXTB.L 명령어 구현
**파일**: `src/decoder.zig`, `src/executor.zig`

**디코더 수정**:
```zig
// EXT opcode: 0x4880 (byte->word), 0x48C0 (word->long), 0x49C0 (byte->long, 68020)
fn decodeEXT(opcode: u16, pc: u32) !Instruction {
    const reg = @as(u8, @truncate(opcode & 7));
    const mode = @as(u8, @truncate((opcode >> 6) & 7));
    
    const size: DataSize = switch (mode) {
        2 => .Word,  // byte -> word
        3 => .Long,  // word -> long
        7 => .Long,  // byte -> long (68020 EXTB)
        else => return error.InvalidOpcode,
    };
    
    return Instruction{
        .kind = .EXT,
        .size = size,
        .dst_mode = .DataRegDirect,
        .dst_reg = reg,
        .is_extb = (mode == 7),  // 새 필드
        .length = 2,
    };
}
```

**실행기 수정**:
```zig
fn executeEXT(self: *Executor, cpu: *M68k, inst: *const Instruction) !u32 {
    const reg = inst.dst_reg;
    
    if (inst.is_extb) {
        // EXTB.L: byte -> long (68020)
        const byte_val = @as(i8, @bitCast(@as(u8, @truncate(cpu.d[reg] & 0xFF))));
        cpu.d[reg] = @as(u32, @bitCast(@as(i32, byte_val)));
    } else {
        // 기존 EXT 로직
        switch (inst.size) {
            .Word => {
                // byte -> word
                const byte_val = @as(i8, @bitCast(@as(u8, @truncate(cpu.d[reg] & 0xFF))));
                const extended = @as(u16, @bitCast(@as(i16, byte_val)));
                cpu.d[reg] = (cpu.d[reg] & 0xFFFF0000) | extended;
            },
            .Long => {
                // word -> long
                const word_val = @as(i16, @bitCast(@as(u16, @truncate(cpu.d[reg] & 0xFFFF))));
                cpu.d[reg] = @as(u32, @bitCast(@as(i32, word_val)));
            },
            else => return error.InvalidSize,
        }
    }
    
    cpu.setFlags(cpu.d[reg], inst.size);
    cpu.pc += inst.length;
    return 4;  // 4 사이클
}
```

**테스트**:
```zig
test "EXTB.L sign extension" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();
    
    // 양수: 0x42 -> 0x00000042
    m68k.d[0] = 0xDEADBE42;
    try m68k.memory.write16(0x1000, 0x49C0);  // EXTB.L D0
    m68k.pc = 0x1000;
    _ = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0x00000042), m68k.d[0]);
    
    // 음수: 0xFF -> 0xFFFFFFFF
    m68k.d[1] = 0x123456FF;
    try m68k.memory.write16(0x1002, 0x49C1);  // EXTB.L D1
    m68k.pc = 0x1002;
    _ = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), m68k.d[1]);
}
```

---

## Phase 1 체크리스트

- [ ] **1.1** 32비트 주소 공간 (memory.zig 수정)
- [ ] **1.2** 선택적 정렬 체크 (MemoryConfig.enforce_alignment)
- [ ] **1.3** VBR 레지스터 추가 (cpu.zig)
- [ ] **1.4** MOVEC 명령어 구현 (decoder + executor)
- [ ] **1.5** EXTB.L 명령어 구현
- [ ] **테스트** 모든 변경사항에 대한 단위 테스트
- [ ] **문서** 68000_vs_68020.md 업데이트

---

## Phase 2: 나머지 68000 명령어 (TODO.md 기반)

Phase 1 완료 후 TODO.md의 미구현 명령어 구현:

### 2.1 프로그램 제어 (우선순위: 최고)
- [ ] JMP
- [ ] BSR
- [ ] DBcc
- [ ] Scc
- [ ] RTR
- [ ] RTE
- [ ] TRAP
- [ ] TRAPV

### 2.2 데이터 이동/교환
- [ ] EXG
- [ ] MOVEP
- [ ] CMPM

### 2.3 기타
- [ ] CHK
- [ ] TAS

### 2.4 BCD 연산 (선택적)
- [ ] ABCD
- [ ] SBCD
- [ ] NBCD

**예상 시간**: 4-6시간

---

## Phase 3: 68020 전용 명령어

### 3.1 비트 필드 연산
- [ ] BFCHG
- [ ] BFCLR
- [ ] BFEXTS
- [ ] BFEXTU
- [ ] BFFFO
- [ ] BFINS
- [ ] BFSET
- [ ] BFTST

### 3.2 멀티프로세서
- [ ] CAS
- [ ] CAS2

### 3.3 BCD 패킹
- [ ] PACK
- [ ] UNPK

### 3.4 기타
- [ ] BKPT

**예상 시간**: 6-8시간

---

## Phase 4: 68020 고급 어드레싱 모드

### 4.1 스케일 팩터
- [ ] `(d8, An, Xn.SIZE*SCALE)` - SCALE: 1, 2, 4, 8

### 4.2 메모리 간접
- [ ] `([bd, An], Xn, od)`
- [ ] `([bd, An, Xn], od)`

### 4.3 PC 상대 확장
- [ ] `(d8, PC, Xn.SIZE*SCALE)`
- [ ] PC 상대 메모리 간접

**예상 시간**: 4-6시간

---

## Phase 5: 캐시 & 성능

### 5.1 명령어 캐시 시뮬레이션
- [ ] 256바이트 캐시 구조체
- [ ] CACR/CAAR 레지스터 처리
- [ ] 캐시 히트/미스 시뮬레이션

### 5.2 사이클 정확도
- [ ] 68020 사이클 테이블 구축
- [ ] 명령어별 정확한 사이클 수

**예상 시간**: 3-4시간

---

## Phase 6: 선택적 고급 기능

### 6.1 코프로세서 인터페이스
- [ ] cpGEN, cpScc, cpDBcc 스텁
- [ ] FPU 플러그인 아키텍처

### 6.2 MMU 시뮬레이션
- [ ] 68851 PMMU 기본 구조
- [ ] 페이지 테이블 워킹

**예상 시간**: 8-12시간 (선택적)

---

## 총 예상 시간

- **Phase 1** (필수): 2-3시간
- **Phase 2** (68000 완성): 4-6시간
- **Phase 3** (68020 명령어): 6-8시간
- **Phase 4** (어드레싱): 4-6시간
- **Phase 5** (성능): 3-4시간
- **Phase 6** (고급, 선택적): 8-12시간

**총합**: 27-39시간 (Phase 1-5), 35-51시간 (전체)

---

## 다음 단계

1. **Phase 1.1 시작**: memory.zig 32비트 주소 수정
2. **테스트 작성**: 각 변경사항마다 테스트 먼저 작성 (TDD)
3. **점진적 커밋**: 각 기능마다 의미있는 커밋

**시작 명령**: 
```bash
# Phase 1.1: 32-bit addressing
zig build test
```
