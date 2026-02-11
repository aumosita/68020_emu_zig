# Phase 2 확장 진행 중

## 완료
- RTR, RTE, TRAP (Phase 2 필수)
- TAS - 디코딩 및 실행 완료, 테스트 통과 ✅
- CHK - 디코딩 및 실행 완료, 테스트 통과 ✅

## 진행중
- EXG - 디코딩 완료, 실행 실패 (레지스터 교환 로직 문제)
- CMPM - 디코딩 수정 필요, 실행 실패

## 문제
- EXG: opcode에서 레지스터를 추출하지만 값이 잘못됨
- CMPM: 플래그 설정 문제

## 다음
1. EXG executor 수정
2. CMPM executor 수정
3. BCD 연산 4개 (stub만)

**테스트**: 25/27 통과
