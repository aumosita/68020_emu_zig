# 버스 에러 및 재시도 메커니즘 (Bus Error & Retry)

## 개요
68020 칩은 버스 사이클 도중 외부 장치로부터 `BERR*` 신호를 받을 수 있습니다. 이때 CPU는 즉시 버스 에러 예외 처리를 하거나, `HALT*` 신호와 함께 입력될 경우 해당 사이클을 재시도(Retry)합니다. 본 에뮬레이터는 이러한 하드웨어 동작을 소프트웨어적으로 정밀하게 재현합니다.

## 구현 상세

### 1. 자동 재시도 (Automatic Retry)
- **메커니즘**: `memory.BusSignal.retry` 신호가 수신되면 CPU는 현재 명령을 중단하고 즉시 동일한 버스 사이클을 다시 시작합니다.
- **횟수 제한**: 무한 루프 방지를 위해 `bus_retry_limit` 필드를 통해 최대 재시도 횟수를 제한합니다. (기본값: 3회)
- **API**:
  - `setBusRetryLimit(limit: u8)`: 재시도 한도 설정
  - `getBusRetryCount()`: 현재 발생한 연속 재시도 횟수 확인

### 2. 버스 에러 예외 (Bus Error Exception)
- 재시도 한도를 초과하거나 `memory.BusSignal.bus_error` 신호를 직접 수신하면 발생합니다.
- **예외 프레임**: 68020 고유의 **Format $A (Short Bus Fault)** 스택 프레임을 생성합니다.
- **추가 정보 기록**: 디버깅을 위해 스택 프레임 내의 'Internal Register' 영역(SP+16)에 실제 발생했던 재시도 횟수를 기록합니다.

## 관련 파일
- `src/cpu.zig`: 재시도 카운터 및 예외 프레임 생성 로직
- `src/memory.zig`: 버스 신호 정의 및 전송
- `src/test_bus_retry.zig`: 기능 검증 테스트
