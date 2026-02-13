# 타이밍 회귀 테스트 자동화 가이드

## 목적

명령어 사이클 변경 사항을 자동으로 검증하여 의도하지 않은 성능 회귀를 방지합니다.

---

## 검증 벡터 형식

### JSON 구조

```json
{
  "name": "테스트 케이스 이름",
  "setup": {
    "pc": 4096,
    "sr": 8192,
    "steps": 1,
    "d": [레지스터 초기값...],
    "a": [주소 레지스터 초기값...],
    "memory16": [{ "addr": 주소, "value": 값 }],
    "memory32": [{ "addr": 주소, "value": 값 }]
  },
  "expect": {
    "pc": 예상 PC,
    "step_cycles": 예상 사이클,  // ⭐ 핵심 필드
    "total_cycles": 누적 사이클 (옵션),
    "d": [{ "idx": 레지스터번호, "value": 예상값 }],
    "memory32": [{ "addr": 주소, "value": 예상값 }]
  }
}
```

### 주요 필드

- **`step_cycles`**: 해당 명령어 실행의 정확한 사이클 수 (필수)
- **`total_cycles`**: 누적 사이클 (다중 step의 경우 검증용)

---

## 작성 예시

### 1. MOVE Dn,Dn (가장 빠른 경우)

```json
{
  "name": "move_dn_to_dn",
  "setup": {
    "pc": 4096,
    "d": [305419896, 0, 0, 0, 0, 0, 0, 0],
    "memory16": [{ "addr": 4096, "value": 8704 }]
  },
  "expect": {
    "pc": 4098,
    "step_cycles": 4,
    "d": [
      { "idx": 0, "value": 305419896 },
      { "idx": 1, "value": 305419896 }
    ]
  }
}
```

**사이클 계산**: 4 (기본) + 0 (src EA) + 0 (dst EA) = **4**

---

### 2. MOVE Dn,(An) (메모리 쓰기)

```json
{
  "name": "move_dn_to_an_indirect",
  "setup": {
    "pc": 4096,
    "d": [2864434397, 0, 0, 0, 0, 0, 0, 0],
    "a": [8192, 0, 0, 0, 0, 0, 0, 0],
    "memory16": [{ "addr": 4096, "value": 8848 }]
  },
  "expect": {
    "pc": 4098,
    "step_cycles": 8,
    "memory32": [{ "addr": 8192, "value": 2864434397 }]
  }
}
```

**사이클 계산**: 4 (기본) + 0 (src EA) + 4 (dst EA indirect) = **8**

---

### 3. MOVE (An)+,-(An) (메모리 간 이동)

```json
{
  "name": "move_an_postinc_to_predec",
  "setup": {
    "pc": 4096,
    "a": [8192, 12288, 0, 0, 0, 0, 0, 0],
    "memory16": [{ "addr": 4096, "value": 8505 }],
    "memory32": [{ "addr": 8192, "value": 2864434397 }]
  },
  "expect": {
    "pc": 4098,
    "step_cycles": 14,
    "a": [
      { "idx": 0, "value": 8196 },
      { "idx": 1, "value": 12284 }
    ],
    "memory32": [{ "addr": 12284, "value": 2864434397 }]
  }
}
```

**사이클 계산**: 4 (기본) + 4 (src EA postinc) + 6 (dst EA predec) = **14**

---

## 사이클 계산 참조표

| EA 모드 | Read | Write |
|---------|------|-------|
| `Dn`, `An` | 0 | 0 |
| `(An)` | 4 | 4 |
| `(An)+` | 4 | 4 |
| `-(An)` | 6 | 6 |
| `(d16,An)` | 8 | 8 |
| `(d8,An,Xn)` | 10 | 10 |
| Memory Indirect | 14 | 14 |
| Absolute | 8 | 8 |

---

## 벡터 검증 실행

### 로컬 테스트

```bash
zig test src/external_vectors.zig
```

### 전체 빌드 테스트

```bash
zig build test
```

---

## 벡터 파일 구성

### 디렉토리 구조

```
external_vectors/
  subset/           # 기능 검증용 (기존)
    bitfield_bfset_reg.json
    exception_trap_return_pc.json
    packed_abcd_reg.json
  timing/           # 타이밍 검증 전용 (신규)
    move_dn_to_dn.json
    move_dn_to_an_indirect.json
    move_an_indirect_to_dn.json
    move_an_postinc_to_predec.json
    move_d16_an_to_d16_an.json
    add_dn_dn.json
    lea_d16_an.json
    jsr_absolute.json
    rts.json
    nop.json
```

### 명명 규칙

- 명령어_소스형식_목적지형식.json
- 예: `move_dn_to_an_indirect.json`
- 간단한 경우: `명령어_모드.json` (예: `nop.json`)

---

## CI 통합 (GitHub Actions)

### 현재 구성

`.github/workflows/ci.yml`:

```yaml
- name: Run tests
  run: zig build test
```

### 확장 계획

```yaml
- name: Run tests
  run: zig build test

- name: Timing regression check
  run: |
    zig test src/external_vectors.zig
    # 실패 시 step_cycles 불일치 상세 리포트 생성
```

---

## 벡터 생성 도구 (향후 계획)

### Python 스크립트

```python
# tools/generate_timing_vector.py
def generate_move_vector(src_ea, dst_ea, data_size):
    opcode = calculate_move_opcode(src_ea, dst_ea, data_size)
    expected_cycles = calculate_move_cycles(src_ea, dst_ea, data_size)
    
    return {
        "name": f"move_{src_ea}_to_{dst_ea}",
        "setup": {...},
        "expect": {"step_cycles": expected_cycles, ...}
    }
```

### 사용 예

```bash
python tools/generate_timing_vector.py --op MOVE --src Dn --dst "(An)" --size Long
```

---

## 회귀 검출 예시

### 변경 전 (baseline)

```
test "move_dn_to_an_indirect"...OK (8 cycles)
```

### 변경 후 (EA 로직 수정)

```
test "move_dn_to_an_indirect"...FAIL
  expected: 8 cycles
  found: 10 cycles
```

### 대응 절차

1. 의도된 변경인가?
   - **Yes**: 벡터 파일의 `step_cycles` 값 갱신 + 커밋 메시지에 명시
   - **No**: 코드 수정하여 사이클 복원

2. 문서 갱신
   - `docs/cycle-model.md` 업데이트
   - 변경 이유 기록

---

## 커버리지 목표

| Phase | 목표 벡터 수 | 현재 상태 |
|-------|--------------|-----------|
| Phase 1 | 50개 | 10개 (20%) |
| Phase 2 | 100개 | - |
| Phase 3 | 200개 | - |

### 우선순위

1. **Phase 1**: 핵심 명령어 (MOVE, ADD, SUB, JMP, JSR, RTS)
2. **Phase 2**: 복잡 EA (ComplexEA, BitField)
3. **Phase 3**: 68020 확장 명령 (CAS, CALLM, bitfield 등)

---

## 참조

- **68020 User's Manual**: MC68020UM/AD Section 9 (Instruction Execution Times)
- **EA 사이클 모듈**: `src/ea_cycles.zig`
- **기존 검증 벡터**: `external_vectors/subset/`
- **사이클 정책**: `docs/cycle-model.md`

---

## 문제 해결

### Q: 벡터 실행 시 사이클이 예상보다 많음

**A**: 파이프라인 모드가 활성화되었는지 확인
```zig
m68k.setPipelineMode(.off); // 기본 사이클만 측정
```

### Q: opcode 값을 어떻게 구하나?

**A**: 68k 어셈블러 사용 또는 수동 계산
```
MOVE.L D0,D1 = 0x2200
ADD.L D1,D0 = 0xD100
```

### Q: 복잡한 명령어는 어떻게 테스트?

**A**: `steps: N`으로 다중 스텝 실행
```json
"setup": { "steps": 3 },
"expect": { "total_cycles": 24 }
```
