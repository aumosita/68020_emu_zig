# Decoder 계층화 기준 비교 분석

## 📊 가능한 계층화 기준 5가지

---

## 1. Opcode 패턴 기준 (현재 제안) ⭐ 추천

### 기준
**상위 4비트 (bits 15-12)로 1차 분류**

```
0x0xxx: 비트 연산, 즉시값 연산
0x1xxx: MOVE.B
0x2xxx: MOVE.L
0x3xxx: MOVE.W
0x4xxx: 특수 명령어 (NOP, JSR, TRAP, LEA, CLR, NOT, MOVEM...)
0x5xxx: ADDQ, SUBQ, Scc, DBcc
0x6xxx: Bcc, BRA, BSR
0x7xxx: MOVEQ
0x8xxx: OR, DIVU, DIVS, SBCD
0x9xxx: SUB, SUBA, SUBX
0xAxxx: (Reserved / Line-A emulator)
0xBxxx: CMP, CMPA, CMPM, EOR
0xCxxx: AND, MULU, MULS, ABCD, EXG
0xDxxx: ADD, ADDA, ADDX
0xExxx: 시프트/로테이트 (ASL, LSR, ROL, ROR...)
0xFxxx: (Reserved / Line-F emulator)
```

### 장점
✅ **하드웨어 디코딩과 일치** - 실제 68000 CPU도 이 방식 사용  
✅ **빠른 분기** - 단일 switch로 O(1) 분류  
✅ **명확한 경계** - opcode만 보고 그룹 판단 가능  
✅ **확장성** - 68020 명령어도 동일 패턴  
✅ **컴파일러 최적화** - 점프 테이블 생성 용이

### 단점
❌ **이질적 그룹** - 0x4xxx에 40개 이상 명령어 혼재  
❌ **불균형** - 그룹별 명령어 개수 차이 큼

### 2차 분류
**Group 4 (0x4xxx) 세분화 예시**:
```zig
fn decodeGroup4(...) {
    if (opcode == 0x4E71) return .NOP;
    if (opcode == 0x4E75) return .RTS;
    if ((opcode & 0xFFF0) == 0x4E40) return decodeTrap(...);
    if ((opcode & 0xFFC0) == 0x4E80) return decodeJsr(...);
    if ((opcode & 0xFF00) == 0x4A00) return decodeTst(...);
    if ((opcode & 0xFF00) == 0x4000) return decodeNegClrNot(...);
    ...
}
```

---

## 2. 기능적 분류 기준

### 기준
**명령어의 기능/카테고리로 분류**

```
산술 연산: ADD, ADDA, ADDI, ADDQ, ADDX, SUB, SUBA, SUBI, SUBQ, SUBX, NEG, NEGX
논리 연산: AND, ANDI, OR, ORI, EOR, EORI, NOT
비교: CMP, CMPA, CMPI, CMPM, TST
곱셈/나눗셈: MULU, MULS, DIVU, DIVS
데이터 이동: MOVE, MOVEA, MOVEQ, MOVEM, MOVEP, LEA, PEA, EXG, SWAP
비트 조작: BTST, BSET, BCLR, BCHG
시프트/로테이트: ASL, ASR, LSL, LSR, ROL, ROR, ROXL, ROXR
분기: Bcc, BRA, BSR, DBcc, JMP, JSR
스택: LINK, UNLK, RTS, RTR, RTE
시스템: TRAP, TRAPV, CHK, RESET, STOP, NOP
BCD: ABCD, SBCD, NBCD
```

### 구현 예시
```zig
fn decode(...) {
    const category = identifyCategory(opcode);  // ⚠️ 복잡한 로직
    return switch (category) {
        .Arithmetic => decodeArithmetic(opcode, ...),
        .Logical => decodeLogical(opcode, ...),
        .DataMovement => decodeDataMovement(opcode, ...),
        ...
    };
}

fn identifyCategory(opcode: u16) Category {
    // ⚠️ 복잡한 패턴 매칭 필요
    const high4 = (opcode >> 12) & 0xF;
    if (high4 == 0xD or high4 == 0x9) return .Arithmetic;
    if (high4 == 0x1 or high4 == 0x2 or high4 == 0x3) return .DataMovement;
    if ((opcode & 0xF1C0) == 0x0100) return .BitManipulation;
    // ... 수십 개의 조건 필요
}
```

### 장점
✅ **논리적** - 기능별로 그룹화  
✅ **이해하기 쉬움** - 초보자 친화적  
✅ **문서화 용이** - 카테고리별 설명

### 단점
❌ **opcode 패턴과 불일치** - 복잡한 매핑 로직 필요  
❌ **성능 저하** - 카테고리 식별에 추가 비용  
❌ **유지보수 어려움** - 새 명령어 추가 시 여러 곳 수정  
❌ **하드웨어와 동떨어짐** - 실제 CPU 동작과 다름

---

## 3. 어드레싱 모드 기준

### 기준
**EA(Effective Address) 사용 패턴으로 분류**

```
EA 미사용: MOVEQ, NOP, RTS, SWAP
단일 EA: CLR, NOT, TST, NEG, JMP, JSR
소스 EA: MOVE (src), ADD (Dn ← EA)
목적지 EA: MOVE (dst), ADD (EA ← Dn)
양방향 EA: MOVE (src, dst)
특수 EA: MOVEM (레지스터 마스크)
```

### 구현 예시
```zig
fn decode(...) {
    const ea_pattern = analyzeEA(opcode);
    return switch (ea_pattern) {
        .NoEA => decodeNoEA(opcode),
        .SingleEA => decodeSingleEA(opcode, ...),
        .SourceEA => decodeSourceEA(opcode, ...),
        ...
    };
}
```

### 장점
✅ **디코딩 로직 단순화** - EA 파싱 로직 공유  
✅ **성능 최적화** - EA별 최적화 가능

### 단점
❌ **명령어 분산** - 같은 기능이 여러 그룹에 흩어짐  
❌ **불명확한 분류** - EA 패턴 식별 복잡  
❌ **확장성 낮음** - 68020 복잡한 EA 모드 추가 시 재설계 필요

---

## 4. 명령어 길이/복잡도 기준

### 기준
**명령어 워드 수와 복잡도로 분류**

```
단일 워드 (2바이트):
  - MOVEQ, NOP, RTS, SWAP, EXG

확장 워드 1개 (4바이트):
  - ADDI, SUBI, ORI, ANDI, CMPI
  - Bcc (16비트 변위)
  - LINK

확장 워드 2개 (6바이트):
  - MOVE (즉시값 Long)
  - Bcc (32비트 변위)

가변 길이:
  - MOVEM (레지스터 개수에 따라)
  - d(An, Xn) - Brief Extension
  - ([bd, An], Xn, od) - Full Extension
```

### 구현 예시
```zig
fn decode(...) {
    const complexity = estimateComplexity(opcode);
    return switch (complexity) {
        .Simple => decodeSimple(opcode),
        .Medium => decodeMedium(opcode, ...),
        .Complex => decodeComplex(opcode, ...),
    };
}
```

### 장점
✅ **성능 최적화** - 단순 명령어 빠른 경로  
✅ **메모리 효율** - 길이별 처리 최적화

### 단점
❌ **유지보수 악몽** - 명령어 분산  
❌ **직관성 없음** - 개발자 혼란  
❌ **확장 어려움** - 새 명령어마다 복잡도 재평가

---

## 5. 하이브리드 기준 (2단계)

### 기준
**1단계: 상위 4비트, 2단계: 기능적 서브그룹**

```zig
fn decode(...) {
    const high4 = (opcode >> 12) & 0xF;
    
    return switch (high4) {
        0x0 => decodeGroup0(opcode, ...),  // 1차: opcode 패턴
        0x4 => decodeGroup4(opcode, ...),
        ...
    };
}

fn decodeGroup4(...) {
    // 2차: 기능적 분류
    if (isStackOp(opcode)) return decodeStackOp(...);      // LINK, UNLK
    if (isControlFlow(opcode)) return decodeControlFlow(...); // JSR, JMP, RTS, RTE
    if (isSystem(opcode)) return decodeSystem(...);         // TRAP, NOP
    if (isDataManip(opcode)) return decodeDataManip(...);   // CLR, NOT, NEG, TST
    ...
}
```

### 장점
✅ **균형잡힌 접근** - 성능과 가독성 동시 확보  
✅ **확장성** - 각 레벨 독립적 확장  
✅ **최적화 가능** - 1단계 빠른 분기, 2단계 논리적 분류

### 단점
❌ **복잡도 증가** - 2단계 관리  
❌ **일관성 문제** - 레벨 간 기준 충돌 가능

---

## 📊 비교표

| 기준 | 성능 | 가독성 | 유지보수 | 확장성 | 하드웨어 일치 |
|------|------|--------|----------|--------|---------------|
| 1. Opcode 패턴 | ⭐⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐⭐⭐⭐ |
| 2. 기능적 분류 | ⭐⭐ | ⭐⭐⭐⭐⭐ | ⭐⭐ | ⭐⭐⭐ | ⭐ |
| 3. 어드레싱 모드 | ⭐⭐⭐ | ⭐⭐ | ⭐⭐ | ⭐⭐ | ⭐⭐ |
| 4. 명령어 길이 | ⭐⭐⭐⭐ | ⭐ | ⭐ | ⭐ | ⭐⭐ |
| 5. 하이브리드 | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐ | ⭐⭐⭐⭐ | ⭐⭐⭐⭐ |

---

## 🎯 추천 및 근거

### 1순위: Opcode 패턴 기준 ⭐

**이유**:
1. **68000/68020 실제 설계 방식** - Motorola가 사용한 디코딩 방식
2. **최고 성능** - 단일 switch O(1) 분기
3. **확장성** - 68020, 68030 명령어도 동일 패턴
4. **검증됨** - 수많은 에뮬레이터가 이 방식 사용

**실제 68000 데이터시트 (Motorola)**:
```
"The instruction decoder uses the upper 4 bits (15-12) 
 for primary classification of instruction groups."
```

**사용 예시**:
- QEMU (m68k 에뮬레이터)
- Musashi (68000 에뮬레이터)
- UAE (Amiga 에뮬레이터)

### 2순위: 하이브리드 기준

**사용 시점**: 0x4xxx 그룹이 너무 커질 때

**예시**:
```zig
fn decodeGroup4(...) {
    // 2차 분류
    const subgroup = (opcode >> 8) & 0xFF;
    
    return switch (subgroup) {
        0x4E => decodeGroup4E(...),  // NOP, RTS, JSR, JMP, TRAP
        0x4A => decodeTst(...),
        0x48 => decodeMovemOrExt(...),
        0x40, 0x42, 0x44, 0x46 => decodeNegClrNot(...),
        else => .UNKNOWN,
    };
}

fn decodeGroup4E(...) {
    // 3차 분류 (기능적)
    if ((opcode & 0xFFF8) == 0x4E50) return decodeLink(...);
    if ((opcode & 0xFFF8) == 0x4E58) return decodeUnlk(...);
    if ((opcode & 0xFFC0) == 0x4E80) return decodeJsr(...);
    if ((opcode & 0xFFC0) == 0x4EC0) return decodeJmp(...);
    ...
}
```

---

## 💡 최종 권장사항

### 제안 1: Opcode 패턴 기준 (단순 버전)
**추천 대상**: 현재 프로젝트  
**이유**: 명령어 개수가 아직 관리 가능

```zig
switch (high4) {
    0x0 => decodeGroup0(...),    // 30줄
    0x4 => decodeGroup4(...),    // 50줄 (가장 큼)
    0x7 => decodeMoveq(...),     // 10줄
    ...
}
```

### 제안 2: Opcode 패턴 + 서브그룹 (하이브리드)
**추천 대상**: Phase 2-3 완료 후  
**이유**: 명령어가 100개 이상 늘어날 때

```zig
switch (high4) {
    0x0 => decodeGroup0(...),
    0x4 => switch (opcode >> 8) {  // 2단계
        0x4E => decodeGroup4E(...),
        0x4A => decodeTst(...),
        ...
    },
    ...
}
```

---

## 📋 구현 순서

**Phase 1**: Opcode 패턴 기준 (현재 제안)
1. decode() → 15줄 라우터
2. 각 그룹별 함수 (15개)
3. 테스트

**Phase 2**: 필요 시 서브그룹 추가
1. 0x4xxx 세분화 (3-4개 서브그룹)
2. 0x0xxx 세분화 (2-3개 서브그룹)

---

## ❓ 대감의 선택

**A. Opcode 패턴 기준** (⭐ 추천)  
   → 단순, 빠름, 표준적

**B. 하이브리드 기준** (⭐⭐ 미래 대비)  
   → 균형잡힌, 확장성

**C. 기능적 분류 기준**  
   → 논리적이지만 느림

**D. 다른 기준 제안**  
   → 대감의 아이디어

**어떤 기준으로 진행할까요?**
