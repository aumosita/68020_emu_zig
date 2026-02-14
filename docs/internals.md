# CPU 내부 동작 참고

## 68000 vs 68020 핵심 차이

- 주소: 68000은 24비트, 68020은 32비트
- 스택: 68000은 USP/SSP, 68020은 USP/ISP/MSP 3개
- 명령어: 비트 필드, CAS/CAS2, 32비트 곱셈/나눗셈 등 추가
- EA: 전체 인덱스 확장 (bd, od, 메모리 간접)

## 스택 포인터 모델

68020은 3개의 스택 포인터 (USP, ISP, MSP)를 제공. SR의 S/M 비트로 선택:

| S | M | 활성 스택 | 모드 |
|---|---|-----------|------|
| 0 | x | USP | User |
| 1 | 0 | ISP | Supervisor (Interrupt) |
| 1 | 1 | MSP | Supervisor (Master) |

**예외 진입**: 항상 M=0으로 클리어 → ISP 사용  
**RTE**: 저장된 SR 복원 → 자동 스택 전환  
**MOVEC ISP/MSP**: 라스트 A7 자동 동기화 안 됨 (주의!)

## 에러 처리

`src/core/errors.zig`에 정의된 구조화된 에러 타입:

| 카테고리 | 에러 | C API 코드 |
|----------|------|-----------|
| MemoryError | InvalidAddress, BusError, AddressError, BusRetry, BusHalt | -2 ~ -6 |
| CpuError | IllegalInstruction, PrivilegeViolation, DivisionByZero 등 | -10 ~ -16 |
| DecodeError | InvalidOpcode, InvalidEAMode 등 | -20 ~ -23 |
| ConfigError | InvalidConfig, InvalidMemorySize 등 | -30 ~ -32 |

사용 패턴:
```zig
// 구체적 에러 타입 사용
pub fn fetch(addr: u32) errors.MemoryError!u16 { ... }
// C API 경계에서만 상태 코드로 변환
return errors.errorToStatus(@errorCast(err));
```

## MOVEC 제어 레지스터

| 코드 | 레지스터 | 설명 |
|------|----------|------|
| 0x000 | SFC | Source Function Code |
| 0x001 | DFC | Destination Function Code |
| 0x002 | CACR | Cache Control Register |
| 0x800 | USP | User Stack Pointer |
| 0x801 | VBR | Vector Base Register |
| 0x802 | CAAR | Cache Address Register |
| 0x803 | MSP | Master Stack Pointer |
| 0x804 | ISP | Interrupt Stack Pointer |

## 코프로세서 처리

FPU(68881/68882)는 미구현. F-line opcode(`0xFxxx`) → COPROC 디스패처 → 예외 벡터 11(F-line trap)로 라우팅. 실제 코프로세서 프로토콜이 필요한 경우 `M68k.CoprocessorHandler` 콜백을 통해 외부에서 구현 가능.

## PMMU 난이도 요약

68020+68851 PMMU 8개 명령어 중 **PTEST가 가장 난이도 높음** (모든 PMMU 기능 통합 + 진단 정보). 현재 호환 레이어로 우회 처리 중.
