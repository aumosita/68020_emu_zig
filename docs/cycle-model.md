# 사이클 모델 정책

## 목적

- 기능 정확도 중심 코어에서 현재 사이클 값의 신뢰 범위를 명확히 문서화
- "고정/검증됨"과 "근사"를 분리해 회귀 테스트 기준을 고정

## 현재 정책 요약

- `고정/검증됨`: 코드 경로와 테스트에서 기대 사이클이 고정된 항목
- `근사`: 실칩 미세 타이밍(버스 폭, 파이프라인, 캐시 세부 상태)을 단순화한 항목

## 고정 사이클 경로(핵심)

`src/cpu.zig`의 `step()`에서 고정되는 공통 경로:

- IRQ 진입: `44`
- STOP 상태 대기 tick: `4`
- fault(frame A) subtype:
  - instruction fetch fault: `50`
  - decode extension fetch fault: `52`
  - execute data access fault: `54`
- illegal/decode fault: `34`
- I-cache miss fetch penalty: `+2` (fetch 단계)
- (옵션) Dynamic Bus Sizing split penalty: `+N`
  - `N`은 포트 폭 분할로 발생한 추가 bus sub-access 수
  - 기본값은 비활성, `setSplitBusCyclePenaltyEnabled(true)`에서만 합산
- (옵션) PipelineMode penalty/overlap:
  - `approx`: taken branch flush `+2`, memory-dst write overlap `-1`
  - `detailed`: taken branch flush `+4`, memory-dst write overlap `-2`(골격 단계)
  - `off`는 기존 고정 사이클 경로 유지

`src/executor.zig`의 대표 고정 반환:

- `NOP`: `4`
- `RTE`: `20`
- `TRAP`: `34`
- `TRAPV`(trap): `34`, (no trap): `4`
- `RESET`(supervisor): `132`
- `BKPT` fallback: `10`
- `TRAPcc` trap: `33`, no trap: `3`

## 검증된 회귀 테스트(예시)

- IRQ/STOP 경로: `src/cpu.zig` `test "M68k STOP halts until interrupt and resumes on IRQ"`
- fetch fault frame A: `src/cpu.zig` `test "M68k bus error during instruction fetch creates format A frame"`
- root C API IRQ/STOP 경로: `src/root.zig` `test "root API STOP resumes on IRQ with expected cycle PC and SR"`

## 근사 영역

아래 영역은 현재 기능 정확도 우선으로 단순화되어 있습니다.

- 복합 확장 명령(`bitfield`, `CALLM/RTM`, 일부 coprocessor 경로)
- 복잡 EA별 실칩 버스 타이밍
- MOVEM 상세 비용(레지스터 수/방향별 세분화)
- 실칩 수준 파이프라인/캐시 라인 상태 기반 변동

## 표기 규칙

- 문서/커밋/릴리스 노트에서 사이클 관련 변경 시 반드시 아래로 표기:
  - `고정/검증됨`: 테스트 기대값과 함께 변경
  - `근사`: 정책 변경(의도)만 명시, 실칩 일치 주장 금지

## 하드웨어 인터럽트 및 타이밍

이벤트 스케줄러(`src/core/scheduler.zig`) 도입으로 하드웨어 타이밍 정확도가 개선되었습니다.

- **이벤트 기반 스케줄링**: `step()`마다 카운터를 감소시키는 방식 대신, 목표 사이클(deadline)을 등록하고 시간 도래 시 콜백을 실행합니다.
- **RBV VBL**: 60.00Hz (266,667 cycles @ 16MHz) 주기로 정확하게 인터럽트를 발생시킵니다.
- **VIA 타이머**: 타이머 만료 시점을 스케줄러에 등록하여 지연 없는 인터럽트 요청을 보장합니다.

이로써 CPU의 명령어 실행 사이클뿐만 아니라, 외부 장치의 인터럽트 발생 시점도 사이클 단위로 예측 가능해졌습니다.
