# 벤치마크/품질 측정 가이드

## 목적

- 기능 회귀를 우선으로 유지하면서, 성능 변화를 재현 가능한 절차로 추적한다.
- CPI/MIPS는 참고 지표로 사용하고, 기능 정확도 테스트를 우선 게이트로 둔다.

## 워크로드

`src/bench_workloads.zig`는 아래 3개 워크로드를 실행한다.

- `sequential_nop`
  - 연속 NOP 스트림 실행
  - fetch/decode + 기본 실행 경로의 기준선

- `tight_branch_loop`
  - `BRA.S -2` 무한 루프
  - 분기 중심 경로의 기준선

- `platform_irq_loop`
  - 플랫폼 레이어(timer + PIC)로 주기 IRQ 주입
  - IRQ 진입/복귀를 포함한 통합 경로

## 실행 방법

```bash
zig run src/bench_workloads.zig
```

출력 필드:

- `steps`
- `cycles`
- `elapsed_ns`
- `mips`
- `cpi`

## 기준 결과(2026-02-11, 동일 머신 1회)

```text
68020 bench workloads (steps=200000)
sequential_nop: steps=200000 cycles=1337856 elapsed_ns=46362709 mips=4.314 cpi=6.689
tight_branch_loop: steps=200000 cycles=2000000 elapsed_ns=23604666 mips=8.473 cpi=10.000
platform_irq_loop: steps=200000 cycles=4533308 elapsed_ns=40952500 mips=4.884 cpi=22.667
```

## 운영 원칙

- PR/변경 검토 시:
  - 먼저 `zig build test` 통과 여부를 확인
  - 벤치 수치는 회귀 탐지 참고 자료로만 사용
- 10% 이상 성능 변화가 나타나면:
  - 원인 커밋/옵션/워크로드 편향을 함께 기록
