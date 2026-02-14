# PMMU 명령어 구현 난이도 평가

## 개요

68020 + 68851 PMMU (Paged Memory Management Unit) 명령어 8개의 구현 난이도를 평가합니다.

**평가 기준:**
- 기술적 복잡도 (1-5)
- 문서화 수준 (1-5)
- 예상 개발 시간 (시간)
- 테스트 난이도 (1-5)
- 전제 조건

**난이도 등급:**
- ⭐ 쉬움
- ⭐⭐ 보통
- ⭐⭐⭐ 어려움
- ⭐⭐⭐⭐ 매우 어려움
- ⭐⭐⭐⭐⭐ 극도로 어려움

---

## 전제 조건: PMMU 핵심 인프라 구현

모든 PMMU 명령어를 구현하기 전에 다음 인프라가 필요합니다:

### 1. Address Translation Cache (ATC)
```zig
pub const ATCEntry = struct {
    valid: bool,
    logical_addr: u32,
    physical_addr: u32,
    function_code: u3,
    page_size: u32,
    write_protect: bool,
    modified: bool,
    used: bool,
};

pub const ATC = struct {
    entries: [64]ATCEntry,  // 68851 has 64 entries
    // Lookup, insert, flush operations
};
```

**복잡도**: ⭐⭐⭐  
**예상 시간**: 8-16시간

### 2. Translation Table Walk Engine
```zig
pub fn walkPageTable(
    logical_addr: u32,
    function_code: u3,
    root_pointer: u64,
) !PhysicalAddress {
    // Multi-level page table traversal
    // Support for 2-level, 3-level, 4-level tables
    // Descriptor format parsing
}
```

**복잡도**: ⭐⭐⭐⭐  
**예상 시간**: 16-32시간

### 3. PMMU 레지스터 세트
```zig
pub const PMMURegisters = struct {
    crp: u64,       // CPU Root Pointer
    srp: u64,       // Supervisor Root Pointer
    tc: u32,        // Translation Control
    tt0: u32,       // Transparent Translation 0
    tt1: u32,       // Transparent Translation 1
    mmusr: u16,     // MMU Status Register
};
```

**복잡도**: ⭐⭐  
**예상 시간**: 4-8시간

### 4. 페이지 폴트 예외 처리
```zig
pub fn raisePageFault(
    logical_addr: u32,
    access_type: AccessType,
    fault_code: u8,
) void {
    // Format B exception frame (68020)
    // Push fault address, SSW, etc.
}
```

**복잡도**: ⭐⭐⭐  
**예상 시간**: 8-12시간

**총 전제 조건 구현 시간**: **40-70시간**

---

## PMMU 명령어별 난이도 평가

### 1. PMOVE - Move to/from PMMU Registers

#### 설명
PMMU 레지스터와 메모리 간 데이터 이동

```zig
// PMOVE CRP, (A0)  - Write CRP to memory
// PMOVE (A0), TC   - Load TC from memory
```

#### 난이도 분석

| 항목 | 평가 | 설명 |
|------|------|------|
| **기술적 복잡도** | ⭐⭐ | 레지스터 읽기/쓰기만 처리 |
| **문서화** | ⭐⭐⭐⭐ | MC68851 매뉴얼에 상세 설명 |
| **예상 시간** | 4-8시간 | 레지스터별 크기/형식만 처리 |
| **테스트 난이도** | ⭐⭐ | 레지스터 값 검증 간단 |
| **의존성** | PMMURegisters 구조체 |

#### 구현 예시
```zig
fn executePmove(m: *M68k, inst: *Instruction) !u32 {
    const reg = inst.control_reg.?;
    const to_pmmu = inst.is_to_control;
    
    if (to_pmmu) {
        // Load from EA into PMMU register
        const val = try getOperandValue64(m, inst.src);
        switch (reg) {
            0x000 => m.pmmu.tc = @truncate(val),
            0x002 => m.pmmu.srp = val,
            0x003 => m.pmmu.crp = val,
            // ...
        }
    } else {
        // Store PMMU register to EA
        const val = switch (reg) {
            0x000 => @as(u64, m.pmmu.tc),
            0x002 => m.pmmu.srp,
            0x003 => m.pmmu.crp,
            // ...
        };
        try setOperandValue64(m, inst.dst, val);
    }
    return 10;
}
```

#### 난이도 결론
**⭐⭐ 보통** - 레지스터 I/O만 처리, 단순한 편

---

### 2. PFLUSH - Flush Entry in ATC

#### 설명
ATC (Address Translation Cache) 엔트리를 무효화

```zig
// PFLUSH (A0)      - Flush specific entry
// PFLUSHA          - Flush all entries
```

#### 난이도 분석

| 항목 | 평가 | 설명 |
|------|------|------|
| **기술적 복잡도** | ⭐⭐ | ATC 엔트리 무효화만 필요 |
| **문서화** | ⭐⭐⭐⭐ | 매뉴얼에 명확히 설명 |
| **예상 시간** | 2-4시간 | ATC 구조 가정 시 간단 |
| **테스트 난이도** | ⭐⭐⭐ | ATC 상태 검증 필요 |
| **의존성** | ATC 구조체, lookup 함수 |

#### 구현 예시
```zig
fn executePflush(m: *M68k, inst: *Instruction) !u32 {
    const mode = (inst.extension_word.? >> 10) & 0x7;
    
    switch (mode) {
        0 => {
            // PFLUSHA - Flush all
            for (&m.pmmu.atc.entries) |*entry| {
                entry.valid = false;
            }
        },
        1 => {
            // PFLUSH (EA) - Flush specific address
            const addr = try getOperandValue(m, inst.src, .Long);
            m.pmmu.atc.flush(addr);
        },
        // ... other modes
    }
    return 20;
}
```

#### 난이도 결론
**⭐⭐ 보통** - ATC 관리만 필요, 복잡하지 않음

---

### 3. PLOAD - Load Entry into ATC

#### 설명
페이지 테이블을 워킹하여 ATC에 엔트리를 미리 로드

```zig
// PLOADR (A0)  - Load read access
// PLOADW (A0)  - Load write access
```

#### 난이도 분석

| 항목 | 평가 | 설명 |
|------|------|------|
| **기술적 복잡도** | ⭐⭐⭐⭐ | 페이지 테이블 워킹 필요 |
| **문서화** | ⭐⭐⭐ | 테이블 포맷 이해 필요 |
| **예상 시간** | 16-24시간 | Translation walk 엔진 필수 |
| **테스트 난이도** | ⭐⭐⭐⭐ | 복잡한 페이지 테이블 설정 필요 |
| **의존성** | Translation table walk, ATC |

#### 구현 예시
```zig
fn executePload(m: *M68k, inst: *Instruction) !u32 {
    const addr = try getOperandValue(m, inst.src, .Long);
    const is_write = (inst.extension_word.? & 0x200) != 0;
    const fc = @truncate((inst.extension_word.? >> 10) & 0x7);
    
    // Walk the page table
    const result = try m.pmmu.walkPageTable(
        addr,
        fc,
        if (fc < 4) m.pmmu.srp else m.pmmu.crp,
    );
    
    // Insert into ATC
    m.pmmu.atc.insert(ATCEntry{
        .valid = true,
        .logical_addr = addr & ~(result.page_size - 1),
        .physical_addr = result.physical_addr,
        .function_code = fc,
        .page_size = result.page_size,
        .write_protect = result.write_protect,
        .modified = false,
        .used = false,
    });
    
    return 50;  // Long operation
}
```

#### 난이도 결론
**⭐⭐⭐⭐ 매우 어려움** - 페이지 테이블 워킹 엔진 필수

---

### 4. PTEST - Test Logical Address

#### 설명
논리 주소를 변환하고 결과를 MMUSR 레지스터에 저장 (실제 ATC 변경 없음)

```zig
// PTESTW (A0)  - Test write access
// PTESTR (A0)  - Test read access
```

#### 난이도 분석

| 항목 | 평가 | 설명 |
|------|------|------|
| **기술적 복잡도** | ⭐⭐⭐⭐⭐ | 완전한 변환 로직 + 상태 리포팅 |
| **문서화** | ⭐⭐⭐ | MMUSR 비트 의미 복잡 |
| **예상 시간** | 24-40시간 | 가장 복잡한 PMMU 명령어 |
| **테스트 난이도** | ⭐⭐⭐⭐⭐ | 모든 엣지 케이스 검증 |
| **의존성** | Translation walk, ATC, 예외 처리 |

#### 구현 예시
```zig
fn executePtest(m: *M68k, inst: *Instruction) !u32 {
    const addr = try getOperandValue(m, inst.src, .Long);
    const is_write = (inst.extension_word.? & 0x200) != 0;
    const fc = @truncate((inst.extension_word.? >> 10) & 0x7);
    const level = (inst.extension_word.? >> 13) & 0x7;
    
    // Clear MMUSR
    m.pmmu.mmusr = 0;
    
    // Try ATC lookup first
    if (m.pmmu.atc.lookup(addr, fc)) |entry| {
        m.pmmu.mmusr |= 0x8000;  // Resident
        m.pmmu.mmusr |= @as(u16, entry.write_protect) << 13;
        m.pmmu.mmusr |= @as(u16, entry.modified) << 12;
        // ... set other bits
        return 20;
    }
    
    // Walk page table
    const result = m.pmmu.walkPageTable(addr, fc, root_ptr) catch |err| {
        // Set fault bits in MMUSR
        m.pmmu.mmusr |= 0x4000;  // Invalid
        m.pmmu.mmusr |= @intFromError(err) & 0xFF;
        return 50;
    };
    
    // Set success bits
    m.pmmu.mmusr |= 0x8000;  // Resident
    m.pmmu.mmusr |= @as(u16, result.write_protect) << 13;
    // ... detailed status reporting
    
    // Optionally write physical address to register
    if (inst.dst != .None) {
        try setOperandValue(m, inst.dst, result.physical_addr, .Long);
    }
    
    return 50;
}
```

#### 난이도 결론
**⭐⭐⭐⭐⭐ 극도로 어려움** - PMMU의 핵심, 모든 기능 통합 필요

---

### 5. PBcc - Branch on PMMU Condition

#### 설명
MMUSR 레지스터 상태에 따라 조건부 분기

```zig
// PBSR target   - Branch if supervisor
// PBCI target   - Branch if cache inhibit
```

#### 난이도 분석

| 항목 | 평가 | 설명 |
|------|------|------|
| **기술적 복잡도** | ⭐⭐ | 일반 Bcc와 유사 |
| **문서화** | ⭐⭐⭐⭐ | 조건 비트 명확 |
| **예상 시간** | 2-4시간 | Bcc 구현 재사용 가능 |
| **테스트 난이도** | ⭐⭐⭐ | MMUSR 상태 설정 필요 |
| **의존성** | MMUSR 레지스터 |

#### 구현 예시
```zig
fn executePBcc(m: *M68k, inst: *Instruction) !u32 {
    const cond = @truncate((inst.opcode >> 8) & 0xF);
    const take = evaluatePMMUCondition(m.pmmu.mmusr, cond);
    
    if (take) {
        const disp = switch (inst.src) {
            .Immediate16 => |v| @as(i32, @as(i16, @bitCast(v))),
            .Immediate32 => |v| @as(i32, @bitCast(v)),
            else => 0,
        };
        m.pc = @intCast(@as(i32, @intCast(m.pc)) + disp);
        return 10;
    } else {
        m.pc += inst.size;
        return 8;
    }
}

fn evaluatePMMUCondition(mmusr: u16, cond: u4) bool {
    return switch (cond) {
        0x0 => (mmusr & 0x0400) != 0,  // Bus error
        0x1 => (mmusr & 0x0800) != 0,  // Limit violation
        0x2 => (mmusr & 0x1000) != 0,  // Supervisor only
        0x3 => (mmusr & 0x0100) != 0,  // Write protected
        0x4 => (mmusr & 0x4000) != 0,  // Invalid
        0x5 => (mmusr & 0x8000) != 0,  // Modified
        // ... other conditions
        else => false,
    };
}
```

#### 난이도 결론
**⭐⭐ 보통** - Bcc 로직 재사용, MMUSR 비트만 추가

---

### 6. PDBcc - PMMU Decrement and Branch

#### 설명
데이터 레지스터를 감소시키고 PMMU 조건 검사 후 분기

```zig
// PDBSR D0, target
```

#### 난이도 분석

| 항목 | 평가 | 설명 |
|------|------|------|
| **기술적 복잡도** | ⭐⭐ | DBcc와 동일, MMUSR만 추가 |
| **문서화** | ⭐⭐⭐⭐ | DBcc 기반 |
| **예상 시간** | 2-4시간 | DBcc 재사용 |
| **테스트 난이도** | ⭐⭐ | 루프 검증 |
| **의존성** | MMUSR, PBcc |

#### 구현 예시
```zig
fn executePDBcc(m: *M68k, inst: *Instruction) !u32 {
    const cond = @truncate((inst.opcode >> 8) & 0xF);
    const reg = switch (inst.dst) {
        .DataReg => |r| r,
        else => 0,
    };
    
    if (evaluatePMMUCondition(m.pmmu.mmusr, cond)) {
        m.pc += inst.size;
        return 12;
    }
    
    m.d[reg] = (m.d[reg] & 0xFFFF0000) | 
               ((m.d[reg] -% 1) & 0xFFFF);
    
    if ((m.d[reg] & 0xFFFF) == 0xFFFF) {
        m.pc += inst.size;
        return 14;
    }
    
    const disp = switch (inst.src) {
        .Immediate16 => |v| @as(i32, @as(i16, @bitCast(v))),
        else => 0,
    };
    m.pc = @intCast(@as(i32, @intCast(m.pc)) + disp);
    return 10;
}
```

#### 난이도 결론
**⭐⭐ 보통** - DBcc 변형, 간단

---

### 7. PScc - Set on PMMU Condition

#### 설명
PMMU 조건에 따라 바이트를 0x00 또는 0xFF로 설정

```zig
// PSSR (A0)  - Set if supervisor
```

#### 난이도 분석

| 항목 | 평가 | 설명 |
|------|------|------|
| **기술적 복잡도** | ⭐ | Scc와 동일 |
| **문서화** | ⭐⭐⭐⭐ | Scc 기반 |
| **예상 시간** | 1-2시간 | Scc 재사용 |
| **테스트 난이도** | ⭐⭐ | 간단 |
| **의존성** | MMUSR |

#### 구현 예시
```zig
fn executePScc(m: *M68k, inst: *Instruction) !u32 {
    const cond = @truncate((inst.opcode >> 8) & 0xF);
    const val: u8 = if (evaluatePMMUCondition(m.pmmu.mmusr, cond)) 0xFF else 0x00;
    
    try setOperandValue(m, inst.dst, val, .Byte);
    m.pc += inst.size;
    return 8;
}
```

#### 난이도 결론
**⭐ 쉬움** - Scc 복사, MMUSR만 추가

---

### 8. PTRAPcc - Trap on PMMU Condition

#### 설명
PMMU 조건이 참이면 예외 발생

```zig
// PTRAPS      - Trap if supervisor
// PTRAPS #imm - Trap with immediate
```

#### 난이도 분석

| 항목 | 평가 | 설명 |
|------|------|------|
| **기술적 복잡도** | ⭐⭐ | TRAPcc와 동일 |
| **문서화** | ⭐⭐⭐⭐ | TRAPcc 기반 |
| **예상 시간** | 2-4시간 | TRAPcc 재사용 |
| **테스트 난이도** | ⭐⭐⭐ | 예외 프레임 검증 |
| **의존성** | MMUSR, TRAP 핸들러 |

#### 구현 예시
```zig
fn executePTRAPcc(m: *M68k, inst: *Instruction) !u32 {
    const cond = @truncate((inst.opcode >> 8) & 0xF);
    
    if (evaluatePMMUCondition(m.pmmu.mmusr, cond)) {
        return try executeTrap(m, 7);  // Vector 7: TRAPV
    }
    
    m.pc += inst.size;
    return 4;
}
```

#### 난이도 결론
**⭐⭐ 보통** - TRAPcc 변형, 간단

---

## 종합 평가

### 난이도 순위 (쉬운 순)

| 순위 | 명령어 | 난이도 | 예상 시간 | 의존성 |
|------|--------|--------|-----------|--------|
| 1 | **PScc** | ⭐ | 1-2시간 | MMUSR |
| 2 | **PFLUSH** | ⭐⭐ | 2-4시간 | ATC |
| 3 | **PMOVE** | ⭐⭐ | 4-8시간 | PMMURegisters |
| 4 | **PBcc** | ⭐⭐ | 2-4시간 | MMUSR |
| 5 | **PDBcc** | ⭐⭐ | 2-4시간 | MMUSR, PBcc |
| 6 | **PTRAPcc** | ⭐⭐ | 2-4시간 | MMUSR, TRAP |
| 7 | **PLOAD** | ⭐⭐⭐⭐ | 16-24시간 | Translation walk, ATC |
| 8 | **PTEST** | ⭐⭐⭐⭐⭐ | 24-40시간 | 모든 PMMU 기능 |

### 총 예상 개발 시간

| 항목 | 시간 |
|------|------|
| **전제 조건 인프라** | 40-70시간 |
| **간단한 명령어 6개** | 15-30시간 |
| **PLOAD** | 16-24시간 |
| **PTEST** | 24-40시간 |
| **테스트 및 디버깅** | 40-60시간 |
| **문서화** | 8-12시간 |
| **총계** | **143-236시간** |

**실제 예상**: **~200시간** (약 5주 풀타임)

---

## 핵심 도전 과제

### 1. 페이지 테이블 워킹 (최고 난이도)

**문제점:**
- 68851은 가변 레벨 테이블 지원 (2-8 레벨)
- 각 레벨마다 다른 디스크립터 포맷
- Early termination (Short/Long format)
- 인다이렉션 포인터

**복잡도**: ⭐⭐⭐⭐⭐  
**예상 시간**: 30-50시간

### 2. 디스크립터 포맷 파싱

68851 디스크립터 타입:
- Invalid (0)
- Page descriptor
- Short table descriptor
- Long table descriptor
- Indirect descriptor

각 타입마다 다른 비트 레이아웃.

**복잡도**: ⭐⭐⭐⭐  
**예상 시간**: 16-24시간

### 3. Transparent Translation

TC 레지스터의 TT0/TT1 필드:
- 특정 주소 범위를 변환 없이 통과
- CI (Cache Inhibit) 제어

**복잡도**: ⭐⭐⭐  
**예상 시간**: 8-12시간

### 4. 예외 처리 통합

PMMU 예외:
- Invalid descriptor
- Write protection violation
- Limit check violation
- Bus error during table walk

각각 다른 스택 프레임 포맷.

**복잡도**: ⭐⭐⭐⭐  
**예상 시간**: 16-24시간

---

## 테스트 난이도

### 테스트 인프라 구축
- 페이지 테이블 구조 생성 도구 필요
- 다양한 디스크립터 조합 테스트
- 예외 케이스 재현

**예상 시간**: 40-60시간

### 검증 방법
1. **실제 68851 동작 비교** (하드웨어 없음 → 불가능)
2. **A/UX 커널 코드 분석** (리버스 엔지니어링)
3. **MAME/UAE 에뮬레이터 참조** (오픈소스)

**권장**: MAME 소스 참조

---

## 구현 우선순위 (추천)

### Phase 1: 기초 (2-3주)
1. PMMU 레지스터 구조체
2. ATC 구조 및 lookup/flush
3. PMOVE, PFLUSH 구현
4. 간단한 명령어 (PBcc, PScc, etc.)

### Phase 2: 핵심 (3-4주)
1. Translation table walk 엔진
2. 디스크립터 파싱
3. PLOAD 구현
4. Transparent translation

### Phase 3: 고급 (2-3주)
1. PTEST 완전 구현
2. 예외 처리 통합
3. 엣지 케이스 처리

### Phase 4: 검증 (2-3주)
1. 광범위한 테스트 작성
2. A/UX 호환성 검증
3. 성능 최적화

---

## 결론

### 실용성 평가

| 항목 | 평가 |
|------|------|
| **총 개발 시간** | 200시간 (5주 풀타임) |
| **기술적 난이도** | ⭐⭐⭐⭐ (매우 높음) |
| **문서화 품질** | ⭐⭐⭐ (보통 - 역공학 필요) |
| **테스트 가능성** | ⭐⭐ (낮음 - 실제 HW 없음) |
| **Mac LC 필요성** | ❌ (불필요) |
| **A/UX 필요성** | ✅ (필수) |

### 권장 사항

**현재 단계**: ❌ **구현 보류**

**이유:**
1. Mac LC / System 6/7은 PMMU 미사용
2. 200시간 투자 대비 실질적 가치 없음
3. A/UX 지원이 확정된 후 구현

**구현 시점:**
- A/UX 부팅이 프로젝트 목표가 될 때
- 또는 68030/68040 지원으로 확장 시

**현재 우선순위:**
1. ✅ Mac LC ROM 부팅 성공
2. ✅ System 6.0.8 GUI 렌더링
3. ⬜ 성능 최적화 및 안정화
4. ⬜ (훨씬 나중) PMMU 구현

---

**최종 평가**: PMMU는 **기술적으로 가능하지만 현재 불필요**. ROM 부팅 성공 후 재검토 권장.
