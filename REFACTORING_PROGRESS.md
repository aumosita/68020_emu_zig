# Decoder 리팩토링 진행 상황

## 작업 계획

### 리팩토링 전략
1. 기존 decoder.zig.backup 보존 (이미 완료)
2. decode() 함수를 라우터로 변경
3. 각 그룹별로 개별 함수 추출
4. 각 단계마다 테스트

### 그룹 분류 (Opcode 상위 4비트 기준)

```
0x0: Bit operations, Immediate operations
0x1-0x3: MOVE family
0x4: Special (NOP, RTS, JSR, TRAP, LEA, CLR, TST, etc.)
0x5: ADDQ, SUBQ, DBcc, Scc
0x6: Branch (Bcc, BRA, BSR)
0x7: MOVEQ
0x8: OR, DIVU, DIVS, SBCD
0x9, 0xD: SUB/ADD family
0xB: CMP, EOR, CMPM
0xC: AND, MULU, MULS, ABCD, EXG
0xE: Shift/Rotate
```

### 작업 순서 (단순 → 복잡)

1. ✅ **Group 7 (MOVEQ)** - 가장 단순 (5분)
2. ⏳ **Group 6 (Branch)** - 단순 (10분)
3. ⏳ **Group 1-3 (MOVE)** - 단순 (10분)
4. ⏳ **Group 5 (ADDQ/SUBQ/DBcc/Scc)** - 중간 (15분)
5. ⏳ **Group 8 (OR/DIV/SBCD)** - 중간 (15분)
6. ⏳ **Group 9/D (SUB/ADD)** - 중간 (15분)
7. ⏳ **Group B (CMP/EOR)** - 중간 (15분)
8. ⏳ **Group C (AND/MUL)** - 중간 (15분)
9. ⏳ **Group E (Shift/Rotate)** - 중간 (15분)
10. ⏳ **Group 0 (Bit ops)** - 복잡 (20분)
11. ⏳ **Group 4 (Special)** - 가장 복잡 (30분)

**총 예상 시간**: 2-3시간

---

## 진행 상황

### 준비 완료
- ✅ 백업 완료: `src/decoder.zig.backup`
- ✅ 현재 파일 라인 수: 681줄
- ✅ 테스트 환경 준비

### 다음 단계
점진적 리팩토링 시작
- 한 그룹씩 추출
- 각 단계마다 테스트

---

**시작 시각**: ~09:05
**예상 완료**: ~11:00-12:00
