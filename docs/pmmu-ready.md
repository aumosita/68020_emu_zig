# PMMU-Ready 최소 호환 레이어

## 목표

- 실제 페이지 워크 구현 없이도, PMMU(68851) 존재를 전제로 한 소프트웨어가 초기 probe 단계에서 즉시 실패하지 않도록 최소 동작을 제공한다.
- 기능 정확도(명령 의미론)와 호환성(존재 감지)을 분리한다.

## 옵션 플래그

- CPU API:
  - `setPmmuCompatEnabled(enabled: bool)`
- C API:
  - `m68k_set_pmmu_compat(m68k, enabled)`

기본값은 `false`이며, 비활성 상태에서는 기존과 동일하게 F-line opcode가 `vector 11`(Line-1111 emulator) 예외로 진입한다.

## 현재 최소 동작(2026-02-11)

- `enabled = true`일 때, F-line opcode 중 coprocessor ID가 `0`인 경우를 PMMU opcode로 간주한다.
  - 인식 기준: opcode bits `[11:9] == 0`
- 인식된 PMMU opcode는 다음으로 처리한다.
  - `PC += 4` (opcode + extension word 1개 소비)
  - `MMUSR` 최소 상태(`0`) 유지
  - 고정 cycle `20` 반환
- coprocessor ID가 `0`이 아닌 F-line opcode는 기존 경로를 유지한다.
  - 코프로세서 핸들러가 없으면 `vector 11`
  - 코프로세서 핸들러가 있으면 핸들러 우선

## 비목표(현재 범위 밖)

- PMMU 명령의 완전한 디코딩/의미론 실행
- 루트 포인터(`CRP/SRP`), `TC`, 페이지 테이블 워크, ATC/TLB 모델
- PMOVE/PTEST/PFLUSH의 실칩 수준 부작용

## 확장 계획

- 단계 1: PMMU 주요 레지스터 구조체와 명령별 길이 해석기 추가
- 단계 2: 논리 주소 변환 훅(`AddressTranslator`)과 PMMU 상태 레지스터 연동
- 단계 3: 제한된 페이지 워크(읽기 전용/identity-map 우선)와 fault frame 세분화
