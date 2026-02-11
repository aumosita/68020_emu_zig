# 문서 인덱스

이 디렉터리는 현재 코드베이스 기준의 활성 기술 문서를 모아둔 곳입니다.

## 문서 목록

- `68020-reference.md`
  68020 아키텍처, 예외/인터럽트, 레지스터 동작, 구현 메모

- `instruction-set.md`
  명령어 분류, 디코더/실행기 기준 동작 요약

- `68000_vs_68020.md`
  68000 대비 68020 차이점 요약

- `testing-guide.md`
  테스트 전략, 회귀 테스트 작성 및 실행 가이드

- `MOVEC_GUIDE.md`
  `MOVEC` 및 제어 레지스터 처리 규칙

- `python-examples.md`
  외부 연동 시 API 사용 예시

- `LAYERING_CRITERIA.md`
  파일 계층화/책임 분리 기준

- `cycle-model.md`
  사이클 정책(고정/검증됨 vs 근사)과 회귀 기준

- `coprocessor-handler.md`
  코프로세서 핸들러 계약(handled/unavailable/fault)과 회귀 기준

- `pmmu-ready.md`
  PMMU-ready 최소 호환 레이어(옵션 플래그, 현재 범위, 확장 계획)

- `cache-pipeline-options.md`
  I-cache 통계/penalty 옵션 및 파이프라인 모드 플래그 정책

- `translation-cache.md`
  address_translator 경로용 소프트웨어 TLB 설계/무효화/검증 포인트

- `platform-layer.md`
  CPU 외부 PIC/timer/UART stub 설계와 IRQ 주입 경계 계약

- `benchmark-guide.md`
  3개 대표 워크로드 기반 성능 측정 절차와 기준 수치
