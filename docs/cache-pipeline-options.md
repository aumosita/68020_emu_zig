# 캐시/파이프라인 옵션(비기본)

## 목적

- 기능 정확도와 분리된 성능 모델 실험 지점을 명시적으로 제공한다.
- 기본 동작은 유지하고, 옵션 활성 시에만 모델링 강도를 조정한다.

## I-cache 옵션

- 통계 노출:
  - `getICacheStats()` -> `{ hits, misses }`
  - `clearICacheStats()`
  - C API:
    - `m68k_get_icache_hit_count`
    - `m68k_get_icache_miss_count`
    - `m68k_clear_icache_stats`

- miss penalty 조정:
  - `setICacheFetchMissPenalty(cycles)`
  - 기본값: `2`
  - C API:
    - `m68k_set_icache_fetch_miss_penalty`
    - `m68k_get_icache_fetch_miss_penalty`

## 파이프라인 모드 플래그

- `PipelineMode`:
  - `off`
  - `approx`
  - `detailed`
- 현재는 플래그 상태 저장/조회만 제공한다.
  - `setPipelineMode(mode)`
  - `getPipelineMode()`
  - `approx`:
    - taken branch에 flush penalty `+2`
    - memory destination write에 EA/bus overlap 보정 `-1`
  - `detailed`:
    - taken branch flush `+4`
    - memory destination write overlap 보정 `-2`(초기 골격)
  - C API:
    - `m68k_set_pipeline_mode`
    - `m68k_get_pipeline_mode`

## 호환성 정책

- 기본값은 기존 동작과 동일(`off`, miss penalty `2`).
- 옵션 비활성 시 기존 회귀 테스트의 기대 cycle 값을 유지한다.
