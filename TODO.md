# 68020 에뮬레이터 개발 로드맵
> **목표**: Macintosh LC 하드웨어 완벽 에뮬레이션 및 System 6.0.8 부팅 성공

이 문서는 프로젝트의 현재 진행 상황과 향후 개발 계획을 **실제 가치**와 **우선순위**를 기준으로 정리한 것입니다.

---

## 🎯 현재 상태 (2026-02-14)

### 프로젝트 건강도
- ✅ **테스트**: 265/265 통과 (100%)
- ✅ **빌드**: 29/29 단계 성공
- ✅ **플랫폼**: Linux, Windows, macOS CI 통합
- ✅ **코드 품질**: 구조화된 에러 타입, 문서화 완료

### 주요 성과
- System 6.0.8 부팅을 위한 모든 하드웨어 구현 완료
- CPU 코어 (68020 ISA 완전 구현)
- 주변장치 (VIA, RTC, RBV, Video, SCSI, ADB, SCC, IWM)
- 메모리 관리 (ROM overlay, 24/32-bit 지원)
- 이벤트 스케줄러 및 인터럽트 시스템

---

## 🚀 1. 높은 우선순위 (High Priority)

### 실제 ROM 부팅 및 디버깅
현재 모든 하드웨어가 구현되었으므로, 실제 ROM 부팅 시도 및 디버깅이 최우선입니다.

- [ ] **ROM 부팅 시도 및 로그 분석**
    - Mac LC ROM 파일로 실제 부팅 시도
    - 부팅 실패 지점 식별
    - CPU 명령어 추적 및 MMIO 접근 로그
    - 목표: System 6.0.8 첫 화면 출력

- [ ] **디버깅 도구 개선**
    - 명령어 실행 추적 (trace mode)
    - MMIO 읽기/쓰기 로그
    - 레지스터 상태 덤프
    - 단계별 실행 (step-through debugging)

---

## 🛠 2. 중간 우선순위 (Medium Priority)

### 성능 및 안정성

- [ ] **테스트 커버리지 확대**
    - 통합 테스트: ROM 부팅 시나리오
    - 엣지 케이스: 타이밍 경계 조건
    - 장기 실행 테스트: 메모리 누수 검증

- [ ] **벤치마크 및 프로파일링**
    - 명령어별 실행 시간 측정
    - 병목 지점 식별
    - 최적화 대상 우선순위 결정

### SCSI 모듈 고도화

- [ ] **SCSI 장치 에뮬레이션 및 데이터 전송**
    - [ ] 가상 장치 인터페이스 (`ScsiDevice`) 및 가상 디스크 모듈 구현
    - [ ] SCSI-1 필수 명령어 세트 구현 (`INQUIRY`, `READ`, `WRITE`, `TEST UNIT READY` 등)
    - [ ] 정보 전송 단계(Information Transfer Phase) 상태 머신 완성 및 REQ/ACK 핸드셰이크 구현
    - [ ] Pseudo-DMA 지원 및 블록 전송 최적화
    - [ ] SCSI 트레이스 로깅 기능 추가 (명령어 및 단계 변화 추적)

### 기타 주변기기 고도화

- [ ] **SCC (Serial Communications Controller) 기능 확장**
    - [ ] Zilog 8530 전체 레지스터 상태 머신 구현 (WR/RR 쌍)
    - [ ] 비동기 데이터 전송 및 인터럽트 로직 보강
    - [ ] 호스트 터미널/콘솔 출력을 위한 후크 추가
- [ ] **IWM/SWIM (Floppy Controller) 실체화**
    - [ ] Sony 3.5인치 드라이브 프로토콜 시뮬레이션
    - [ ] 디스크 이미지(.dsk, .img) 로드 및 섹터 읽기/쓰기 로직 구현
    - [ ] GCR 데이터 디코딩 또는 상위 레벨 섹터 액세스 추상화
- [ ] **ADB (Apple Desktop Bus) 입력 통합**
    - [ ] ADB 트랜시버 상태 머신 구현 및 장치 주소 관리
    - [ ] 호스트 OS의 키보드/마우스 이벤트를 ADB 패킷으로 변환 및 주입
    - [ ] 다중 입력 장치 지원 (Keyboard ID 2, Mouse ID 3)
- [ ] **RTC (Real Time Clock) 및 PRAM 지속성**
    - [ ] 실시간 시계 카운터 및 알람 레지스터 연동
    - [ ] 256바이트 PRAM 데이터 구현 및 파일 기반 저장/로드(Persistence) 지원

### 사용성 개선

- [ ] **명령줄 인터페이스 개선**
    - ROM 파일 경로 옵션
    - 디버그 모드 플래그
    - 설정 파일 지원 (JSON/YAML)

- [ ] **실행 예제 추가**
    - ROM 부팅 데모
    - 단순 프로그램 실행 예제
    - 성능 벤치마크 예제

---

## 🔮 3. 낮은 우선순위 (Low Priority / Future)

### 기능 확장
- [ ] **PMMU 완전 구현** (A/UX 지원)
- [ ] **사운드 칩 구현** (Apple Sound Chip)
- [ ] **GDB 리모트 디버깅** (외부 디버거 연동)
- [ ] **JIT 컴파일러** (장기 최적화)

### 코드 리팩토링 (현재 보류)
이 항목들은 현재 코드가 정상 작동하고 유지보수 가능하므로 실제 필요성이 낮습니다.

- [ ] **executor.zig 모듈 분리** (2,075줄)
    - 현황: 단일 switch로 효율적 동작
    - 조건: 새 명령어 추가 시 점진적 리팩토링

- [ ] **cpu_test.zig 분할** (2,925줄, 95개 테스트)
    - 현황: 모든 테스트 통과
    - 조건: 새 테스트는 별도 파일 작성

- [ ] **Arena allocator 도입**
    - 현황: 초기화 시 한 번만 할당
    - 조건: 멀티 인스턴스 또는 JIT 도입 시
    - 분석: `docs/MEMORY_ALLOCATION_ANALYSIS.md`

---

## ✅ 4. 완료된 항목 (Completed)

### 2026-02-14 완료
- [x] **에러 처리 통합**
  - 구조화된 에러 타입 (`src/core/errors.zig`)
  - `anyerror` 완전 제거 (3곳 → 0곳)
  - C API 에러 매핑 및 문서화
  - 테스트: 265/265 통과

- [x] **Quick Wins**
  - `.editorconfig`, `CONTRIBUTING.md`, `LICENSE` (MIT)
  - `docs/architecture.md`, `examples/README.md`
  - GitHub Actions: Linux + Windows + macOS

### 핵심 하드웨어
- [x] **CPU Core** (MC68020 ISA 완전 구현)
- [x] **주변장치**
  - VIA 6522 (타이머, 인터럽트)
  - RTC (시계, PRAM)
  - RBV (VIA2, VBL)
  - Video (VRAM, 8-bit CLUT)
  - SCSI (NCR 5380, 상태 머신)
  - ADB (키보드/마우스)
  - SCC (Zilog 8530 스텁)
  - IWM (플로피 스텁)

### 시스템 아키텍처
- [x] **메모리 맵** (ROM overlay, 24/32-bit)
- [x] **이벤트 스케줄러** (우선순위 큐)
- [x] **인터럽트 시스템** (중첩, 우선순위)
- [x] **버스 사이클 모델** (Wait states)
- [x] **소프트웨어 TLB** (주소 변환 캐시)

### 품질 보증
- [x] **테스트 환경** (`tests/integration/`)
- [x] **CI/CD** (Linux/Windows/macOS)
- [x] **문서화** (15+ 문서)
- [x] **코드 스타일** (EditorConfig, 컨벤션)

---

## 📊 다음 단계

**즉시 실행 가능:**
1. Mac LC ROM 파일 확보 및 부팅 시도
2. 디버그 로그 활성화하여 실패 지점 분석
3. 부팅 과정 문서화

**중기 목표:**
- System 6.0.8 부팅 성공
- 기본 GUI 렌더링
- 키보드/마우스 입력

**장기 비전:**
- 실제 Mac LC 소프트웨어 실행
- System 7 지원
- A/UX 지원 (PMMU 필요)
