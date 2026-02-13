# 2-way Set Associative 인스트럭션 캐시

## 개요
기존의 단순 Direct-mapped 캐시를 개선하여, 실제 68020 칩의 사양인 256바이트 규모의 **2-way set associative** 캐시를 구현했습니다. 이를 통해 동일한 세트에 매핑되는 다른 주소들 간의 충돌(Conflict Miss)을 줄이고 성능을 향상시켰습니다.

## 구조 (Cache Layout)
- **전체 크기**: 256 Bytes
- **라인 구성**: 64 Entries (각 4 Bytes / Longword)
- **매핑 방식**: 32 Sets × 2 Ways
- **교체 정책**: LRU (Least Recently Used)

### 주소 해석 (Address Decoding)
32비트 주소는 다음과 같이 해석됩니다:
- `Tag`: 상위 25 비트
- `Set Index`: 중간 5 비트 (2^5 = 32 sets)
- `Word Select`: 하위 1 비트 (Longword 내의 Word 선택)
- `Byte Offset`: 최하위 1 비트 (정렬된 접근 시 무시)

## LRU 교체 알고리즘
- 각 세트 내의 두 방식(Way)은 `lru` 플래그를 가집니다.
- 특정 방식이 히트되거나 새로 로드되면 해당 방식의 `lru`를 `true`로, 다른 방식의 `lru`를 `false`로 설정합니다.
- 새로운 데이터를 로드해야 할 때, `lru`가 `false`인 방식을 교체 대상으로 선정합니다.

## 제어 및 통계
- `CACR` 레지스터의 비트 0(Enable) 및 비트 3(Clear)을 통해 제어됩니다.
- `getICacheStats()`를 통해 히트(Hit) 및 미스(Miss) 횟수를 실시간으로 모니터링할 수 있습니다.

## 관련 파일
- `src/cpu.zig`: 캐시 데이터 구조 및 Fetch 로직
- `src/test_icache_assoc.zig`: 2-way 동작 검증 테스트
