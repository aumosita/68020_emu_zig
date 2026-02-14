# 타이밍, 버스, 캐시

## 사이클 모델

기능 정확도 중심. 사이클 값은 **근사 모델**이며, 기본 EA 사이클은 `ea_cycles.zig`에서 계산.

- 기본 명령어: M68020 매뉴얼 기준 정확
- 예외 프레임, CALLM/RTM, 복합 EA: 근사
- 명령어별 사이클은 테스트에서 assert로 잠금

## 버스 사이클 상태 머신

`src/core/bus_cycle.zig` — S0→S1→S2→SW→S3 5단계 모델.

- **Wait State**: 주변장치별 지연 주입 가능 (ROM, UART 등)
- **동적 버스 크기**: 8/16/32비트 포트 폭 설정 가능
- **Split 사이클 페널티**: 좁은 포트에서 워드/롱 접근 시 추가 사이클

## 버스 에러 및 재시도

`BERR*` 신호 → BusError 예외 (Format A 프레임)  
`BERR* + HALT*` → 현재 사이클 재시도 (retry count 추적)

## 인스트럭션 캐시

실제 68020 사양 기반: 256바이트, 2-way set associative.

- **캐시 on/off**: CACR bit 0
- **무효화**: CACR bit 3 (clear request)
- **Miss 페널티**: 설정 가능 (기본 2사이클)
- **Longword 정렬**: 상위/하위 워드 동시 캐시

## 소프트웨어 TLB

`memory.zig`의 8-entry direct-mapped TLB로 `address_translator` 콜백 오버헤드 절감.

## ALU 시뮬레이션

기능적 에뮬레이션 (Functional Emulation) 방식. 게이트 레벨이 아닌 결과 기반 연산.  
BCD, 비트 필드, MUL/DIV는 Zig 내장 연산자로 구현.

## 타이밍 회귀 테스트

`tests/timing/` 디렉토리에서 명령어별 사이클 변화 추적. `zig build test`로 자동 검증.

## 사이클 프로파일러

명령어 그룹별 실행 횟수/소모 사이클을 실시간 추적.  
API: `m68k.getCycleProfile()`, `m68k.resetCycleProfile()`
