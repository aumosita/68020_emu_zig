# 68020 구현 참고

## CPU 상태

- 데이터 레지스터: `D0-D7`
- 주소 레지스터: `A0-A7`
- 프로그램 카운터: `PC`
- 상태 레지스터: `SR`
- 제어 레지스터: `VBR`, `CACR`, `CAAR`, `SFC`, `DFC`
- 스택 포인터 뱅킹: `USP`, `ISP`, `MSP`

## 예외/인터럽트

- 예외 벡터는 `VBR + vector*4`로 계산
- `enterException()`에서 스택 프레임을 쌓고 핸들러로 분기
- IRQ 레벨/벡터 오버라이드/스퓨리어스 지원
- STOP 상태에서 IRQ로 복귀 가능
- 명령어 fetch 버스 에러는 vector 2 진입 시 Format A(24바이트) 프레임으로 모델링

## 디코더/실행기 구조

- `decoder.zig`: opcode -> `Instruction` 변환, EA 확장 해석
- `executor.zig`: 명령 의미론, 플래그 갱신, 예외 진입
- `cpu.zig`: step 루프, 디코드/실행 에러의 예외 라우팅
- `memory.zig`: 버스 훅/주소 변환기(가상 메모리 연동 지점)와 기본 메모리 백엔드

## 캐시/버스 모델(경량)

- I-cache: 명령 fetch 경로에서만 direct-mapped 경량 모델 적용
  - 미스 시 가중치 사이클(+2), 히트 시 추가 비용 없음
  - `CACR` 비트 기반 enable/무효화 반영
- 버스 추상화:
  - `BusHook`: `ok/retry/halt/bus_error` 신호 반환
  - `AddressTranslator`: 논리 주소 -> 물리 주소 변환 훅(PMMU 연동 지점)

## 정확도 포인트

- 확장 EA를 사용하는 명령은 `i.size` 기반 PC 증가 필요
- privilege 명령(`MOVEC`, `STOP`, `RESET`, SR 직접 수정 계열) 검증 필수
- `MOVEM`, `TAS`, shift/rotate의 메모리 대상 동작은 회귀 테스트 유지 권장
