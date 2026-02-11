# Phase 1.4: MOVEC 명령어 구현 가이드

## 목표
68020 VBR/CACR/CAAR 레지스터를 읽고 쓰는 MOVEC 명령어 구현

---

## 1. decoder.zig 수정

### 1.1 Instruction 구조체 확장

```zig
// decoder.zig - Instruction 구조체에 필드 추가
pub const Instruction = struct {
    opcode: u16,
    size: u8,
    mnemonic: Mnemonic,
    src: Operand,
    dst: Operand,
    data_size: DataSize,
    
    // MOVEC용 추가 필드 ⭐
    control_reg: ?u16 = null,  // VBR=0x801, CACR=0x002, CAAR=0x802
    is_to_control: bool = false,  // true: Rc ← Rn, false: Rn ← Rc
    
    pub fn init() Instruction {
        return .{
            .opcode = 0,
            .size = 2,
            .mnemonic = .NOP,
            .src = .{ .None = {} },
            .dst = .{ .None = {} },
            .data_size = .Long,
            .control_reg = null,
            .is_to_control = false,
        };
    }
};
```

### 1.2 Mnemonic에 MOVEC 추가

```zig
pub const Mnemonic = enum {
    // 기존 명령어...
    
    // 시스템 제어
    TRAP, TRAPV,
    CHK,
    ILLEGAL,
    RESET, STOP,
    MOVEC,  // ⭐ 추가
    
    UNKNOWN,
};
```

### 1.3 MOVEC 디코더 추가

```zig
// decoder.zig - decode() 함수 내부에 추가
pub fn decode(self: *const Decoder, opcode: u16, pc: u32, read_word: *const fn(u32) u16) !Instruction {
    var current_pc = pc + 2;
    var inst = Instruction.init();
    inst.opcode = opcode;
    
    const high4 = (opcode >> 12) & 0xF;
    
    switch (high4) {
        // ... 기존 케이스들 ...
        
        0x4 => {
            // ... 기존 0x4xxx 케이스들 ...
            
            // MOVEC 체크 ⭐
            if (opcode == 0x4E7A or opcode == 0x4E7B) {
                // MOVEC
                inst.mnemonic = .MOVEC;
                inst.data_size = .Long;
                
                const ext_word = read_word(current_pc);
                current_pc += 2;
                
                // Extension word 형식:
                // 15    12 11  0
                // A/D Reg  Control Register
                const reg_num = @as(u8, @truncate((ext_word >> 12) & 0xF));
                const is_addr_reg = ((ext_word >> 15) & 1) != 0;
                const control_reg = ext_word & 0xFFF;
                
                inst.control_reg = control_reg;
                inst.is_to_control = (opcode == 0x4E7B);  // 0x4E7B = Rc ← Rn
                
                if (is_addr_reg) {
                    inst.src = .{ .AddrReg = @truncate(reg_num & 0x7) };
                } else {
                    inst.src = .{ .DataReg = @truncate(reg_num & 0x7) };
                }
                
                inst.size = 4;  // opcode(2) + extension(2)
            }
            // ... 나머지 0x4xxx 처리 ...
        },
        
        // ... 나머지 케이스들 ...
    }
    
    inst.size = @truncate(current_pc - pc);
    return inst;
}
```

---

## 2. executor.zig 수정

### 2.1 execute() 스위치에 MOVEC 추가

```zig
pub fn execute(self: *const Executor, m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    _ = self;
    
    switch (inst.mnemonic) {
        // ... 기존 케이스들 ...
        
        .MOVEC => return try executeMovec(m68k, inst),  // ⭐
        
        // ... 나머지 케이스들 ...
    }
}
```

### 2.2 executeMovec() 함수 구현

```zig
// executor.zig - 파일 끝에 추가
fn executeMovec(m68k: *cpu.M68k, inst: *const decoder.Instruction) !u32 {
    const control_reg = inst.control_reg orelse return error.InvalidInstruction;
    
    if (inst.is_to_control) {
        // Rc ← Rn (레지스터 → 컨트롤 레지스터)
        const value = switch (inst.src) {
            .DataReg => |reg| m68k.d[reg],
            .AddrReg => |reg| m68k.a[reg],
            else => return error.InvalidOperand,
        };
        
        switch (control_reg) {
            0x000 => {}, // SFC (Source Function Code) - 미구현
            0x001 => {}, // DFC (Destination Function Code) - 미구현
            0x002 => m68k.cacr = value,  // CACR
            0x800 => {}, // USP (User Stack Pointer) - 미구현
            0x801 => m68k.vbr = value,   // VBR ⭐
            0x802 => m68k.caar = value,  // CAAR
            else => return error.InvalidControlRegister,
        }
    } else {
        // Rn ← Rc (컨트롤 레지스터 → 레지스터)
        const value: u32 = switch (control_reg) {
            0x000 => 0,  // SFC
            0x001 => 0,  // DFC
            0x002 => m68k.cacr,  // CACR
            0x800 => 0,  // USP
            0x801 => m68k.vbr,   // VBR ⭐
            0x802 => m68k.caar,  // CAAR
            else => return error.InvalidControlRegister,
        };
        
        switch (inst.src) {
            .DataReg => |reg| m68k.d[reg] = value,
            .AddrReg => |reg| m68k.a[reg] = value,
            else => return error.InvalidOperand,
        }
    }
    
    m68k.pc += inst.size;
    return 12;  // 68020: 12 사이클 (데이터시트 기준)
}
```

---

## 3. 테스트 작성

### 3.1 cpu.zig 테스트 추가

```zig
// cpu.zig - 테스트 섹션에 추가
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
```

### 3.2 테스트 실행

```bash
cd C:\Users\lyon\.openclaw\workspace\projects\m68020-emu
.\zig-windows-x86_64-0.13.0\zig.exe test src/cpu.zig
```

**예상 출력**:
```
1/8 cpu.test.M68k initialization...OK
2/8 cpu.test.M68k custom memory size...OK
3/8 cpu.test.M68k 68020 registers initialization...OK
4/8 cpu.test.M68k VBR exception vector calculation...OK
5/8 cpu.test.M68k MOVEC VBR...OK
6/8 cpu.test.M68k MOVEC from VBR...OK
7/8 cpu.test.M68k MOVEC CACR...OK
All 8 tests passed.
```

---

## 4. 체크리스트

### decoder.zig
- [ ] `Instruction` 구조체에 `control_reg`, `is_to_control` 필드 추가
- [ ] `Mnemonic`에 `.MOVEC` 추가
- [ ] `decode()` 함수에 0x4E7A/0x4E7B 처리 추가
- [ ] Extension word 파싱 구현

### executor.zig
- [ ] `execute()` 스위치에 `.MOVEC` 케이스 추가
- [ ] `executeMovec()` 함수 구현
- [ ] VBR/CACR/CAAR 읽기/쓰기 처리
- [ ] 사이클 카운트 12 반환

### cpu.zig
- [ ] 테스트 3개 추가
- [ ] `zig test src/cpu.zig` 통과 확인

### 전체 빌드
- [ ] `zig build test` 통과 확인
- [ ] 기존 테스트 영향 없는지 확인

---

## 5. 예상 시간

- **decoder.zig 수정**: 15분
- **executor.zig 수정**: 10분
- **테스트 작성**: 10분
- **디버깅**: 5분

**총 예상 시간**: 30-40분

---

## 6. 다음 단계

MOVEC 완료 후:
- Phase 1.5: EXTB.L 명령어 구현
- Phase 1 완료 커밋
- Phase 2 시작 또는 다른 작업

---

**준비 완료**: 가이드에 따라 구현 시작 가능
