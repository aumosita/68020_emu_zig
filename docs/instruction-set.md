# 68020 명령어 세트 구현 현황

**구현률**: 97/105 (92.4%) — PMMU 8개 제외 시 100%  
**테스트**: 216개 / 통과율 100%  
**최종 업데이트**: 2026-02-14

## 구현된 명령어 (97개)

| 카테고리 | 명령어 | 개수 |
|----------|--------|------|
| 데이터 이동 | MOVE, MOVEA, MOVEQ, MOVEM, MOVEP, MOVEC, MOVES, MOVE USP, LEA, PEA, LINK, UNLK, EXG, SWAP, EXT/EXTB | 15 |
| 산술 | ADD/A/I/Q/X, SUB/A/I/Q/X, NEG/X, CLR, CMP/A/I/M, CMP2, TST | 22 |
| 곱셈/나눗셈 | MULU/S (16×16), MULU/S.L (32×32), DIVU/S (32÷16), DIVU/S.L (64÷32) | 8 |
| 논리 | AND/I, OR/I, EOR/I, NOT (+CCR/SR variants) | 7 |
| 시프트/로테이트 | ASL/R, LSL/R, ROL/R, ROXL/R | 8 |
| 비트 조작 | BTST, BSET, BCLR, BCHG | 4 |
| 비트 필드 (68020) | BFTST, BFSET, BFCLR, BFCHG, BFEXTS, BFEXTU, BFINS, BFFFO | 8 |
| BCD | ABCD, SBCD, NBCD, PACK, UNPK | 5 |
| 분기/점프 | BRA, Bcc, BSR, DBcc, Scc, JMP, JSR | 7 |
| 복귀 | RTS, RTR, RTE, RTD | 4 |
| 예외 | TRAP, TRAPV, TRAPcc, CHK, CHK2 | 5 |
| 시스템 제어 | RESET, STOP, NOP, ILLEGAL, TAS, BKPT | 6 |
| 멀티프로세서 (68020) | CAS, CAS2 | 2 |
| 모듈 (68020) | CALLM, RTM | 2 |
| 에뮬레이션 | Line-A, Line-F (COPROC) | 2 |

## 미구현 명령어 (8개) — PMMU (68851)

PTEST, PLOAD, PFLUSH, PMOVE, PBcc, PDBcc, PScc, PTRAPcc

- Mac LC는 PMMU 미사용 (24-bit 주소 모드)
- System 6/7 부팅에 불필요
- A/UX 지원 시 구현 예정

## 사이클 표기

- **정확**: 테스트로 검증된 값
- **근사**: 확장 명령어, 복합 EA, 예외 프레임 경로 등

## 코드 위치

- 디코딩: `src/core/decoder.zig`
- 실행: `src/core/executor.zig`
- 테스트: `src/core/cpu_test.zig`
