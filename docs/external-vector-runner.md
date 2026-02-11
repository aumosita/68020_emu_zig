# 외부 검증 벡터 러너

## 목적

- 외부 68k validation vector(JSON)를 파일 기반으로 로드해 회귀 테스트에 반영한다.
- 코어 내장 unit test와 별도로, 데이터 중심 검증 벡터를 점진적으로 확대할 수 있게 한다.

## 현재 구현

- 러너: `src/external_vectors.zig`
- 기본 subset 경로: `external_vectors/subset/*.json`
- 현재 포함된 희소 인코딩 중심 벡터:
  - bitfield: `bitfield_bfset_reg.json`
  - packed decimal: `packed_abcd_reg.json`
  - exception return PC: `exception_trap_return_pc.json`

## 실행 방법

- 단독 실행:

```bash
zig test src/external_vectors.zig
```

- 통합 실행:

```bash
zig build test
```

`build.zig`의 `test` step에 external vector test가 포함되어 있다.

## CI

- GitHub Actions: `.github/workflows/ci.yml`
- `zig build test`를 실행하며, external subset도 자동 검증된다.

## JSON 스키마(요약)

- `setup`:
  - `pc`, `sr`, `steps`
  - `d[8]`, `a[8]`
  - `memory8[]`, `memory16[]`, `memory32[]`
- `expect`:
  - `pc`, `sr`, `step_cycles`, `total_cycles`
  - `d[]`, `a[]` (인덱스 기반 기대값)
  - `memory8[]`, `memory16[]`, `memory32[]`
