# 사이클 프로파일러 (Cycle Profiler)

## 개요
에뮬레이터의 성능 분석과 사이클 정밀도 검증을 위해 명령어 그룹별 실행 횟수 및 소모 사이클을 실시간으로 추적하는 프로파일러를 내장했습니다.

## 주요 기능

### 1. 실시간 통계 수집
- **추적 대상**: 고상위 바이트(Opcode High Byte) 기준 256개 명령어 그룹
- **데이터 항목**: 
  - `instruction_counts`: 실행 횟수
  - `instruction_cycles`: 누적 소모 사이클 (Bus penalty 포함)
  - `total_steps`: 전체 실행 단계
  - `total_cycles`: 전체 소모 사이클

### 2. 성능 리포트 출력
`printProfilerReport()` 함수를 호출하면 표준 에러(stderr)를 통해 다음과 같은 분석 정보를 제공합니다.
- 전체 인스트럭션 수 및 총 사이클
- 평균 인스트럭션당 사이클(Avg Cycles/Inst)
- **Top 10 사이클 점유 명령어 그룹**: 어떤 명령어가 전체 자원의 몇 퍼센트(%)를 쓰고 있는지 내림차순으로 표시

## 사용 방법
```zig
// 프로파일러 활성화
try m68k.enableProfiler();

// 코드 실행...
try m68k.execute(1000);

// 리포트 출력
m68k.printProfilerReport();
```

## 관련 파일
- `src/cpu.zig`: 프로파일러 데이터 구조 및 기록 로직
- `src/test_profiler.zig`: 통계 수집 검증 테스트
