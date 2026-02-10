# 컴파일 에러 분석 보고서

## 🔍 에러 1: decoder.zig:590 타입 불일치

### 문제
```
error: expected type '?decoder.Operand.Operand__struct_2960.Operand__struct_2960__struct_2962',
found '?decoder.Decoder.decodeFullExtension__struct_2963'
```

### 원인
**Line 590** 근처 코드:
```zig
return .{ .ComplexEA = .{
    .base_reg = if (base_suppress) null else reg,
    .is_pc_relative = is_pc,
    .index_reg = index_reg,  // 👈 타입 불일치
    ...
}}
```

**`index_reg` 타입 선언** (Line 576):
```zig
var index_reg: ?struct { reg: u3, is_addr: bool, is_long: bool, scale: u4 } = null;
```

**`Operand.ComplexEA.index_reg` 타입** (Line 109):
```zig
ComplexEA: struct {
    ...
    index_reg: ?struct {
        reg: u3,
        is_addr: bool,
        is_long: bool,
        scale: u4,
    },
    ...
},
```

### 문제점
- **익명 구조체 타입 불일치**: Zig는 각 익명 구조체를 별도 타입으로 취급
- Line 576의 구조체 ≠ Line 109의 구조체 (구조적으로 동일하지만 다른 타입)

### 해결 방법
**Option 1: 명명된 타입 사용**
```zig
// decoder.zig 최상위에 추가
pub const IndexReg = struct {
    reg: u3,
    is_addr: bool,
    is_long: bool,
    scale: u4,
};

// Operand 정의 수정
ComplexEA: struct {
    ...
    index_reg: ?IndexReg,
    ...
},

// Line 576 수정
var index_reg: ?IndexReg = null;
```

**Option 2: 타입 추론 사용**
```zig
// Line 576 수정 - 타입 명시 제거
var index_reg = null;  // 타입 추론

// 할당 시 타입 자동 결정
if (!index_suppress) {
    index_reg = .{ .reg = idx_reg, .is_addr = is_addr, .is_long = is_long, .scale = scale };
}
```

---

## 🔍 에러 2: executor.zig:1388 필드 없음

### 문제
```
error: no field named 'AddrDisplace' in enum '@typeInfo(decoder.Operand).Union.tag_type.?'
```

### 원인
**Line 1388** 코드:
```zig
.AddrDisplace => |info| m68k.a[info.reg] +% @as(u32, @bitCast(@as(i32, info.displacement))),
```

**`Operand` 정의** (decoder.zig Line 86):
```zig
pub const Operand = union(enum) {
    None: void,
    DataReg: u3,
    AddrReg: u3,
    Immediate8: u8,
    Immediate16: u16,
    Immediate32: u32,
    Address: u32,
    AddrIndirect: u3,
    AddrPostInc: u3,
    AddrPreDec: u3,
    BitField: struct { ... },
    ComplexEA: struct { ... },  // 👈 AddrDisplace 없음!
};
```

### 문제점
- **`AddrDisplace` 필드가 존재하지 않음**
- 68000의 `d16(An)` 어드레싱 모드를 `ComplexEA`로 통합했으나
- executor.zig에서 여전히 `AddrDisplace` 사용

### 해결 방법
**Option 1: `AddrDisplace` 필드 추가**
```zig
pub const Operand = union(enum) {
    ...
    AddrPreDec: u3,
    AddrDisplace: struct {  // 👈 추가
        reg: u3,
        displacement: i16,
    },
    BitField: struct { ... },
    ...
};
```

**Option 2: `ComplexEA` 사용하도록 수정**
```zig
// executor.zig:1388 수정
.ComplexEA => |ea| blk: {
    var addr = if (ea.base_reg) |reg| m68k.a[reg] else 0;
    addr +%= @as(u32, @bitCast(ea.base_disp));
    // index_reg, outer_disp 등 처리...
    break :blk addr;
},
```

**Option 3: 간단한 변위 모드 복원**
```zig
// Operand에 추가
AddrDisplaceWord: struct { reg: u3, disp: i16 },  // d16(An)
```

---

## 📋 권장 수정 계획

### Phase A: 최소 수정 (타입 에러만 해결)
**예상 시간**: 15-20분

1. **에러 1 해결**: `IndexReg` 타입 추출
   ```zig
   pub const IndexReg = struct {
       reg: u3, is_addr: bool, is_long: bool, scale: u4,
   };
   ```

2. **에러 2 해결**: `AddrDisplace` 필드 추가
   ```zig
   AddrDisplace: struct { reg: u3, displacement: i16 },
   ```

3. **테스트**: `zig build test` 통과 확인

### Phase B: ComplexEA 통합 (리팩토링)
**예상 시간**: 30-40분

1. `AddrDisplace` 사용을 `ComplexEA`로 변환
2. executor.zig의 모든 switch 케이스 수정
3. 단순 어드레싱 모드 테스트 작성

---

## 🎯 선택지

**A. 최소 수정만 진행** (15-20분)
   - 타입 에러만 해결
   - 기존 구조 유지
   - Phase 1 나머지 진행 가능

**B. 완전한 리팩토링** (30-40분)
   - ComplexEA로 통합
   - 더 깔끔한 구조
   - 68020 어드레싱 모드 준비 완료

**C. 하이브리드** (20-25분)
   - 에러 1: IndexReg 타입 추출
   - 에러 2: AddrDisplace 추가 (임시)
   - Phase 1 완료 후 리팩토링

---

## 💡 추천

**Option A (최소 수정)**를 추천합니다:
- 빠른 해결 (15-20분)
- Phase 1 완료 가능
- 리팩토링은 Phase 2-3에서

**다음 단계**: 대감의 승인 후 수정 시작
