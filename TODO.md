# TODO

## 현재 상태(2026-02-11 기준)

- 예외/트랩 핵심 보강 완료:
  - `BKPT` 디버거 훅 + 미연결 시 `vector 4` 폴백
  - `Address Error(vector 3)`와 `Bus Error(vector 2)` 분리
  - `RTE` 특권 검사(`vector 8`) 반영
  - `Format A/B` 포함 `RTE` 프레임 복귀 회귀 추가
  - 중첩 `TRAP` 예외 복귀 회귀 추가
- 코프로세서 미구현 환경 대응 완료:
  - F-line을 사용자 핸들러로 위임 가능한 coprocessor dispatch 경로 반영
- 경량 캐시/버스 추상화 완료:
  - `CACR` 기반 I-cache enable/invalidate 가시 효과
  - bus hook / address translator 연동 포인트 반영

## 높은 우선순위

- 스택 포인터 모델 세부 규칙 완성
  - `S/M` 비트 전환 시 `USP/ISP/MSP` 저장/복원 규칙을 케이스별 표로 정리
  - `MOVE USP`, `MOVEC USP/ISP/MSP` 혼합 사용 시 일관성 회귀 테스트 추가
  - 인터럽트 진입/중첩 인터럽트/`RTE` 복귀에서 active stack 전환 검증 강화
  - 완료 기준: supervisor/user, interrupt/master 전환 조합 테스트 통과

- 예외 프레임 정확도 2차 보강
  - 현재 Format A/B 생성 경로에서 누락된 상태 워드/내부 정보 필드 점검
  - `Address Error` 프레임의 `fault address`, `IR`, `access type` 기록 정책 결정
  - 디코더 확장 워드 fetch 실패 시 faulting address 보존 규칙 통일
  - 완료 기준: vector 2/3 프레임 필드 검증 테스트 추가 후 통과

- `root.zig` 외부 API 검증 확대
  - `m68k_set_irq`, `m68k_set_irq_vector`, `m68k_set_spurious_irq` 경로를 C API 기준으로 통합 테스트
  - STOP 상태에서 인터럽트 재개 시 cycle/PC/SR 기대값 검증
  - 완료 기준: root API 테스트에서 IRQ 관련 시나리오 전부 자동 검증

- 불법 인코딩/확장 워드 예외 커버리지 확장
  - `CALLM/RTM`, bitfield, `MOVEC`, coprocessor/line-A/F의 경계 인코딩 추가
  - 디코더에서 거부해야 할 모드와 실행기에서 거부해야 할 케이스 분리
  - 완료 기준: 예외 벡터(4,10,11)와 return PC 일관성 테스트 통과

## 중간 우선순위

- 사이클 모델 정리(기능 정확도 유지, 선택적 정밀화)
  - 현재 고정 사이클 반환 명령 목록을 추출해 문서화
  - 주소 지정 모드 영향이 큰 명령(`MOVEM`, 분기/예외, bitfield)만 우선 정밀화
  - `README.md`에 "근사/검증됨" 표기 규칙 추가
  - 완료 기준: 사이클 근사 정책 문서 + 핵심 명령 cycle 회귀 테스트

- `MOVEM` 비용 모델 세분화
  - 레지스터 개수, 방향(mem->reg/reg->mem), predecrement/postincrement 별 비용 반영
  - word/long 전송 폭 차등 반영
  - 완료 기준: 최소 6개 모드 조합 cycle 테스트 통과

- 코프로세서 호환 레이어 정리
  - coprocessor handler 계약(입력 opcode/PC, 반환 semantics)을 문서화
  - 핸들러 부재/거부/fault 반환의 표준 동작을 고정
  - 완료 기준: 문서 + 샘플 핸들러 테스트 케이스 유지

- 버스 추상화 고도화
  - FC 기반 접근 정책(사용자/슈퍼바이저 + 프로그램/데이터) 테스트 강화
  - `retry/halt/bus_error` 시 재시도/정지/예외 진입 규칙 명확화
  - 완료 기준: bus hook 시나리오별 step 동작 회귀 테스트

## 낮은 우선순위

- PMMU-ready 확장 준비
  - PMMU 명령 감지/상태 레지스터 최소 모델 초안
  - 실제 페이지 워크 없이도 OS가 "MMU 존재"를 인식할 수 있는 호환 레이어 검토
  - 완료 기준: 옵션 플래그 기반 최소 동작 명세서 작성

- 캐시/파이프라인 옵션 고도화(비기본)
  - 현재 I-cache 경량 모델의 통계(hit/miss 카운터) 노출
  - 필요 시 fetch penalty를 옵션 값으로 조정 가능하게 확장
  - 완료 기준: 기능 플래그 + 문서화

- 벤치마크/품질 측정
  - 대표 워크로드 3개 기준 회귀 성능 측정 스크립트 준비
  - CPI/MIPS는 참고 지표로만 보고, 기능 회귀를 우선 게이트로 유지
  - 완료 기준: 재현 가능한 벤치 실행 절차 문서화
