# 개발 가이드

## 테스트

```bash
zig build test                    # 전체 테스트
zig build test --summary all     # 상세 요약
zig test src/core/cpu_test.zig    # 모듈별 테스트
```

## 벤치마크

```bash
zig build benchmark
./zig-out/bin/benchmark --iterations 1000000
```

기능 회귀 우선, 성능 변화는 재현 가능한 절차로 추적.

## 플랫폼 레이어 (`src/platform/`)

CPU 코어 외부에서 IRQ 중재를 담당하는 최소 플랫폼 계층:

| 모듈 | 역할 |
|------|------|
| `pic.zig` | IRQ 우선순위 인코딩, 마스킹 |
| `timer.zig` | 주기적 틱 생성 |
| `uart_stub.zig` | 시리얼 I/O 플레이스홀더 |

## 외부 검증 벡터

`external_vectors.zig` — JSON 형식 68k validation vector를 로드하여 회귀 테스트에 반영.

```bash
zig build test-vectors -- --vector-file=path/to/vectors.json
```

## Python 연동

```python
import ctypes
lib = ctypes.CDLL("./libm68020-emu.so")
m68k = lib.m68k_create()
lib.m68k_step(m68k)
lib.m68k_destroy(m68k)
```

## PMMU 호환 레이어 (`pmmu-ready`)

실제 페이지 워크 없이 PMMU 존재를 전제로 한 소프트웨어가 초기 probe에서 즉시 실패하지 않도록 최소 동작 제공. PMOVE/PFLUSH 등은 NOP으로 처리.
