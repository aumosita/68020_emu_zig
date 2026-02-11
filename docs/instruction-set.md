# 명령어 세트 개요

이 문서는 현재 구현된 명령군을 실무 관점에서 요약합니다.

## 기본 명령군

- 데이터 이동: `MOVE`, `MOVEA`, `MOVEQ`, `MOVEM`, `MOVEP`, `LEA`, `PEA`, `EXG`, `SWAP`
- 산술/비교: `ADD*`, `SUB*`, `MUL*`, `DIV*`, `CMP*`, `CHK`, `TST`, `NEG*`, `CLR`, `EXT/EXTB`
- 논리/비트: `AND*`, `OR*`, `EOR*`, `NOT`, `BTST/BSET/BCLR/BCHG`
- 시프트/회전: `AS*`, `LS*`, `RO*`, `ROX*`
- 흐름 제어: `BRA`, `BSR`, `Bcc`, `DBcc`, `Scc`, `JMP`, `JSR`, `RTS`, `RTR`, `RTE`, `RTD`
- 예외/시스템: `TRAP`, `TRAPV`, `ILLEGAL`, `RESET`, `STOP`, `BKPT`, `TRAPcc`

## 68020 확장 중심

- 비트필드: `BFTST`, `BFEXTU`, `BFEXTS`, `BFSET`, `BFCLR`, `BFCHG`, `BFINS`, `BFFFO`
- 원자 연산: `CAS`, `CAS2`
- 모듈/범위/BCD 확장: `CALLM`, `RTM`, `CHK2`, `CMP2`, `PACK`, `UNPK`
- 확장 산술: `MULS.L`, `MULU.L`, `DIVS.L`, `DIVU.L`
- 제어 레지스터: `MOVEC`

## 주의 사항

- 일부 명령의 사이클은 근사 모델일 수 있어 향후 보정 대상입니다.
- FPU 명령은 실행하지 않으며 코프로세서 예외 경로로 처리합니다.

## 사이클 표기 규칙

이 프로젝트 문맥에서 사이클 표기는 아래 기준을 따릅니다.

- `정확`: 현재 테스트로 고정된 동작/분기 조건을 포함해 검증된 값
- `근사`: 구현 단순화를 위해 실칩 내부 타이밍을 추상화한 값

특히 아래 그룹은 `근사` 가능성이 상대적으로 높습니다.

- 확장 명령(`MUL*.L`, `DIV*.L`, `CALLM/RTM`, 비트필드 계열)
- 복합 EA가 포함된 메모리 명령
- 예외 프레임 포맷별 특수 경로
