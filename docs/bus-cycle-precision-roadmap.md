# 버스 및 사이클 정밀성 향상 로드맵

## 개요

본 문서는 68020 에뮬레이터 코어의 버스 타이밍 및 사이클 정확도를 단계적으로 향상시키기 위한 구체적 개선 과제를 정의합니다.

---

## 1. 버스 타이밍 정밀성 향상

### 1.1 버스 사이클 상태 머신 (Bus State Machine)

**현황**:
- 현재는 단순화된 버스 접근 (read/write immediate)
- 실칩의 S0-S1-S2-... 사이클 상태 모델링 없음

**제안**:
```zig
pub const BusCycleState = enum {
    S0,  // Address valid
    S1,  // Start of data transfer
    S2,  // Data acknowledge
    SW,  // Wait state
    S3,  // End of transfer
};

pub const BusTransaction = struct {
    state: BusCycleState,
    address: u32,
    data: u32,
    width: PortWidth,
    wait_states: u8,
};
```

**혜택**:
- 외부 느린 주변장치(ROM, UART) 타이밍 정확도 향상
- Wait state 주입으로 실제 하드웨어 동작 재현
- 벤치마크 수치가 실칩 타이밍에 근접

**우선순위**: 높음  
**예상 작업량**: 2-3일  
**회귀 테스트**: `src/memory.zig`에 wait state 주입 시나리오 추가

---

### 1.2 버스 에러 복구 메커니즘 강화

**현황**:
- `BusSignal::bus_error` 존재하지만 재시도(retry) 로직 미흡
- `BusSignal::retry`는 단순 플래그 수준

**제안**:
- 버스 에러 발생 시 재시도 카운터 추가
- 최대 재시도 횟수 설정 가능 (기본값: 3회)
- 재시도 실패 시 예외 프레임에 시도 횟수 기록

**API 추가**:
```zig
pub fn setBusRetryLimit(self: *M68k, limit: u8) void;
pub fn getBusRetryCount(self: *M68k) u8; // 디버깅용
```

**우선순위**: 중간  
**예상 작업량**: 1일

---

### 1.3 DMA 채널 시뮬레이션

**현황**:
- CPU 전용 버스 모델, DMA 없음

**제안**:
- 간단한 DMA 컨트롤러 stub 추가 (`src/platform/dma.zig`)
- CPU 사이클 중 버스 중재(arbitration) 시뮬레이션
- DMA 전송 중 CPU halt/resume 타이밍 모델링

**사용 사례**:
- 디스크 I/O, 비디오 메모리 전송 등 시뮬레이션
- Amiga/Atari ST 에뮬레이션에서 필수

**우선순위**: 낮음 (플랫폼 특화)  
**예상 작업량**: 3-4일

---

## 2. 사이클 정확도 개선

### 2.1 EA(Effective Address) 계산 사이클 세분화

**현황**:
- `executor.zig`에서 EA별 사이클이 근사값
- 간접 모드(`(An)+`, `-(An)`, `(d16,An)` 등)의 비용이 평균화됨

**제안**:
- EA 모드별 사이클 테이블 정의
- 68020 User's Manual 기준으로 각 모드 고정

**예시 테이블**:
```zig
const EA_CYCLES = [_]u8{
    0,  // Dn (register direct)
    0,  // An
    4,  // (An)
    4,  // (An)+
    6,  // -(An)
    8,  // (d16,An)
    10, // (d8,An,Xn)
    12, // (bd,An,Xn)
    // ...
};
```

**우선순위**: 높음  
**예상 작업량**: 2일  
**회귀 테스트**: 각 EA 모드별 사이클 assertion 추가

---

### 2.2 I-Cache 히트/미스 정밀화

**현황**:
- 64 entry direct-mapped
- 충돌(collision) 시 무조건 교체

**제안 A**: **2-way set associative**
- 64 entry → 32 set x 2-way
- LRU(Least Recently Used) 교체 정책
- 히트율 10-15% 향상 예상

**제안 B**: **캐시 라인 크기 조정**
- 현재: 4 bytes (longword)
- 제안: 8 bytes (2 longwords)
- Burst fetch 시뮬레이션으로 sequential access 성능 향상

**우선순위**: 중간  
**예상 작업량**: 제안 A (2일), 제안 B (1일)  
**벤치마크**: `src/bench_workloads.zig`에서 측정

---

### 2.3 파이프라인 스톨 모델 고도화

**현황**:
- `PipelineMode::approx` - 단순 페널티 추가
- `PipelineMode::detailed` - 골격만 존재

**제안**:
```zig
pub const PipelineStage = enum {
    Fetch,
    Decode,
    Execute,
    WriteBack,
};

pub const PipelineState = struct {
    stages: [4]?Instruction,
    stall_cycles: u8,
    branch_taken: bool,
};
```

**모델링 항목**:
1. **Data dependency stall**
   - RAW(Read After Write) hazard 검출
   - 의존성 있는 명령 간 1-2 사이클 지연
2. **Branch prediction**
   - 간단한 1-bit predictor
   - Misprediction 시 flush penalty
3. **Memory access contention**
   - Fetch-Execute 동시 메모리 접근 시 충돌

**우선순위**: 낮음 (고급 기능)  
**예상 작업량**: 5-7일

---

## 3. 측정 및 검증 인프라

### 3.1 사이클 프로파일러

**제안**:
- 명령어별 누적 사이클 통계 수집
- 핫스팟(hotspot) 명령 자동 식별

**API**:
```zig
pub const CycleProfiler = struct {
    instruction_counts: [256]u64,
    instruction_cycles: [256]u64,
    
    pub fn enable(self: *M68k) void;
    pub fn getReport(self: *M68k) []const ProfileEntry;
};
```

**출력 예시**:
```
Top 10 cycle consumers:
1. MOVE.L  (32%)  - 1,234,567 cycles / 45,678 instructions
2. ADD.L   (18%)  - 789,012 cycles / 56,789 instructions
...
```

**우선순위**: 중간  
**예상 작업량**: 2일

---

### 3.2 타이밍 회귀 테스트 자동화

**현황**:
- 수동으로 사이클 assertion 추가

**제안**:
- Golden reference 기반 자동 테스트
- 외부 검증 벡터에 기대 사이클 포함
- CI에서 타이밍 변동 자동 탐지

**구조**:
```json
{
  "test_name": "MOVE.L D0,D1",
  "instructions": "0x2200",
  "expected_cycles": 4,
  "tolerance": 0
}
```

**우선순위**: 높음  
**예상 작업량**: 3일

---

### 3.3 실칩 비교 벤치마크

**제안**:
- 실제 68020 보드에서 동일 코드 실행
- 사이클 카운터로 측정한 값과 비교
- 차이 분석 리포트 생성

**필요 하드웨어**:
- 68020 개발 보드 (예: Amiga 1200, Sun-3 등)
- 로직 분석기 또는 사이클 카운터

**우선순위**: 낮음 (리소스 제약)  
**예상 작업량**: 하드웨어 확보 후 1주

---

## 4. 구현 우선순위 요약

| 과제 | 우선순위 | 작업량 | 영향도 |
|------|----------|--------|--------|
| 1.1 버스 사이클 상태 머신 | **높음** | 2-3일 | 타이밍 정확도 대폭 향상 |
| 2.1 EA 계산 사이클 세분화 | **높음** | 2일 | 명령어 사이클 정밀도 향상 |
| 3.2 타이밍 회귀 테스트 자동화 | **높음** | 3일 | 회귀 방지 인프라 |
| 1.2 버스 에러 복구 강화 | 중간 | 1일 | 안정성 향상 |
| 2.2 I-Cache 개선 | 중간 | 2일 | 성능 향상 |
| 3.1 사이클 프로파일러 | 중간 | 2일 | 디버깅 효율성 |
| 2.3 파이프라인 스톨 모델 | 낮음 | 5-7일 | 고급 사용자 대상 |
| 1.3 DMA 시뮬레이션 | 낮음 | 3-4일 | 플랫폼 특화 기능 |
| 3.3 실칩 비교 벤치마크 | 낮음 | 1주+ | 검증 강도 최상 |

---

## 5. 단계별 구현 계획

### Phase 1: 핵심 정밀도 향상 (1-2주)
1. 버스 사이클 상태 머신 (1.1)
2. EA 계산 사이클 세분화 (2.1)
3. 타이밍 회귀 테스트 자동화 (3.2)

**목표**: 기본 명령어의 사이클 정확도 95% 이상

### Phase 2: 성능 및 안정성 (1주)
1. 버스 에러 복구 강화 (1.2)
2. I-Cache 2-way set associative (2.2)
3. 사이클 프로파일러 (3.1)

**목표**: 벤치마크 수치 실칩 대비 ±5% 이내

### Phase 3: 고급 기능 (선택, 2-3주)
1. 파이프라인 스톨 모델 (2.3)
2. DMA 시뮬레이션 (1.3)
3. 실칩 비교 벤치마크 (3.3)

**목표**: 복잡한 시스템 에뮬레이션 지원

---

## 6. 측정 가능한 목표

| 메트릭 | 현재 | Phase 1 목표 | Phase 2 목표 | Phase 3 목표 |
|--------|------|--------------|--------------|--------------|
| 기본 명령 사이클 정확도 | ~80% | 95% | 98% | 99% |
| I-Cache 히트율 (bench) | ~65% | - | 75% | 80% |
| 벤치마크 실칩 오차 | ±15% | ±10% | ±5% | ±3% |
| 타이밍 회귀 테스트 커버리지 | 30개 | 100개 | 200개 | 500개 |

---

## 7. 참고 자료

- **68020 User's Manual** (MC68020UM/AD): 명령어별 사이클 테이블
- **68020 Data Sheet**: 버스 타이밍 다이어그램
- **Musashi 에뮬레이터**: 참고 구현 (사이클 정확도 높음)
- **외부 검증 벡터**: ProcessorTests (JSON 기반)

---

## 8. 관련 문서

- `docs/cycle-model.md`: 현재 사이클 정책
- `docs/translation-cache.md`: TLB 구현
- `docs/cache-pipeline-options.md`: I-cache/파이프라인 옵션
- `docs/benchmark-guide.md`: 벤치마크 절차
