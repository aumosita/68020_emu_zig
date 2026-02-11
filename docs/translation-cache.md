# 소프트웨어 TLB(주소 변환 캐시)

## 개요

- `memory.resolveBusAddress` 경로에 소형 TLB를 추가해 `address_translator` 콜백 호출 오버헤드를 줄인다.
- 현재 구현은 `8-entry direct-mapped` 구조를 사용한다.

## 키/값 구성

- key:
  - logical page (`addr >> 12`)
  - `function_code`
  - `space` (Program/Data)
  - `is_write`
- value:
  - `physical_page_base`

페이지 오프셋은 접근 시점에 재조합한다.

## 무효화 정책

- `Memory.setAddressTranslator(...)` 호출 시 자동 flush
- 수동 flush API:
  - Zig: `Memory.invalidateTranslationCache()`
  - C API: `m68k_invalidate_translation_cache(...)`

## 회귀 검증 포인트

- 동일 페이지 재접근 시 translator 콜백 호출 감소
- 수동 flush 후 translator 콜백 경로 재진입
- translator 교체 시 캐시 자동 무효화

관련 테스트:
- `src/memory.zig` translation-cache 테스트 3종
- `src/root.zig` `root API can invalidate translation cache`
