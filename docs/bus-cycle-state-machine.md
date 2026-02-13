# 버스 사이클 상태 머신 사용 가이드

## 개요

68020 CPU의 버스 타이밍을 정밀하게 모델링하는 상태 머신입니다. S0-S1-S2-SW-S3 사이클을 구현하며, wait state 주입을 통해 느린 주변장치(ROM, UART 등)의 타이밍을 재현합니다.

---

## 버스 사이클 상태

### 68020 버스 사이클 다이어그램

```
S0: Address Setup
 │   - 주소 버스에 주소 출력
 │   - FC (Function Code) 출력
 ↓
S1: Address Valid
 │   - AS* (Address Strobe) assert
 │   - R/W 신호 출력
 ↓
S2: Data Transfer Start
 │   - DS* (Data Strobe) assert
 │   - Write: 데이터 버스에 데이터 출력
 ↓
SW: Wait State (선택적, 반복 가능)
 │   - 느린 장치 응답 대기
 │   - DSACK* 신호 대기
 ↓
S3: Transfer Complete
     - Read: 데이터 버스에서 데이터 읽기
     - AS*, DS* negate
```

### 사이클 계산

- **기본 사이클**: 4 (S0 → S1 → S2 → S3)
- **Wait states 추가**: 각 SW는 +1 cycle
- **총 사이클**: 4 + wait_states

---

## 사용법

### 1. 메모리 설정

```zig
const bus_cycle = @import("bus_cycle.zig");
const Memory = @import("memory.zig").Memory;

// Wait state 영역 정의
const wait_regions = [_]bus_cycle.WaitStateRegion{
    .{ .start = 0x0000, .end_exclusive = 0x4000, .wait_states = 0 }, // Fast RAM
    .{ .start = 0x8000, .end_exclusive = 0xC000, .wait_states = 3 }, // ROM (3 wait states)
    .{ .start = 0xF000, .end_exclusive = 0xF100, .wait_states = 7 }, // UART (7 wait states)
};

var mem = Memory.initWithConfig(allocator, .{
    .size = 64 * 1024,
    .bus_cycle_config = .{
        .default_wait_states = 1, // 기본 1 wait state
        .region_wait_states = &wait_regions,
    },
});
defer mem.deinit();

// 버스 사이클 모델링 활성화
mem.setBusCycleEnabled(true);
```

### 2. 메모리 접근

```zig
// Fast RAM 접근 (0 wait states)
// 사이클: 4 + 0 = 4
try mem.write32(0x1000, 0x12345678);
const val1 = try mem.read32(0x1000);

// ROM 접근 (3 wait states)
// 사이클: 4 + 3 = 7
try mem.write32(0x9000, 0xAABBCCDD);
const val2 = try mem.read32(0x9000);

// UART 접근 (7 wait states)
// 사이클: 4 + 7 = 11
try mem.write8(0xF010, 0x42);
```

### 3. 통계 조회

```zig
// Wait cycles 통계
const stats = mem.getBusCycleStats();
std.debug.print("Total wait cycles: {}\n", .{stats.total_wait_cycles});

// 통계 초기화
mem.resetBusCycleStats();
```

---

## API 참조

### MemoryConfig 필드

```zig
pub const MemoryConfig = struct {
    // ... 기존 필드 ...
    bus_cycle_config: bus_cycle.BusCycleConfig = .{},
};
```

### BusCycleConfig

```zig
pub const BusCycleConfig = struct {
    default_wait_states: u8 = 0,
    region_wait_states: []const WaitStateRegion = &[_]WaitStateRegion{},
};
```

### WaitStateRegion

```zig
pub const WaitStateRegion = struct {
    start: u32,
    end_exclusive: u32,
    wait_states: u8,
};
```

### Memory 메서드

```zig
// 버스 사이클 모델링 활성화/비활성화
pub fn setBusCycleEnabled(self: *Memory, enabled: bool) void;

// 통계 조회
pub fn getBusCycleStats(self: *const Memory) struct { total_wait_cycles: u32 };

// 통계 초기화
pub fn resetBusCycleStats(self: *Memory) void;
```

---

## 실제 사용 예시

### Amiga 500 메모리 맵 시뮬레이션

```zig
const amiga_regions = [_]bus_cycle.WaitStateRegion{
    // Chip RAM (Fast)
    .{ .start = 0x000000, .end_exclusive = 0x080000, .wait_states = 0 },
    
    // Expansion RAM
    .{ .start = 0x200000, .end_exclusive = 0xA00000, .wait_states = 0 },
    
    // Kickstart ROM (Slow)
    .{ .start = 0xF80000, .end_exclusive = 0x1000000, .wait_states = 3 },
    
    // CIA (Very Slow)
    .{ .start = 0xBFE001, .end_exclusive = 0xBFE801, .wait_states = 6 },
};

var mem = Memory.initWithConfig(allocator, .{
    .size = 16 * 1024 * 1024,
    .bus_cycle_config = .{
        .default_wait_states = 2, // Custom chips default
        .region_wait_states = &amiga_regions,
    },
});
mem.setBusCycleEnabled(true);
```

### 성능 프로파일링

```zig
// 테스트 워크로드 실행
mem.resetBusCycleStats();

for (0..1000) |i| {
    const addr: u32 = @intCast(i * 4);
    try mem.write32(addr, @intCast(i));
}

const stats = mem.getBusCycleStats();
std.debug.print("Wait cycles: {}\n", .{stats.total_wait_cycles});
std.debug.print("Wait ratio: {d:.2}%\n", .{
    @as(f64, @floatFromInt(stats.total_wait_cycles)) / 4000.0 * 100.0
});
```

---

## 주의사항

### 성능 영향

버스 사이클 모델링은 시뮬레이션 정확도를 높이지만 성능에 영향을 줄 수 있습니다:

- **비활성화 (기본)**: 오버헤드 없음, 최대 성능
- **활성화**: 영역별 검색 + 상태 관리 오버헤드

**권장 사항**:
- 개발/디버깅: 활성화하여 정확한 타이밍 측정
- 프로덕션: 필요한 경우에만 활성화

### 영역 정의 순서

영역은 선형 검색되므로 **자주 접근되는 영역을 앞쪽에 배치**하면 성능이 향상됩니다:

```zig
const regions = [_]WaitStateRegion{
    // Hot path - RAM (대부분의 접근)
    .{ .start = 0x0000, .end_exclusive = 0x4000, .wait_states = 0 },
    
    // Medium - ROM (가끔 접근)
    .{ .start = 0x8000, .end_exclusive = 0xC000, .wait_states = 3 },
    
    // Cold path - Peripherals (드물게 접근)
    .{ .start = 0xF000, .end_exclusive = 0xF100, .wait_states = 7 },
};
```

---

## 테스트

```bash
# 버스 사이클 모듈 테스트
zig test src/bus_cycle.zig

# 통합 테스트
zig test src/test_bus_cycle.zig

# 전체 빌드 테스트
zig build test
```

---

## 향후 확장

### Phase 2 계획

1. **동적 wait state 콜백**
   ```zig
   pub const WaitStateCallback = *const fn(addr: u32) u8;
   ```

2. **버스 중재 (Bus Arbitration)**
   - DMA와 CPU 간 버스 경합 모델링
   - 우선순위 기반 접근 제어

3. **Burst 모드**
   - 연속 접근 최적화
   - Cache line fill 시뮬레이션

---

## 참조

- **68020 User's Manual**: Section 7 (Bus Operation)
- **EA 사이클 모듈**: `src/ea_cycles.zig`
- **메모리 추상화**: `src/memory.zig`
- **Phase 1 로드맵**: `docs/bus-cycle-precision-roadmap.md`

---

## 문제 해결

### Q: 통계가 0으로 나옴

**A**: `setBusCycleEnabled(true)` 호출 확인

### Q: 예상보다 wait cycles가 많음

**A**: 영역 중복 확인 - 좁은 범위를 넓은 범위보다 먼저 배치

### Q: 성능이 너무 느림

**A**: 
1. 영역 개수 최소화 (10개 이하 권장)
2. 기본 wait_states로 대부분 커버
3. 프로덕션에서는 비활성화 고려
