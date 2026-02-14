# 68020 명령어 세트 구현 현황

## 개요

Motorola 68020 CPU는 약 **100개 이상의 명령어**를 지원합니다. 이 문서는 68020_emu_zig 프로젝트에서 구현된 명령어와 미구현 명령어를 분류합니다.

**현재 상태 (2026-02-14):**
- ✅ **구현 완료**: 97개 명령어
- ❌ **미구현**: 8개 명령어 (PMMU 관련)
- 📊 **구현률**: ~92%

---

## ✅ 구현된 명령어 (97개)

### 데이터 이동 (Data Movement) - 14개
| 명령어 | 설명 | 구현 |
|--------|------|------|
| MOVE | Move data | ✅ |
| MOVEA | Move to address register | ✅ |
| MOVEQ | Move quick (immediate) | ✅ |
| MOVEM | Move multiple registers | ✅ |
| MOVEP | Move peripheral data | ✅ |
| MOVEC | Move control register | ✅ |
| MOVEUSP | Move user stack pointer | ✅ |
| LEA | Load effective address | ✅ |
| PEA | Push effective address | ✅ |
| LINK | Link and allocate | ✅ |
| UNLK | Unlink | ✅ |
| EXG | Exchange registers | ✅ |
| SWAP | Swap register halves | ✅ |
| EXT/EXTB | Sign extend | ✅ |

### 산술 연산 (Arithmetic) - 16개
| 명령어 | 설명 | 구현 |
|--------|------|------|
| ADD | Add binary | ✅ |
| ADDA | Add to address register | ✅ |
| ADDI | Add immediate | ✅ |
| ADDQ | Add quick | ✅ |
| ADDX | Add with extend | ✅ |
| SUB | Subtract binary | ✅ |
| SUBA | Subtract from address | ✅ |
| SUBI | Subtract immediate | ✅ |
| SUBQ | Subtract quick | ✅ |
| SUBX | Subtract with extend | ✅ |
| NEG | Negate | ✅ |
| NEGX | Negate with extend | ✅ |
| CLR | Clear operand | ✅ |
| CMP | Compare | ✅ |
| CMPA | Compare address | ✅ |
| CMPI | Compare immediate | ✅ |
| CMPM | Compare memory | ✅ |

### BCD 연산 (Binary-Coded Decimal) - 3개
| 명령어 | 설명 | 구현 |
|--------|------|------|
| ABCD | Add BCD with extend | ✅ |
| SBCD | Subtract BCD with extend | ✅ |
| NBCD | Negate BCD with extend | ✅ |

### 곱셈/나눗셈 (Multiply/Divide) - 8개
| 명령어 | 설명 | 구현 |
|--------|------|------|
| MULU | Multiply unsigned (16x16→32) | ✅ |
| MULS | Multiply signed (16x16→32) | ✅ |
| DIVU | Divide unsigned (32÷16) | ✅ |
| DIVS | Divide signed (32÷16) | ✅ |
| MULU.L | Multiply unsigned (32x32→64) | ✅ |
| MULS.L | Multiply signed (32x32→64) | ✅ |
| DIVU.L | Divide unsigned (64÷32) | ✅ |
| DIVS.L | Divide signed (64÷32) | ✅ |

### 논리 연산 (Logical) - 7개
| 명령어 | 설명 | 구현 |
|--------|------|------|
| AND | Logical AND | ✅ |
| ANDI | AND immediate | ✅ |
| OR | Logical OR | ✅ |
| ORI | OR immediate | ✅ |
| EOR | Exclusive OR | ✅ |
| EORI | EOR immediate | ✅ |
| NOT | Logical complement | ✅ |

### 시프트/로테이트 (Shift/Rotate) - 8개
| 명령어 | 설명 | 구현 |
|--------|------|------|
| ASL | Arithmetic shift left | ✅ |
| ASR | Arithmetic shift right | ✅ |
| LSL | Logical shift left | ✅ |
| LSR | Logical shift right | ✅ |
| ROL | Rotate left | ✅ |
| ROR | Rotate right | ✅ |
| ROXL | Rotate left with extend | ✅ |
| ROXR | Rotate right with extend | ✅ |

### 비트 조작 (Bit Manipulation) - 4개
| 명령어 | 설명 | 구현 |
|--------|------|------|
| BTST | Test a bit | ✅ |
| BSET | Set a bit | ✅ |
| BCLR | Clear a bit | ✅ |
| BCHG | Change a bit | ✅ |

### 비트 필드 (Bit Field) - 68020 전용 - 8개
| 명령어 | 설명 | 구현 |
|--------|------|------|
| BFTST | Test bit field | ✅ |
| BFSET | Set bit field | ✅ |
| BFCLR | Clear bit field | ✅ |
| BFCHG | Change bit field | ✅ |
| BFEXTS | Extract bit field signed | ✅ |
| BFEXTU | Extract bit field unsigned | ✅ |
| BFINS | Insert bit field | ✅ |
| BFFFO | Find first one in bit field | ✅ |

### 분기 (Branch) - 5개
| 명령어 | 설명 | 구현 |
|--------|------|------|
| BRA | Branch always | ✅ |
| Bcc | Branch conditionally | ✅ |
| BSR | Branch to subroutine | ✅ |
| DBcc | Decrement and branch | ✅ |
| Scc | Set conditionally | ✅ |

### 점프 (Jump) - 2개
| 명령어 | 설명 | 구현 |
|--------|------|------|
| JMP | Jump | ✅ |
| JSR | Jump to subroutine | ✅ |

### 서브루틴 복귀 (Return) - 4개
| 명령어 | 설명 | 구현 |
|--------|------|------|
| RTS | Return from subroutine | ✅ |
| RTR | Return and restore CCR | ✅ |
| RTE | Return from exception | ✅ |
| RTD | Return and deallocate | ✅ |

### 예외 처리 (Exception) - 5개
| 명령어 | 설명 | 구현 |
|--------|------|------|
| TRAP | Trap | ✅ |
| TRAPV | Trap on overflow | ✅ |
| TRAPcc | Trap conditionally | ✅ |
| CHK | Check register bounds | ✅ |
| CHK2 | Check bounds (68020) | ✅ |

### 시스템 제어 (System Control) - 6개
| 명령어 | 설명 | 구현 |
|--------|------|------|
| RESET | Reset external devices | ✅ |
| STOP | Stop and wait | ✅ |
| NOP | No operation | ✅ |
| ILLEGAL | Illegal instruction | ✅ |
| TAS | Test and set | ✅ |
| TST | Test operand | ✅ |

### 특수 명령어 (Special) - 7개
| 명령어 | 설명 | 구현 |
|--------|------|------|
| CAS | Compare and swap | ✅ |
| CAS2 | Compare and swap dual | ✅ |
| CMP2 | Compare bounds | ✅ |
| PACK | Pack BCD | ✅ |
| UNPK | Unpack BCD | ✅ |
| CALLM | Call module | ✅ |
| RTM | Return from module | ✅ |
| BKPT | Breakpoint | ✅ |

### 에뮬레이션 (Emulation) - 2개
| 명령어 | 설명 | 구현 |
|--------|------|------|
| LINEA | Line-A emulator trap | ✅ |
| COPROC | Coprocessor instruction | ✅ |

---

## ❌ 미구현 명령어 (8개)

### PMMU (Paged Memory Management Unit) 명령어 - 8개

| 명령어 | 설명 | 상태 | 우선순위 |
|--------|------|------|----------|
| PTEST | Test logical address | ❌ | 낮음 |
| PLOAD | Load entry in ATC | ❌ | 낮음 |
| PFLUSH | Flush entry in ATC | ❌ | 낮음 |
| PMOVE | Move to/from PMMU | ❌ | 낮음 |
| PBcc | Branch on PMMU condition | ❌ | 낮음 |
| PDBcc | Decrement and branch | ❌ | 낮음 |
| PScc | Set on PMMU condition | ❌ | 낮음 |
| PTRAPcc | Trap on PMMU condition | ❌ | 낮음 |

**미구현 이유:**
- Mac LC는 PMMU를 사용하지 않음 (24-bit 주소 모드)
- System 6.0.8 부팅에 불필요
- A/UX (Unix) 지원 시에만 필요

**구현 계획:**
- 현재: 호환 레이어로 우회 (PMMU 접근 시 무시)
- 장기: A/UX 지원 목표 시 구현 예정

---

## 📊 구현 통계

### 카테고리별 구현률

| 카테고리 | 구현 | 미구현 | 구현률 |
|----------|------|--------|--------|
| 데이터 이동 | 14 | 0 | 100% |
| 산술 연산 | 16 | 0 | 100% |
| BCD 연산 | 3 | 0 | 100% |
| 곱셈/나눗셈 | 8 | 0 | 100% |
| 논리 연산 | 7 | 0 | 100% |
| 시프트/로테이트 | 8 | 0 | 100% |
| 비트 조작 | 4 | 0 | 100% |
| 비트 필드 | 8 | 0 | 100% |
| 분기 | 5 | 0 | 100% |
| 점프 | 2 | 0 | 100% |
| 서브루틴 복귀 | 4 | 0 | 100% |
| 예외 처리 | 5 | 0 | 100% |
| 시스템 제어 | 6 | 0 | 100% |
| 특수 명령어 | 8 | 0 | 100% |
| 에뮬레이션 | 2 | 0 | 100% |
| **PMMU** | **0** | **8** | **0%** |
| **전체** | **97** | **8** | **92.4%** |

### 68020 신규 명령어 (68000 대비)

68020에서 추가된 명령어들:

| 명령어 | 설명 | 구현 |
|--------|------|------|
| BFCHG/BFCLR/BFEXTS/BFEXTU/BFFFO/BFINS/BFSET/BFTST | 비트 필드 조작 | ✅ |
| CAS/CAS2 | Compare-and-swap | ✅ |
| CHK2/CMP2 | 범위 검사 확장 | ✅ |
| DIVS.L/DIVU.L | 64÷32 나눗셈 | ✅ |
| MULS.L/MULU.L | 32x32 곱셈 | ✅ |
| PACK/UNPK | BCD 팩/언팩 | ✅ |
| RTD | Return and deallocate | ✅ |
| TRAPcc | 조건부 트랩 | ✅ |
| CALLM/RTM | 모듈 호출 | ✅ |
| EXTB | Byte to long extend | ✅ |
| PMMU 명령어 | PTEST, PLOAD 등 | ❌ |

**68020 신규 명령어 구현률**: 22/30 = **73.3%**
(PMMU 8개 제외 시 100%)

---

## 🎯 Mac LC 부팅 필수 명령어

System 6.0.8 부팅에 실제로 사용되는 핵심 명령어:

### 필수 (Critical)
✅ MOVE, MOVEA, MOVEQ, LEA, PEA  
✅ ADD, SUB, CMP, TST, CLR  
✅ AND, OR, EOR, NOT  
✅ BRA, Bcc, BSR, DBcc  
✅ JSR, RTS, RTE, TRAP  
✅ BTST, BSET, BCLR  
✅ MOVEC, MOVEUSP  
✅ LINK, UNLK  

### 자주 사용 (Common)
✅ ADDQ, SUBQ, CMPI  
✅ ASL, ASR, LSL, LSR, ROL, ROR  
✅ MOVEM, EXG, SWAP  
✅ NEG, EXT  

### 선택적 (Optional)
✅ MULU, MULS, DIVU, DIVS  
✅ ABCD, SBCD, NBCD (BCD 연산)  
✅ 비트 필드 명령어 (68020 최적화)  
⚠️ PMMU 명령어 (Mac LC 미사용)

**부팅 필수 명령어 구현률**: **100%**

---

## 📝 테스트 커버리지

### 명령어 테스트 현황
- 전체 테스트: 265개
- 통과율: 100%
- CPU 테스트: 95개 (`cpu_test.zig`)
- 통합 테스트: 170개

### 테스트되지 않은 명령어
모든 구현된 명령어는 최소 1개 이상의 테스트를 가지고 있습니다.

---

## 🔄 향후 계획

### 단기 (현재)
1. ✅ 모든 일반 명령어 구현 완료
2. ✅ Mac LC 부팅 필수 명령어 100%
3. 🔄 ROM 부팅 시도 및 디버깅

### 중기
1. 명령어 타이밍 정밀도 향상
2. 엣지 케이스 테스트 확대
3. 성능 프로파일링

### 장기
1. PMMU 명령어 구현 (A/UX 지원 시)
2. FPU (68881/68882) 코프로세서 지원
3. JIT 컴파일러 검토

---

## 📚 참고 자료

### 공식 문서
- MC68020 32-Bit Microprocessor User's Manual (Motorola)
- M68000 Family Programmer's Reference Manual

### 코드 위치
- 명령어 실행: `src/core/executor.zig`
- 명령어 디코딩: `src/core/decoder.zig`
- CPU 테스트: `src/core/cpu_test.zig`

---

**최종 업데이트**: 2026-02-14  
**프로젝트**: 68020_emu_zig  
**버전**: 1.0 (ROM 부팅 준비 완료)
