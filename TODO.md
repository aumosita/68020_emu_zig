# 68020 에뮬레이터 - 미구현 명령어 목록

## 현재 구현 상태

### ✅ 구현 완료 (57개)
- 데이터 이동: MOVE, MOVEA, MOVEQ, LEA, PEA, SWAP, MOVEM
- 산술: ADD계열(5), SUB계열(5), MUL(2), DIV(2), NEG(2), CLR, EXT
- 논리: AND(3), OR(3), EOR(3), NOT
- 시프트/로테이트: ASL, ASR, LSL, LSR, ROL, ROR, ROXL, ROXR (8개)
- 비트: BTST, BSET, BCLR, BCHG (4개)
- 스택: LINK, UNLK
- 프로그램 제어: BRA, Bcc, JSR, RTS, NOP
- 비교: CMP, CMPA, CMPI, TST

### ⏳ 미구현 (약 20-25개)

#### 1. BCD 연산 (3개) - 우선순위: 중
- **ABCD** - Add BCD with extend
  - opcode: 0xC100-0xC10F (Dx,Dy 또는 -(Ax),-(Ay))
  - 용도: BCD 덧셈
  
- **SBCD** - Subtract BCD with extend
  - opcode: 0x8100-0x810F
  - 용도: BCD 뺄셈
  
- **NBCD** - Negate BCD with extend
  - opcode: 0x4800
  - 용도: BCD 부정

#### 2. 프로그램 제어 (8개) - 우선순위: 높음

- **JMP** - Jump (조건 없는 점프)
  - opcode: 0x4EC0
  - JSR와 유사하지만 return address를 push하지 않음
  - 이미 디코더에 일부 코드 있음
  
- **BSR** - Branch to subroutine
  - opcode: 0x6100
  - JSR의 상대 주소 버전
  
- **DBcc** - Decrement and branch conditionally
  - opcode: 0x50C8-0x5FC8
  - 용도: 루프 제어 (Dn 감소하고 조건부 분기)
  - 이미 디코더에 일부 코드 있음
  
- **Scc** - Set according to condition
  - opcode: 0x50C0-0x5FFF
  - 조건에 따라 바이트를 0x00 또는 0xFF로 설정
  
- **RTR** - Return and restore condition codes
  - opcode: 0x4E77
  - CCR 복원 후 리턴
  
- **RTE** - Return from exception
  - opcode: 0x4E73
  - SR 및 PC 복원
  
- **TRAP** - Trap
  - opcode: 0x4E40-0x4E4F
  - 소프트웨어 인터럽트
  
- **TRAPV** - Trap on overflow
  - opcode: 0x4E76
  - V 플래그가 설정되면 trap

#### 3. 데이터 이동/교환 (3개) - 우선순위: 중

- **EXG** - Exchange registers
  - opcode: 0xC140, 0xC148, 0xC188
  - Dn↔Dn, An↔An, Dn↔An 교환
  - 디코더에 일부 코드 있음
  
- **MOVEP** - Move peripheral data
  - opcode: 0x0108, 0x0148, 0x0188, 0x01C8
  - 메모리↔레지스터 (바이트 간격으로)
  - 주변장치 I/O용
  
- **CMPM** - Compare memory
  - opcode: 0xB108-0xB1CF
  - (Ay)+와 (Ax)+ 비교

#### 4. 기타 제어 (4개) - 우선순위: 낮음

- **CHK** - Check register against bounds
  - opcode: 0x4180, 0x4100
  - 범위 체크, 벗어나면 exception
  
- **TAS** - Test and set
  - opcode: 0x4AC0
  - 테스트 후 최상위 비트 설정 (원자적 연산)
  
- **RESET** - Reset external devices
  - opcode: 0x4E70
  - 외부 장치 리셋 신호
  
- **STOP** - Stop and wait
  - opcode: 0x4E72
  - 즉시값을 SR에 로드하고 정지

#### 5. 68020 전용 (선택적) - 우선순위: 매우 낮음

- **EXTB** - Sign extend byte to long
  - opcode: 0x49C0
  - EXT의 68020 확장
  
- **BFCHG, BFCLR, BFEXTS, BFEXTU, BFFFO, BFINS, BFSET, BFTST**
  - 비트 필드 연산 (68020)
  - 복잡하고 자주 사용되지 않음
  
- **CAS, CAS2** - Compare and swap
  - 원자적 연산 (68020)
  
- **PACK, UNPK** - Pack/Unpack BCD
  - BCD 변환 (68020)

## 권장 구현 순서

### Phase 1: 프로그램 제어 완성 (가장 중요)
1. **JMP** - 매우 간단, JSR 복사 후 push 제거
2. **BSR** - BRA와 유사 + return address push
3. **DBcc** - 루프에 필수적
4. **Scc** - 조건부 설정, 유용함

### Phase 2: 필수 유틸리티
5. **RTR** - RTS와 유사 + CCR 복원
6. **RTE** - 예외 처리에 필수
7. **TRAP** - 시스템 콜에 필수
8. **TAS** - 멀티태스킹/동기화에 유용

### Phase 3: 특수 연산
9. **EXG** - 레지스터 교환
10. **CMPM** - 메모리 비교
11. **CHK** - 배열 범위 체크

### Phase 4: BCD 연산 (선택적)
12. **ABCD, SBCD, NBCD** - BCD 산술

### Phase 5: 주변장치/시스템 (선택적)
13. **MOVEP** - 주변장치 I/O
14. **TRAPV** - 오버플로우 trap
15. **RESET, STOP** - 시스템 제어

## 예상 작업량

- **JMP, BSR, RTR**: 각 10-20분 (기존 코드 재사용)
- **DBcc, Scc**: 각 20-30분 (조건 평가 로직 필요)
- **TRAP, RTE**: 각 30-40분 (예외 처리 프레임워크)
- **EXG, CMPM, CHK**: 각 15-25분
- **BCD 연산**: 각 20-30분 (BCD 로직)
- **MOVEP, TAS**: 각 20-30분

**총 예상 시간**: 약 4-6시간 (Phase 1-3 완성)

## 실용성 평가

### 필수 (90% 이상의 프로그램에서 사용)
- JMP, BSR, DBcc, Scc, RTE, TRAP

### 유용 (50-80% 프로그램에서 사용)
- RTR, TAS, EXG, CMPM, CHK

### 선택적 (20% 미만)
- BCD 연산, MOVEP, TRAPV, RESET, STOP

### 거의 사용 안함
- 68020 전용 비트 필드 연산, CAS, PACK/UNPK

## 결론

**기본 68000 호환을 위한 최소 추가 구현:**
- JMP, BSR, DBcc, Scc, RTR, RTE, TRAP (7개)

**완전한 68000 호환:**
- 위 + EXG, CMPM, CHK, TAS, BCD 3개, MOVEP, TRAPV (15개)

**68020 완전 구현:**
- 위 + EXTB, 비트 필드 8개, CAS/CAS2, PACK/UNPK (15개 추가)

현재 57개 + Phase 1-3 (15개) = **72개 명령어**로 실용적인 68000 에뮬레이션 완성
