# 플랫폼 주변장치/PIC 레이어

## 목적

- CPU 코어 외부에서 IRQ 중재를 담당하는 최소 플랫폼 계층을 제공한다.
- 코어-플랫폼 경계를 명확히 해, 타이머/UART/PIC 확장을 독립적으로 진행할 수 있게 한다.

## 모듈 구성

- `src/platform/pic.zig`
  - 레벨별 pending IRQ를 보관하고 최고 우선순위를 CPU로 전달
  - autovector / explicit vector 모두 지원

- `src/platform/timer.zig`
  - 주기 기반 tick 누적 후 IRQ 요청 생성
  - `tick(elapsed_cycles, pic)` 형태로 CPU step 결과와 연동

- `src/platform/uart_stub.zig`
  - RX pending/ TX log만 가진 최소 스텁
  - RX 입력 시 PIC로 IRQ 요청

- `src/platform/mod.zig`
  - `Platform{ pic, timer, uart }` 조합
  - `onCpuStep(cpu, cycles_used)`에서 timer 갱신 + PIC 전달

## 코어/플랫폼 계약

- 플랫폼 -> 코어:
  - `cpu.setInterruptLevel(level)` 또는 `cpu.setInterruptVector(level, vector)`
- 코어 -> 플랫폼:
  - `step()` 반환 cycles를 플랫폼이 받아 timer 누적에 사용

IRQ acknowledge는 현재 코어 내부 pending 모델을 이용해 암묵적으로 처리하며,
PIC는 `deliver()` 시점에 자체 pending을 clear한다.

## 샘플 루프 데모

- 실행:

```bash
zig run src/demo_platform_loop.zig
```

- 동작:
  - 메인 루프(`BRA.S -2`) 실행 중 timer가 주기 IRQ(L2)를 발생
  - 핸들러(`ADDQ.L #1,D7; RTE`)가 반복 진입/복귀
  - 실행 결과로 IRQ 왕복 횟수(`D7`)와 복귀 PC를 출력

## 회귀 테스트

- `src/platform/mod.zig`
  - `test "platform timer drives periodic IRQ and CPU handler roundtrip"`
