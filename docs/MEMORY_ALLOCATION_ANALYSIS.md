# Memory Allocation Optimization

## Summary

Arena allocator를 도입하여 CPU 인스턴스 생성/파괴 시 메모리 할당 성능을 개선합니다.

## Current State

현재 `M68k` 구조체는 `GeneralPurposeAllocator`를 사용하여:
- Memory 버퍼 할당 (최대 16MB)
- Profiler 데이터 할당

매번 할당/해제 시 오버헤드가 발생합니다.

## Proposed Changes

### 1. Arena Allocator 옵션 추가

```zig
pub const M68kConfig = struct {
    memory: memory.MemoryConfig = .{},
    use_arena: bool = false,  // Arena allocator 사용 여부
};
```

### 2. 두 가지 생성 방식 지원

**방식 A: 기존 방식 (호환성)**
```zig
var m68k = M68k.init(gpa.allocator());
defer m68k.deinit();
```

**방식 B: Arena 방식 (최적화)**
```zig
var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
defer arena.deinit();
var m68k = M68k.initWithArena(arena.allocator());
// deinit 불필요 - arena.deinit()이 모두 정리
```

## Benefits

1. **성능 향상**: 
   - 할당: 단일 큰 블록 할당 → 개별 할당 제거
   - 해제: 전체 arena 한 번에 해제 → 개별 free 호출 제거
   
2. **메모리 지역성**: 
   - 관련 데이터가 메모리상 가까이 위치 → 캐시 효율성 향상

3. **코드 간소화**: 
   - arena.deinit() 한 번으로 모든 리소스 정리

## Benchmark Target

- CPU 생성/파괴: **30-50% 성능 향상**
- 메모리 단편화: **감소**

## Implementation Plan

1. `M68kConfig` 구조체 추가
2. `initWithArena()` 메서드 추가
3. 벤치마크 테스트 작성
4. 문서 업데이트

## Testing

```zig
test "M68k with arena allocator" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    
    var m68k = M68k.initWithArena(arena.allocator());
    // No explicit deinit needed
    
    try std.testing.expectEqual(@as(u32, 0), m68k.pc);
}
```

## Status

⏸️ **Deferred** - 현재 메모리 할당 패턴 분석 결과, 대부분의 할당이 초기화 시 한 번만 발생합니다.
실제 병목은 할당보다 명령어 실행에 있으므로, executor 모듈 분리가 더 우선순위가 높습니다.

향후 다음 경우에 재검토:
- 멀티 인스턴스 생성/파괴가 빈번한 경우
- 프로파일링으로 할당 오버헤드 확인 시
- JIT 컴파일러 도입 시 (메모리 관리 복잡도 증가)
