# 68020 에뮬레이터 (Zig)

Zig로 작성된 Motorola 68000/68020 CPU 에뮬레이터 코어입니다. 디코더와 실행기 분리 구조를 사용하며, C에서 호출 가능한 API를 제공합니다.

## 현재 상태

- 핵심 명령 실행, 예외 처리, 인터럽트 처리 흐름이 구현되어 있습니다.
- 68020 확장 명령(`CALLM/RTM`, 비트필드, `CAS/CAS2`, `MUL*.L/DIV*.L`, `CHK2/CMP2`, `PACK/UNPK`, `MOVEC`)이 동작합니다.
- 스택 뱅킹(`USP/ISP/MSP`)과 IRQ 주입 API(`m68k_set_irq*`)를 지원합니다.
- 최근 수정으로 `MOVEM` 주소 지정 처리, 확장 EA의 PC 증가량, `BKPT`/예외 벡터 동작 정확도를 강화했습니다.
- 기능 정확도 범위에서 경량 I-cache 모델(히트/미스 비용, CACR 기반 무효화)을 반영했습니다.
- I-cache 통계(hit/miss) 조회와 fetch miss penalty 조정 옵션을 제공합니다.
- 파이프라인 모드 플래그(`off/approx/detailed`)를 추가해 비기본 모델 확장 지점을 고정했습니다.
- 버스 추상화 계층(`bus hook`, 주소 변환기)을 추가해 PMMU/외부 버스 컨트롤러 연동 지점을 제공했습니다.
- PIC/timer/UART stub 기반의 플랫폼 레이어와 주기 IRQ 데모 루프를 제공합니다.
- 명령어 fetch 단계 버스 에러 시 Format A 프레임(vector 2) 생성 경로를 반영했습니다.

## 범위와 제한

- 본 프로젝트는 기능 중심 CPU 코어(ISS)에 가깝습니다.
- 68881/68882 FPU 연산은 구현하지 않습니다. F-line은 기본적으로 코프로세서 미사용 예외 경로이며, PMMU-ready 최소 호환 모드에서 coprocessor-id 0만 제한적으로 흡수합니다.
- 파이프라인 및 실칩 수준 캐시 미세동작(라인 상태/버스트/정확 CPI)은 현재 범위 밖입니다.

## 사이클 정확도 정책

현재 코어는 기능 정확도를 우선합니다. 사이클은 아래처럼 관리합니다.

- `정확(고정/검증됨)`: 코드와 테스트에서 기대 사이클이 고정된 항목
- `근사`: 일부 복합 명령(확장 명령, 복잡 EA, 특수 프레임)에서 하드웨어 미세 타이밍을 단순화한 항목

실행 시 반환되는 사이클 값은 유효한 비용 모델이지만, 모든 명령에서 실칩 미세 타이밍과 1:1 보장을 의미하지는 않습니다.

세부 정책/고정 경로 목록은 `docs/cycle-model.md`를 참고하세요.
성능 측정 절차/기준 워크로드는 `docs/benchmark-guide.md`를 참고하세요.
외부 검증 벡터(JSON) 러너/CI 연동은 `docs/external-vector-runner.md`를 참고하세요.

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
- 컨텍스트 기반 생성/해제: `m68k_context_create`, `m68k_context_destroy`, `m68k_create_in_context`, `m68k_destroy_in_context`
- 외부 allocator callback: `m68k_context_set_allocator_callbacks`
- 실행: `m68k_step`, `m68k_execute`
- 인터럽트: `m68k_set_irq`, `m68k_set_irq_vector`, `m68k_set_spurious_irq`
- 레지스터/PC: `m68k_set_pc`, `m68k_get_pc`, `m68k_set_reg_d`, `m68k_get_reg_d`, `m68k_set_reg_a`, `m68k_get_reg_a`
- 메모리: `m68k_write_memory_8/16/32`, `m68k_read_memory_8/16/32`, `m68k_load_binary`
- 메모리(v2, 권장): `m68k_write_memory_8/16/32_status`, `m68k_read_memory_8/16/32_status`

### C API 마이그레이션 노트

- 구 메모리 API(`m68k_read_memory_*`, `m68k_write_memory_*`)는 호환성 유지를 위해 남아 있지만, 오류를 값으로 숨길 수 있으므로 신규 통합에서는 `*_status` API 사용을 권장합니다.
- 멀티 인스턴스/스레드 환경에서는 전역 생성 API 대신 context API(`m68k_context_*`, `m68k_create_in_context`) 사용을 권장합니다.

## 문서

- 문서 인덱스: `docs/README.md`
- 명령어 참고: `docs/instruction-set.md`
- 68020 참고: `docs/68020-reference.md`
- 테스트 가이드: `docs/testing-guide.md`
- 사이클 모델: `docs/cycle-model.md`
