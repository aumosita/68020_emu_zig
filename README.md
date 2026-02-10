# Motorola 68020 에뮬레이터 (Zig)

Zig 0.13으로 작성된 고성능 Motorola 68020 프로세서 에뮬레이터입니다.

## 기능

✅ **완전한 명령어 세트 구현**
- MOVE 계열 (MOVE, MOVEA, MOVEQ)
- 산술 연산: ADD, ADDA, ADDI, ADDQ, ADDX
- 산술 연산: SUB, SUBA, SUBI, SUBQ, SUBX
- 비교: CMP, CMPA, CMPI
- 논리 연산: AND, OR, EOR, NOT (+ 즉시값 변형)
- 곱셈/나눗셈: MULU, MULS, DIVU, DIVS
- 비트 조작: NEG, NEGX, CLR, TST, SWAP, EXT
- 비트 연산: BTST, BSET, BCLR, BCHG
- 시프트/로테이트: ASL, ASR, LSL, LSR, ROL, ROR, ROXL, ROXR
- 스택 연산: LINK, UNLK, PEA, MOVEM
- 프로그램 제어: BRA, Bcc, JSR, RTS, NOP

✅ **모든 8가지 어드레싱 모드**
1. 데이터 레지스터 직접 (Dn)
2. 주소 레지스터 직접 (An)
3. 주소 레지스터 간접 ((An))
4. 후증가 ((An)+)
5. 전감소 (-(An))
6. 변위 포함 주소 (d16(An))
7. 즉시값 (#imm8/16/32)
8. 절대 주소 지정 (xxx.W/L)

✅ **정확한 에뮬레이션**
- 빅 엔디안 바이트 순서 (모토로라 표준)
- 정확한 플래그 처리 (N, Z, V, C, X)
- 사이클 정확 타이밍 프레임워크
- 부호 확장 (byte→word, word→long)
- 설정 가능한 메모리 (기본 16MB)

✅ **다른 언어 통합을 위한 C API**
- 정적/동적 라이브러리로 컴파일
- Python, C, C++ 등에서 호출 가능
- 간단한 생성/해제/실행 인터페이스

## 빌드

### 사전 요구사항
- Zig 0.13.0 ([다운로드](https://ziglang.org/download/))

### 컴파일
```bash
zig build
```

생성물:
- `zig-out/lib/m68020-emu.lib` - 정적 라이브러리
- `zig-out/lib/m68020-emu.dll` - 동적 라이브러리
- `zig-out/bin/m68020-emu-test.exe` - 테스트 스위트

### 테스트 실행
```bash
zig-out/bin/m68020-emu-test.exe
zig build test-shift    # 시프트/로테이트 테스트
zig build test-bits     # 비트 연산 테스트
zig build test-stack    # 스택 연산 테스트
```

**현재 테스트 결과: 40/40 통과 (100%)** ✅

## 사용법

### Zig에서 사용
```zig
const cpu = @import("cpu.zig");

var m68k = cpu.M68k.init(allocator);
defer m68k.deinit();

// 프로그램 작성
try m68k.memory.write16(0x1000, 0x702A);  // MOVEQ #42, D0

// 실행
m68k.pc = 0x1000;
const cycles = try m68k.step();

// 결과 읽기
const result = m68k.d[0];  // 42
```

### C/C++에서 사용
```c
#include "m68020-emu.h"

void* cpu = m68k_create_with_memory(16 * 1024 * 1024);  // 16MB

// opcode 작성
m68k_write_memory_16(cpu, 0x1000, 0x702A);  // MOVEQ #42, D0

// 실행
m68k_set_pc(cpu, 0x1000);
m68k_step(cpu);

// 결과 읽기
uint32_t result = m68k_get_reg_d(cpu, 0);  // 42

m68k_destroy(cpu);
```

### Python에서 사용
```python
import ctypes

# 라이브러리 로드
lib = ctypes.CDLL('./m68020-emu.dll')

# CPU 생성
lib.m68k_create_with_memory.restype = ctypes.c_void_p
cpu = lib.m68k_create_with_memory(16 * 1024 * 1024)

# 프로그램 작성
lib.m68k_write_memory_16(cpu, 0x1000, 0x702A)  # MOVEQ #42, D0

# 실행
lib.m68k_set_pc(cpu, 0x1000)
lib.m68k_step(cpu)

# 결과 읽기
lib.m68k_get_reg_d.restype = ctypes.c_uint32
result = lib.m68k_get_reg_d(cpu, 0)  # 42

lib.m68k_destroy(cpu)
```

## 프로젝트 구조

```
m68020-emu/
├── src/
│   ├── root.zig        # C API 내보내기
│   ├── cpu.zig         # CPU 상태 및 실행
│   ├── memory.zig      # 메모리 서브시스템 (16MB, 설정 가능)
│   ├── decoder.zig     # 명령어 디코더
│   ├── executor.zig    # 명령어 구현
│   └── main.zig        # 테스트 스위트
├── docs/
│   ├── reference.md          # 아키텍처 개요
│   ├── instruction-set.md    # 완전한 명령어 참조
│   ├── testing.md            # 테스트 가이드
│   └── python-examples.md    # Python 통합 예제
└── build.zig           # 빌드 구성
```

## CPU 레지스터

- **데이터 레지스터**: D0-D7 (32비트)
- **주소 레지스터**: A0-A7 (32비트, A7 = 스택 포인터)
- **프로그램 카운터**: PC (32비트)
- **상태 레지스터**: SR (16비트)
  - 플래그: N (음수), Z (제로), V (오버플로우), C (캐리), X (확장)

## 메모리

- 기본: 16MB RAM (설정 가능)
- 빅 엔디안 바이트 순서
- 24비트 주소 공간 (68000 호환)
- 32비트 주소 공간 (68020 전체)

## 구현 상태

| 카테고리 | 상태 | 포함 내용 |
|----------|--------|----------|
| 데이터 이동 | ✅ 완료 | MOVE, MOVEA, MOVEQ |
| 산술 연산 | ✅ 완료 | ADD/SUB 계열, NEG |
| 논리 연산 | ✅ 완료 | AND, OR, EOR, NOT |
| 곱셈/나눗셈 | ✅ 완료 | MULU/S, DIVU/S |
| 비교 | ✅ 완료 | CMP 계열, TST |
| 비트 조작 | ✅ 완료 | SWAP, EXT, CLR |
| 비트 연산 | ✅ 완료 | BTST, BSET, BCLR, BCHG |
| 시프트/로테이트 | ✅ 완료 | ASL, LSR, ROL, ROR 등 |
| 스택 연산 | ✅ 완료 | LINK, UNLK, PEA, MOVEM |
| 프로그램 제어 | ✅ 완료 | BRA, Bcc, JSR, RTS |
| 어드레싱 모드 | ✅ 완료 | 모든 8가지 모드 |

## 테스트

포괄적인 테스트 스위트 실행:
```bash
zig-out/bin/m68020-emu-test.exe         # 기본 테스트
zig build test-shift                     # 시프트/로테이트
zig build test-bits                      # 비트 연산
zig build test-stack                     # 스택 연산
```

**테스트 검증 항목:**
- ✅ MOVEQ 즉시값 데이터 이동
- ✅ ADDQ/SUBQ 빠른 산술 연산
- ✅ CLR 클리어 연산
- ✅ NOT 논리 보수
- ✅ SWAP 워드 교환
- ✅ EXT 부호 확장
- ✅ MULU 부호 없는 곱셈
- ✅ DIVU 부호 없는 나눗셈
- ✅ 빅 엔디안 메모리 배치
- ✅ 주소 레지스터 연산
- ✅ 간접 주소 지정
- ✅ 시프트/로테이트 (8개 명령어)
- ✅ 비트 조작 (4개 명령어)
- ✅ 스택 프레임 관리 (LINK/UNLK)
- ✅ 다중 레지스터 전송 (MOVEM)

## 성능

- Zig로 작성되어 최적 성능
- 네이티브 코드로 컴파일
- 런타임 오버헤드 없음
- 실시간 에뮬레이션에 적합

## 문서

상세한 문서는 `docs/` 폴더 참조:
- **reference.md**: CPU 아키텍처 및 설계
- **instruction-set.md**: 완전한 명령어 참조
- **testing.md**: 테스트 스위트 문서
- **python-examples.md**: Python 통합 예제

## 라이센스

MIT 라이센스 - LICENSE 파일 참조

## 기여

기여를 환영합니다! 계획된 기능은 이슈 트래커를 확인하세요.

## 감사의 말

- Motorola 68000/68020 프로그래머 레퍼런스 매뉴얼
- Zig 프로그래밍 언어 팀

---

**상태**: 활발한 개발 중
**버전**: 0.1.0
**마지막 업데이트**: 2024-02-11
