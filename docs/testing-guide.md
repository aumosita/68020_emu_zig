# 테스트 가이드

## 기본 실행

```bash
zig build test
zig test src/root.zig
zig test src/cpu.zig
```

## 회귀 테스트 원칙

- 버그 수정 시 반드시 재현 테스트를 먼저 추가
- 예외/인터럽트는 다음을 함께 검증
  - 진입 벡터 번호
  - 스택 프레임(SR/PC/format-vector)
  - 복귀 후 PC/SP/플래그
- 확장 EA를 쓰는 명령은 `PC += i.size`가 맞는지 검증

## 최근 중요 회귀 영역

- `CALLM/RTM` 프레임 왕복
- `MOVEC` 특권 위반
- `BKPT` 벡터 동작
- `TAS` 레지스터/메모리 대상
- `MOVEM` 주소 지정 및 순서
- 메모리 shift/rotate의 확장 EA PC 증가

## 테스트 작성 팁

- opcode/확장 워드를 테스트 코드에서 명시해 디코드 경로를 고정
- 성공 경로와 실패(예외) 경로를 분리
- 레지스터 값뿐 아니라 메모리 부작용까지 확인
