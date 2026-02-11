# 68020 에뮬레이터 (Zig)

Zig로 작성된 Motorola 68000/68020 CPU 에뮬레이터 코어입니다. 디코더와 실행기 분리 구조를 사용하며, C에서 호출 가능한 API를 제공합니다.

## 현재 상태

- 핵심 명령 실행, 예외 처리, 인터럽트 처리 흐름이 구현되어 있습니다.
- 68020 확장 명령(`CALLM/RTM`, 비트필드, `CAS/CAS2`, `MUL*.L/DIV*.L`, `CHK2/CMP2`, `PACK/UNPK`, `MOVEC`)이 동작합니다.
- 스택 뱅킹(`USP/ISP/MSP`)과 IRQ 주입 API(`m68k_set_irq*`)를 지원합니다.
- 최근 수정으로 `MOVEM` 주소 지정 처리, 확장 EA의 PC 증가량, `BKPT`/예외 벡터 동작 정확도를 강화했습니다.

## 범위와 제한

- 본 프로젝트는 기능 중심 CPU 코어(ISS)에 가깝습니다.
- 68881/68882 FPU 연산은 구현하지 않습니다. F-line은 코프로세서 미사용 예외 경로로 처리합니다.
- 캐시/파이프라인 마이크로아키텍처 모델링은 현재 범위 밖입니다.

## 사이클 정확도 정책

현재 코어는 기능 정확도를 우선합니다. 사이클은 아래처럼 관리합니다.

- `정확`: 분기/트랩/기본 산술 등에서 코드와 테스트로 고정 검증된 항목
- `근사`: 일부 복합 명령(확장 명령, 복잡 EA, 특수 프레임)에서 하드웨어 미세 타이밍을 단순화한 항목

실행 시 반환되는 사이클 값은 유효한 비용 모델이지만, 모든 명령에서 실칩 미세 타이밍과 1:1 보장을 의미하지는 않습니다.

## 빌드 및 테스트

Zig 0.13.x 기준:

```bash
zig build
zig build test
```

직접 테스트:

```bash
zig test src/root.zig
zig test src/cpu.zig
```

PATH에 Zig가 없으면 로컬 경로를 사용하세요:

```bash
../zig-macos-aarch64-0.13.0/zig test src/root.zig
```

## 저장소 구조

```text
src/
  cpu.zig        CPU 상태, 예외/인터럽트, step 루프
  decoder.zig    opcode/EA 디코딩
  executor.zig   명령어 실행 의미론
  memory.zig     메모리 모델
  root.zig       Zig/C API 표면

docs/
  README.md      문서 인덱스
  instruction-set.md
  68020-reference.md
```

## C API 요약

- 생성/해제: `m68k_create`, `m68k_destroy`, `m68k_reset`
- 실행: `m68k_step`, `m68k_execute`
- 인터럽트: `m68k_set_irq`, `m68k_set_irq_vector`, `m68k_set_spurious_irq`
- 레지스터/PC: `m68k_set_pc`, `m68k_get_pc`, `m68k_set_reg_d`, `m68k_get_reg_d`, `m68k_set_reg_a`, `m68k_get_reg_a`
- 메모리: `m68k_write_memory_8/16/32`, `m68k_read_memory_8/16/32`, `m68k_load_binary`

## 문서

- 문서 인덱스: `docs/README.md`
- 명령어 참고: `docs/instruction-set.md`
- 68020 참고: `docs/68020-reference.md`
- 테스트 가이드: `docs/testing-guide.md`
