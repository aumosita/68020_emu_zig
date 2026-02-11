# 68020 스택 포인터 모델 상세 규격

## 개요

68020은 3개의 스택 포인터를 제공합니다:
- **USP (User Stack Pointer)**: 사용자 모드 스택
- **ISP (Interrupt Stack Pointer)**: 인터럽트/예외 처리 스택
- **MSP (Master Stack Pointer)**: 마스터 모드 스택

SR 레지스터의 S 비트(bit 13)와 M 비트(bit 12)가 현재 활성 스택을 결정합니다.

## 스택 결정 규칙

| S 비트 | M 비트 | 활성 스택 | 모드 설명 |
|--------|--------|-----------|-----------|
| 0      | 0      | USP       | 사용자 모드 |
| 0      | 1      | USP       | 사용자 모드 (M 비트 무시) |
| 1      | 0      | ISP       | 슈퍼바이저 모드 (인터럽트) |
| 1      | 1      | MSP       | 슈퍼바이저 모드 (마스터) |

**중요**: M 비트는 S=1 (슈퍼바이저 모드)일 때만 유효합니다.

## SR 변경 시 스택 전환 동작

### SR 쓰기 프로토콜

1. **현재 A7 → 현재 스택 레지스터에 저장** (`saveActiveStackPointer`)
2. **SR 업데이트**
3. **새로운 스택 레지스터 → A7로 로드** (`loadActiveStackPointer`)

### 8가지 전환 케이스

| 이전 상태 (S/M) | 새 상태 (S/M) | A7 저장 대상 | A7 로드 소스 | 비고 |
|----------------|--------------|-------------|-------------|------|
| 0/x → 0/x      | User → User  | USP         | USP         | 변화 없음 |
| 0/x → 1/0      | User → ISP   | USP         | ISP         | 예외/인터럽트 진입 |
| 0/x → 1/1      | User → MSP   | USP         | MSP         | 드물지만 가능 |
| 1/0 → 0/x      | ISP → User   | ISP         | USP         | RTE로 사용자 복귀 |
| 1/0 → 1/0      | ISP → ISP    | ISP         | ISP         | 변화 없음 |
| 1/0 → 1/1      | ISP → MSP    | ISP         | MSP         | 모드 전환 |
| 1/1 → 0/x      | MSP → User   | MSP         | USP         | RTE로 사용자 복귀 |
| 1/1 → 1/0      | MSP → ISP    | MSP         | ISP         | **예외 진입** |
| 1/1 → 1/1      | MSP → MSP    | MSP         | MSP         | 변화 없음 |

## 예외/인터럽트 진입 규칙

### 예외 진입 시 스택 선택

**68020 규칙**: 예외/인터럽트 진입 시 항상 **ISP를 사용**합니다.

```
old_sr = SR
new_sr = old_sr | FLAG_S
new_sr &= ~FLAG_M    // M 비트를 명시적으로 클리어
setSR(new_sr)        // 이제 ISP가 활성화됨
push_exception_frame()
```

**시나리오별 동작**:

| 진입 전 모드 | 진입 후 스택 | 저장된 스택 |
|-------------|-------------|-------------|
| User (0/x)  | ISP (1/0)   | USP         |
| ISP (1/0)   | ISP (1/0)   | ISP (중첩)  |
| MSP (1/1)   | ISP (1/0)   | **MSP**     |

**중요 사례**: Master 모드에서 예외 발생 시
- 현재 MSP의 A7 값이 MSP 레지스터에 저장
- ISP가 활성화되어 예외 프레임이 ISP에 푸시
- MSP 값은 보존되어 나중에 복귀 가능

## RTE 복귀 규칙

### RTE 동작 순서

1. 스택에서 프레임 포맷 읽기
2. SR 복원 (→ 이때 `setSR` 호출로 스택 자동 전환)
3. PC 복원
4. 프레임 크기만큼 SP 증가

### 복귀 시나리오

```
예: MSP → (예외) → ISP → (RTE) → MSP

1. [MSP=0x3000] TRAP 발생
2. setSR(0x2000) → MSP에 0x3000 저장, ISP 활성화
3. 예외 처리 중 [ISP=0x1FF8]
4. RTE 실행:
   - 스택에서 SR 읽기 → 0x3000 (S=1, M=1)
   - setSR(0x3000) → ISP에 현재 값 저장, MSP 활성화
   - A7 = 0x3000 복원
```

## MOVE USP / MOVEC 명령 상호작용

### MOVE USP, An / MOVE An, USP

- **슈퍼바이저 전용** 명령
- USP 레지스터를 직접 읽기/쓰기
- **현재 활성 스택과 무관**하게 동작
- User 모드가 아닌 상태에서도 USP 값 조작 가능

### MOVEC Rn, USP / MOVEC USP, Rn

- MOVE USP와 동일한 동작
- 레지스터 번호 0x800

### MOVEC Rn, ISP / MOVEC ISP, Rn

- ISP 레지스터를 직접 읽기/쓰기
- **현재 활성 스택이 ISP여도 A7은 자동 업데이트되지 않음**
- 레지스터 번호 0x801

### MOVEC Rn, MSP / MOVEC MSP, Rn

- MSP 레지스터를 직접 읽기/쓰기
- **현재 활성 스택이 MSP여도 A7은 자동 업데이트되지 않음**
- 레지스터 번호 0x802

### 혼합 사용 시 주의사항

**잘못된 패턴**:
```assembly
; 현재 ISP 모드 (S=1, M=0)
MOVEC D0, ISP      ; ISP 레지스터 변경
; A7은 여전히 예전 ISP 값! 불일치 발생
```

**올바른 패턴**:
```assembly
; ISP 값을 변경하려면:
MOVE.L D0, A7      ; 현재 활성 스택(ISP)를 직접 변경
; 또는
MOVEC D0, ISP      ; ISP 레지스터 변경
ANDI #$DFFF, SR    ; M=0으로 강제 설정 (이미 0이지만 명시)
ORI #$2000, SR     ; S=1, M=0 재확인 → setSR 호출로 A7 동기화
```

## 구현 검증 체크리스트

### 필수 테스트 케이스

- [x] User → ISP 전환 (예외 진입)  
  - `src/cpu.zig` `test "M68k IRQ from user mode uses ISP and RTE restores USP"`
- [x] ISP → User 전환 (RTE)  
  - `src/cpu.zig` `test "M68k IRQ from user mode uses ISP and RTE restores USP"`
- [x] User → MSP 전환 (이론적 케이스)  
  - `src/cpu.zig` `test "M68k setSR stack transition matrix preserves banked pointers"`
- [x] MSP → User 전환 (RTE)  
  - `src/cpu.zig` `test "M68k setSR stack transition matrix preserves banked pointers"`
- [x] MSP → ISP 전환 (예외 진입)  
  - `src/cpu.zig` `test "M68k exception from master stack uses ISP and RTE restores MSP"`  
  - `src/cpu.zig` `test "M68k IRQ from master mode switches to ISP and RTE restores MSP"`
- [x] ISP → MSP 전환 (모드 전환)  
  - `src/cpu.zig` `test "M68k setSR stack transition matrix preserves banked pointers"`
- [x] MSP → ISP → MSP 복귀 (중첩 예외)  
  - `src/cpu.zig` `test "M68k exception from master stack uses ISP and RTE restores MSP"`
- [x] ISP → ISP 중첩 (인터럽트 중첩)  
  - `src/cpu.zig` `test "M68k nested IRQ frames stay on ISP and unwind with RTE"`
- [x] MOVE USP 사용 후 User 복귀 일관성  
  - `src/cpu.zig` `test "M68k MOVE USP transfers and user restore consistency"`
- [x] MOVEC ISP/MSP 후 A7 불일치 검출  
  - `src/cpu.zig` `test "M68k MOVEC stack registers do not force active A7 sync"`
- [x] 인터럽트 진입 시 활성 스택 전환 검증  
  - `src/cpu.zig` `test "M68k IRQ from user mode uses ISP and RTE restores USP"`  
  - `src/cpu.zig` `test "M68k IRQ from master mode switches to ISP and RTE restores MSP"`
- [x] RTE 복귀 시 모든 스택 레지스터 복원 검증  
  - `src/cpu.zig` `test "M68k setSR stack transition matrix preserves banked pointers"`  
  - `src/cpu.zig` `test "M68k nested IRQ frames stay on ISP and unwind with RTE"`

### 엣지 케이스

- [x] **제로 초기화 fallback**: `loadActiveStackPointer`에서 스택이 0이면 fallback 사용  
  - `src/cpu.zig` `test "M68k stack register fallback loads active A7 when target bank is zero"`
- [x] **reset() 동작**: ISP와 MSP 모두 초기 A7로 설정  
  - `src/cpu.zig` `test "M68k reset initializes ISP/MSP from reset vector stack pointer"`
- [x] **STOP 상태에서 인터럽트**: STOP 중에도 스택 전환 정상 동작  
  - `src/cpu.zig` `test "M68k STOP halts until interrupt and resumes on IRQ"`
- [x] **Bus error 프레임 A**: 24바이트 프레임 생성 검증  
  - `src/cpu.zig` `test "M68k bus error during instruction fetch creates format A frame"`  
  - 스택 선택(USP/ISP/MSP 조합) 전용 회귀는 추가 가능

## 참고: Motorola 68020 매뉴얼

- **Section 6.1.1**: Supervisor/User State
- **Section 6.1.3**: Master/Interrupt State  
- **Section 6.3**: Exception Processing
- **Table 6-1**: Stack Pointer Selection

---

**작성일**: 2026-02-11  
**상태**: 검증 완료 (체크리스트 기준)
