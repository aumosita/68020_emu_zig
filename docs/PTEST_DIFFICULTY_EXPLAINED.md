# PTEST 명령어 난이도 분석

## 왜 PTEST가 가장 어려운가?

PTEST는 PMMU의 **"종합 시험"** 명령어입니다. 다른 모든 PMMU 기능을 통합하고, 상세한 진단 정보를 제공해야 합니다.

---

## PTEST vs 다른 PMMU 명령어 비교

### PLOAD (⭐⭐⭐⭐)
```zig
// PLOAD: 단순 목적
1. 주소 변환 수행
2. ATC에 결과 저장
3. 끝
```

### PTEST (⭐⭐⭐⭐⭐)
```zig
// PTEST: 복잡한 목적
1. 주소 변환 수행 (PLOAD와 동일)
2. ATC는 건드리지 않음 (read-only)
3. 변환 과정의 모든 단계 추적
4. 16비트 MMUSR에 상세 상태 인코딩
5. 선택적으로 물리 주소 반환
6. 모든 에러 케이스 구분
```

---

## PTEST가 처리해야 하는 것들

### 1. 완전한 주소 변환 (PLOAD 수준)

```zig
const result = try walkPageTable(addr, fc, root_ptr);
```

**복잡도**: ⭐⭐⭐⭐

---

### 2. MMUSR 레지스터 상세 인코딩

MMUSR은 16비트지만 **20가지 이상의 정보**를 담아야 합니다:

```
MMUSR 비트 맵:
 15: R (Resident) - 페이지가 메모리에 있음
 14: I (Invalid) - 디스크립터가 유효하지 않음
 13: WP (Write Protected) - 쓰기 금지
 12: M (Modified) - 페이지가 수정됨
 11: U (Used) - 페이지가 사용됨
 10: S (Supervisor) - 슈퍼바이저 전용
  9: G (Global) - 전역 페이지
  8: CI (Cache Inhibit) - 캐시 금지
7-4: Level - 테이블 레벨 (0-15)
3-0: 에러 코드
      0000: No error
      0001: Bus error on table fetch
      0010: Invalid descriptor
      0011: Limit violation
      0100: Write protect violation
      ...
```

**각 비트를 정확히 설정해야 합니다.**

```zig
fn encodeMmusrStatus(
    result: TranslationResult,
    error: ?TranslationError,
    level: u4,
) u16 {
    var mmusr: u16 = 0;
    
    if (error) |err| {
        mmusr |= 0x4000;  // Invalid bit
        mmusr |= switch (err) {
            .BusError => 0x0001,
            .InvalidDescriptor => 0x0002,
            .LimitViolation => 0x0003,
            .WriteProtect => 0x0004,
            // ... 10+ error types
        };
        mmusr |= @as(u16, level) << 4;
        return mmusr;
    }
    
    // Success case
    mmusr |= 0x8000;  // Resident
    mmusr |= @as(u16, result.write_protect) << 13;
    mmusr |= @as(u16, result.modified) << 12;
    mmusr |= @as(u16, result.used) << 11;
    mmusr |= @as(u16, result.supervisor) << 10;
    mmusr |= @as(u16, result.global) << 9;
    mmusr |= @as(u16, result.cache_inhibit) << 8;
    mmusr |= @as(u16, level) << 4;
    
    return mmusr;
}
```

**복잡도**: ⭐⭐⭐⭐⭐ (모든 조합 검증 필요)

---

### 3. 레벨별 중단 처리

PTEST는 `level` 파라미터를 받습니다:

```zig
// PTEST FC, (A0), #3, D0
// - FC: Function code
// - (A0): 테스트할 주소
// - #3: 레벨 3까지만 워킹
// - D0: 결과 주소 저장
```

**의미**: "레벨 3 테이블까지만 워킹하고 거기서 멈춰라"

```zig
fn walkPageTableWithLevel(
    addr: u32,
    fc: u3,
    root: u64,
    max_level: u4,
) !PartialTranslationResult {
    var current_level: u4 = 0;
    var current_ptr = root;
    
    while (current_level < max_level) {
        const descriptor = try fetchDescriptor(current_ptr);
        
        // Early termination 검사
        if (descriptor.is_page) {
            return .{
                .stopped_at_level = current_level,
                .descriptor = descriptor,
                .mmusr = encodePartialResult(descriptor, current_level),
            };
        }
        
        current_ptr = descriptor.next_table;
        current_level += 1;
    }
    
    // 지정된 레벨에서 중단
    return .{
        .stopped_at_level = max_level,
        .descriptor = last_descriptor,
        .mmusr = encodePartialResult(last_descriptor, max_level),
    };
}
```

**복잡도**: ⭐⭐⭐⭐ (부분 변환 상태 추적)

---

### 4. 모든 에러 케이스 구분

PTEST는 **10가지 이상의 에러**를 구분해야 합니다:

```zig
pub const TranslationError = error {
    BusErrorOnFetch,        // 테이블 fetch 중 버스 에러
    InvalidDescriptor,      // 디스크립터가 invalid
    LimitViolation,         // 주소가 limit 초과
    WriteProtectViolation,  // 쓰기 시도했지만 WP=1
    SupervisorViolation,    // 유저 모드에서 슈퍼바이저 페이지
    TableSearchDepth,       // 테이블 레벨이 너무 깊음
    IndirectLoop,           // Indirect descriptor 순환 참조
    InvalidFormat,          // 디스크립터 포맷 오류
    // ...
};
```

각 에러마다 다른 MMUSR 코드:

```zig
fn errorToMmusrCode(err: TranslationError) u4 {
    return switch (err) {
        .BusErrorOnFetch => 0x1,
        .InvalidDescriptor => 0x2,
        .LimitViolation => 0x3,
        .WriteProtectViolation => 0x4,
        .SupervisorViolation => 0x5,
        .TableSearchDepth => 0x6,
        .IndirectLoop => 0x7,
        .InvalidFormat => 0x8,
        // ... 더 많은 케이스
    };
}
```

**복잡도**: ⭐⭐⭐⭐⭐ (정확한 에러 구분이 핵심)

---

### 5. 물리 주소 반환 옵션

PTEST는 변환된 물리 주소를 레지스터에 저장할 수 있습니다:

```zig
// PTEST FC, (A0), #7, D0
//                    ^^^ D0에 물리 주소 저장
```

하지만 **에러 시에도** 의미 있는 값을 반환해야 합니다:

```zig
if (error) |err| {
    // 에러가 발생한 레벨의 디스크립터 주소 반환
    const descriptor_addr = calculateDescriptorAddress(
        current_table,
        addr,
        stopped_level,
    );
    return .{
        .mmusr = encodeMmusrError(err, stopped_level),
        .physical_addr = descriptor_addr,  // 에러 디버깅용
    };
}
```

**복잡도**: ⭐⭐⭐ (에러 케이스별 의미 정의)

---

## 왜 다른 명령어보다 어려운가?

### PMOVE (⭐⭐)
```
레지스터 읽기/쓰기만 수행
↓
단순 데이터 이동
```

### PFLUSH (⭐⭐)
```
ATC 엔트리 무효화
↓
플래그 clear만 수행
```

### PLOAD (⭐⭐⭐⭐)
```
주소 변환 수행
↓
ATC에 저장
↓
끝
```

### PTEST (⭐⭐⭐⭐⭐)
```
주소 변환 수행
↓
모든 단계 추적
↓
에러 10가지 구분
↓
MMUSR 16비트에 20가지 정보 인코딩
↓
레벨별 중단 처리
↓
물리 주소 계산
↓
ATC는 건드리지 않음
↓
모든 조합 테스트 필요
```

---

## 실제 구현 복잡도

### PLOAD 구현
```zig
fn executePload(m: *M68k, inst: *Instruction) !u32 {
    const addr = try getOperandValue(m, inst.src, .Long);
    const result = try m.pmmu.walkPageTable(addr, fc, root);
    m.pmmu.atc.insert(result);  // 단순 저장
    return 50;
}
```

**라인 수**: ~20줄

### PTEST 구현
```zig
fn executePtest(m: *M68k, inst: *Instruction) !u32 {
    const addr = try getOperandValue(m, inst.src, .Long);
    const fc = @truncate((inst.extension_word.? >> 10) & 0x7);
    const level = (inst.extension_word.? >> 13) & 0x7;
    const is_write = (inst.extension_word.? & 0x200) != 0;
    
    // ATC 조회 (read-only)
    if (m.pmmu.atc.lookup(addr, fc)) |entry| {
        m.pmmu.mmusr = encodeAtcHit(entry, is_write);
        if (inst.dst != .None) {
            try setOperandValue(m, inst.dst, entry.physical_addr, .Long);
        }
        return 20;
    }
    
    // 페이지 테이블 워킹 (레벨 제한)
    const result = m.pmmu.walkPageTableWithLevel(
        addr, fc, root, level
    ) catch |err| {
        // 에러별 MMUSR 인코딩
        m.pmmu.mmusr = encodeMmusrError(err, current_level);
        
        // 에러 시 디스크립터 주소 반환
        if (inst.dst != .None) {
            const desc_addr = calculateFaultAddress(err);
            try setOperandValue(m, inst.dst, desc_addr, .Long);
        }
        return 50;
    };
    
    // 성공 시 MMUSR 인코딩
    m.pmmu.mmusr = encodeMmusrSuccess(result);
    
    // 물리 주소 반환
    if (inst.dst != .None) {
        try setOperandValue(m, inst.dst, result.physical_addr, .Long);
    }
    
    return 50;
}

// + encodeMmusrSuccess() 함수 (~50줄)
// + encodeMmusrError() 함수 (~30줄)
// + encodeAtcHit() 함수 (~20줄)
// + calculateFaultAddress() 함수 (~30줄)
```

**라인 수**: ~200줄 (보조 함수 포함)

---

## 테스트 복잡도

### PLOAD 테스트
```zig
test "PLOAD basic" {
    // 1. 페이지 테이블 설정
    // 2. PLOAD 실행
    // 3. ATC 확인
}
```

**테스트 케이스**: ~10개

### PTEST 테스트
```zig
test "PTEST - all scenarios" {
    // 1. ATC hit (성공)
    // 2. Translation 성공 (레벨 0-7)
    // 3. 에러 케이스 10가지
    //    - Bus error
    //    - Invalid descriptor
    //    - Limit violation
    //    - Write protect
    //    - Supervisor violation
    //    - ...
    // 4. 물리 주소 반환 검증
    // 5. MMUSR 비트 조합 검증 (2^16 = 65536 조합)
    // 6. 레벨별 중단 (8 레벨)
    // 7. Read/Write 모드 조합
}
```

**테스트 케이스**: ~100개

---

## 결론

### PTEST가 어려운 핵심 이유

1. **통합 복잡도**: 모든 PMMU 기능을 사용
2. **상태 추적**: 변환 과정의 모든 단계 기록
3. **에러 처리**: 10+ 에러를 정확히 구분
4. **인코딩 복잡도**: 16비트에 20가지 정보 압축
5. **레벨 제어**: 부분 변환 지원
6. **Read-only**: ATC를 변경하지 않음 (까다로움)
7. **테스트 폭발**: 조합 경우의 수가 기하급수적

### 비유

- **PMOVE**: 파일 읽기/쓰기
- **PFLUSH**: 파일 삭제
- **PLOAD**: 컴파일
- **PTEST**: 컴파일러 + 디버거 + 프로파일러

PTEST는 PMMU의 **진단 도구**이자 **디버깅 인터페이스**입니다. A/UX 커널이 메모리 관리 문제를 진단할 때 사용하는 핵심 명령어입니다.

---

**예상 개발 시간**: 24-40시간 (PMMU 전체의 20%)  
**난이도**: ⭐⭐⭐⭐⭐ (5/5)
