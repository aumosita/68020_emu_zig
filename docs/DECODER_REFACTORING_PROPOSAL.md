# Decoder 계층화 리팩토링 제안

## 📊 현재 상태 분석

### 문제점
**decoder.zig 라인 수**: 616줄  
**decode() 함수**: 약 400줄의 거대한 switch 문

**현재 구조**:
```zig
switch (high4) {
    0x0 => {
        if (...) { /* 비트 연산 */ }
        else if (...) { /* 즉시값 연산 */ }
        else if (...) { /* ORI/ANDI/SUBI... */ }
        else { UNKNOWN }
    },
    0x4 => {
        if (opcode == 0x4E71) { NOP }
        else if (opcode == 0x4E75) { RTS }
        else if (opcode == 0x4E73) { RTE }
        else if (...) { /* 40개 이상의 if-else */ }
    },
    // ... 0x1~0xF까지 계속
}
```

**단점**:
- ❌ 가독성 낮음 (400줄 한 함수)
- ❌ 유지보수 어려움
- ❌ 테스트 어려움 (함수 단위 분리 불가)
- ❌ 컴파일 시간 증가
- ❌ 새 명령어 추가 시 복잡도 증가

---

## ✅ 제안: 계층화된 디코더 구조

### 1단계: 상위 4비트 분류 (현재와 동일)
```
0x0: 비트 연산 / 즉시값 연산
0x1-0x3: MOVE 계열
0x4: 특수 명령어 (NOP, JSR, TRAP 등)
0x5: ADDQ/SUBQ/DBcc/Scc
0x6: 분기 (Bcc, BRA, BSR)
0x7: MOVEQ
0x8: OR/DIVU/DIVS
0x9/0xD: SUB/ADD 계열
0xB: CMP/EOR
0xC: AND/MULU/MULS
0xE: 시프트/로테이트
```

### 2단계: 각 그룹별 전용 디코더 함수

**새 구조**:
```zig
pub const Decoder = struct {
    pub fn decode(...) !Instruction {
        const high4 = (opcode >> 12) & 0xF;
        
        return switch (high4) {
            0x0 => try self.decodeGroup0(opcode, pc, read_word),
            0x1, 0x2, 0x3 => try self.decodeMove(opcode, pc, read_word),
            0x4 => try self.decodeGroup4(opcode, pc, read_word),
            0x5 => try self.decodeGroup5(opcode, pc, read_word),
            0x6 => try self.decodeBranch(opcode, pc, read_word),
            0x7 => try self.decodeMoveq(opcode),
            0x8 => try self.decodeGroup8(opcode, pc, read_word),
            0x9, 0xD => try self.decodeArithmetic(opcode, pc, read_word),
            0xB => try self.decodeGroupB(opcode, pc, read_word),
            0xC => try self.decodeGroupC(opcode, pc, read_word),
            0xE => try self.decodeShiftRotate(opcode, pc, read_word),
            else => self.unknownInstruction(opcode),
        };
    }
    
    // 각 그룹별 전용 함수들
    fn decodeGroup0(self: *const Decoder, opcode: u16, pc: u32, read_word: ...) !Instruction {
        // 비트 연산, ORI, ANDI, SUBI, ADDI 등
        if ((opcode & 0xF1C0) == 0x0100 or ...) {
            return try self.decodeBitOp(opcode, pc, read_word);
        } else if ((opcode & 0xFF00) == 0x0000 or ...) {
            return try self.decodeImmediateOp(opcode, pc, read_word);
        }
        return self.unknownInstruction(opcode);
    }
    
    fn decodeGroup4(self: *const Decoder, opcode: u16, pc: u32, read_word: ...) !Instruction {
        // 특수 명령어들
        if (opcode == 0x4E71) return self.makeNop();
        if (opcode == 0x4E75) return self.makeRts();
        if (opcode == 0x4E73) return self.makeRte();
        if ((opcode & 0xFFF0) == 0x4E40) return try self.decodeTrap(opcode);
        if ((opcode & 0xFFC0) == 0x4E80) return try self.decodeJsr(opcode, pc, read_word);
        // ... 나머지
    }
    
    // 더 세분화된 헬퍼들
    fn decodeBitOp(...) !Instruction { /* BTST, BSET, BCLR, BCHG */ }
    fn decodeImmediateOp(...) !Instruction { /* ORI, ANDI, SUBI, ADDI, EORI, CMPI */ }
    fn decodeTrap(...) !Instruction { /* TRAP #n */ }
    fn decodeJsr(...) !Instruction { /* JSR */ }
    // ...
};
```

---

## 📈 장점

### 1. 가독성 향상
**Before**:
```zig
// 400줄짜리 하나의 함수
pub fn decode(...) { 
    switch (high4) {
        0x0 => { /* 80줄 */ },
        0x4 => { /* 120줄 */ },
        // ...
    }
}
```

**After**:
```zig
// decode() 함수: 20줄 (라우팅만)
// 각 그룹 함수: 20-50줄
pub fn decode(...) {
    return switch (high4) {
        0x0 => try self.decodeGroup0(...),  // 30줄
        0x4 => try self.decodeGroup4(...),  // 50줄
        // ...
    };
}
```

### 2. 유지보수 용이
- 각 그룹 독립적으로 수정 가능
- 새 명령어 추가 시 해당 그룹만 수정
- Git conflict 감소

### 3. 테스트 가능
```zig
test "Group 0: Bit operations" {
    const decoder = Decoder.init();
    
    // BTST
    const inst1 = try decoder.decodeGroup0(0x0100, 0, &dummy_read);
    try expectEqual(Mnemonic.BTST, inst1.mnemonic);
    
    // BCHG
    const inst2 = try decoder.decodeGroup0(0x0140, 0, &dummy_read);
    try expectEqual(Mnemonic.BCHG, inst2.mnemonic);
}

test "Group 4: Special instructions" {
    const decoder = Decoder.init();
    
    // NOP
    const inst1 = try decoder.decodeGroup4(0x4E71, 0, &dummy_read);
    try expectEqual(Mnemonic.NOP, inst1.mnemonic);
    
    // RTS
    const inst2 = try decoder.decodeGroup4(0x4E75, 0, &dummy_read);
    try expectEqual(Mnemonic.RTS, inst2.mnemonic);
}
```

### 4. 컴파일러 최적화
- 작은 함수들은 인라인 최적화 가능
- 분기 예측 최적화
- 코드 캐시 효율 향상

### 5. 문서화 자동화
```zig
/// Group 0: Bit operations and immediate operations
/// Opcodes: 0x0000-0x0FFF
/// Instructions: BTST, BSET, BCLR, BCHG, ORI, ANDI, SUBI, ADDI, EORI, CMPI
fn decodeGroup0(...)
```

---

## 📋 구현 계획

### Phase A: 준비 (10분)
1. 현재 decode() 함수 백업
2. 새 그룹 함수 스켈레톤 생성

### Phase B: 그룹별 마이그레이션 (1-2시간)
**우선순위 순서**:
1. ✅ Group 7 (MOVEQ) - 가장 단순 (5분)
2. ✅ Group 6 (Branch) - 단순 (10분)
3. ✅ Group 0 (Bit ops) - 중간 (20분)
4. ✅ Group 4 (Special) - 복잡 (30분)
5. ✅ Group 5, 8, 9/D, B, C, E - 나머지 (각 15-20분)

### Phase C: 테스트 (30분)
1. 각 그룹별 단위 테스트 작성
2. 통합 테스트 실행
3. 기존 테스트 통과 확인

### Phase D: 문서화 (20분)
1. 각 그룹 함수 docstring 추가
2. 명령어 매핑 테이블 작성

**총 예상 시간**: 2-3시간

---

## 🎯 예상 효과

### 코드 품질
- **가독성**: ⭐⭐⭐⭐⭐ (현재: ⭐⭐)
- **유지보수성**: ⭐⭐⭐⭐⭐ (현재: ⭐⭐)
- **테스트 커버리지**: ⭐⭐⭐⭐⭐ (현재: ⭐⭐⭐)

### 성능
- **컴파일 시간**: 약간 향상 (함수 분리로)
- **런타임**: 거의 동일 또는 약간 향상 (인라인 최적화)
- **바이너리 크기**: 동일

### 개발 생산성
- **새 명령어 추가 시간**: -50% (해당 그룹만 수정)
- **버그 수정 시간**: -60% (범위 좁힘)
- **코드 리뷰 시간**: -70% (작은 단위)

---

## 💡 추천

**A. 즉시 리팩토링** (2-3시간)
   - Phase 1 완료 전에 리팩토링
   - 깨끗한 구조에서 MOVEC/EXTB.L 추가

**B. Phase 1 완료 후 리팩토링** (2-3시간)
   - 기능 완성 우선
   - 별도 커밋으로 리팩토링

**C. Phase 2 시작하면서 리팩토링** (2-3시간)
   - 새 명령어 추가하면서 함께 정리
   - 점진적 개선

---

## 🔧 샘플 코드

### 계층화 전 (현재)
```zig
pub fn decode(...) !Instruction {
    switch (high4) {
        0x7 => {
            inst.mnemonic = .MOVEQ;
            inst.dst = .{ .DataReg = @truncate((opcode >> 9) & 0x7) };
            inst.src = .{ .Immediate8 = @truncate(opcode & 0xFF) };
        },
        // ... 400줄 계속 ...
    }
}
```

### 계층화 후 (제안)
```zig
pub fn decode(...) !Instruction {
    const high4 = (opcode >> 12) & 0xF;
    return switch (high4) {
        0x7 => self.decodeMoveq(opcode),
        0x6 => try self.decodeBranch(opcode, pc, read_word),
        // ... 간결한 라우팅
    };
}

fn decodeMoveq(self: *const Decoder, opcode: u16) Instruction {
    return .{
        .opcode = opcode,
        .size = 2,
        .mnemonic = .MOVEQ,
        .src = .{ .Immediate8 = @truncate(opcode & 0xFF) },
        .dst = .{ .DataReg = @truncate((opcode >> 9) & 0x7) },
        .data_size = .Long,
    };
}

fn decodeBranch(self: *const Decoder, opcode: u16, pc: *u32, read_word: ...) !Instruction {
    const condition: u8 = @truncate((opcode >> 8) & 0xF);
    const disp8: i8 = @bitCast(@as(u8, @truncate(opcode & 0xFF)));
    
    var inst = Instruction.init();
    inst.opcode = opcode;
    inst.mnemonic = switch (condition) {
        0x0 => .BRA,
        0x1 => .BSR,
        else => .Bcc,
    };
    
    // displacement 처리...
    return inst;
}
```

---

## 📊 비교

| 항목 | 현재 (단일 함수) | 제안 (계층화) |
|------|------------------|---------------|
| decode() 크기 | 400줄 | 20줄 |
| 평균 함수 크기 | 400줄 | 30줄 |
| 함수 개수 | 1개 | 15개 |
| 테스트 가능성 | 낮음 | 높음 |
| 새 명령어 추가 | 어려움 | 쉬움 |
| 코드 리뷰 | 어려움 | 쉬움 |

---

**결론**: 계층화는 **강력히 추천**합니다. 2-3시간 투자로 장기적으로 큰 이득을 얻을 수 있습니다.

**대감의 결정이 필요합니다**:
- **A**: 지금 바로 리팩토링
- **B**: Phase 1 완료 후 리팩토링
- **C**: Phase 2와 함께 리팩토링
- **D**: 나중에 (현재 구조 유지)
