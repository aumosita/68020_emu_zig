# 68020 에뮬레이터 개발 로드맵
> **목표**: Macintosh LC 하드웨어 완벽 에뮬레이션 및 System 6.0.8 부팅 성공

이 문서는 프로젝트의 현재 진행 상황과 향후 개발 계획을 "중요도"와 "개발 순서"를 기준으로 정리한 것입니다.

---

## 🚀 1. 높은 우선순위 (High Priority)
**시스템 안정화 및 핵심 아키텍처 완성**을 위한 필수 과제입니다.

### 아키텍처 및 스케줄러 통합
- [ ] **이벤트 스케줄러 통합 확대**
    - 현재 `VIA6522`와 `MacLcSystem`에 적용된 중앙 스케줄러를 `RBV` 및 `Video` 하위 시스템까지 확대 적용.
    - 정밀한 비디오 타이밍(VBL/HBL) 동기화 구현.
- [ ] **인터럽트 처리 검증 강화**
    - VIA/RBV 인터럽트가 CPU Core로 정확하게 전파되는지 검증하는 시나리오 테스트 보강.
    - 중첩 인터럽트(Nested Interrupts) 및 우선순위 처리 로직의 Edge Case 검증.

### 주변 장치 프로토콜 고도화
- [ ] **SCSI (NCR 5380) 정밀화**
    - 단순 레지스터 구현을 넘어, 실제 OS 드라이버가 요구하는 SCSI Phase(Selection, Command, Data, Status, Message) 전환 로직 구현.
- [ ] **ADB (Apple Desktop Bus) 통신 구현**
    - 키보드/마우스 입력 패킷 처리를 위한 비트 타이밍 및 상태 머신(State Machine) 구현.

### 메모리 및 시스템 맵
- [ ] **Mac LC 메모리 맵 최종 구성**
    - ROM (0x400000 등) 로딩 및 미러링 로직 검증.
    - RAM 동적 크기 할당 및 VRAM과의 주소 공간 매핑 확인.
- [ ] **ROM 부팅 시도 및 Trap 핸들링**
    - 실제 ROM 이미지를 로드하여 초기화 코드 실행 시도.
    - `A-Line` (Toolbox) 및 `F-Line` Trap 예외 처리의 정확성 검증.

---

## 🛠 2. 중간 우선순위 (Medium Priority)
**에뮬레이션 정확도(Accuracy)**를 높이기 위한 기술적 심화 과제입니다.

### CPU 및 버스 정확도
- [ ] **버스 사이클(Bus Cycle) 정밀 모델링**
    - 파이프라인(Fetch/Decode/Execute) 단계별 소요 사이클 정밀화.
    - 외부 느린 장치(ROM 등) 접근 시 Wait State 반영.
- [ ] **EA (Effective Address) 계산 비용 현실화**
    - 68020 매뉴얼 기반의 Addressing Mode별 사이클 테이블 적용 및 회귀 테스트 추가.

### 성능 및 안정성
- [ ] **메모리 할당 최적화**
    - Arena Allocator 도입을 통한 메모리 할당/해제 오버헤드 감소.
- [ ] **테스트 자동화 및 리포팅**
    - `zig build test-all` 통합 러너 구축 및 결과 리포트(JSON/HTML) 생성.

---

## 🔮 3. 낮은 우선순위 (Low Priority / Future)
**기능 확장** 및 **장기적 최적화** 목표입니다.

- [ ] **PMMU (MMU) 완전 구현**
    - 현재의 호환 레이어를 넘어, 실제 페이지 테이블 워크(Page Table Walk) 및 보호 도메인 구현 (A/UX 구동 목표).
- [ ] **사운드 (Apple Sound Chip) 구현**
    - DMA 기반 오디오 버퍼링 및 샘플링 속도 동기화.
- [ ] **디버깅 도구 강화**
    - GDB Remote Protocol 스텁(Stub) 구현으로 외부 디버거 연동 지원.
    - 실행 추적(Execution Trace) 로그의 포맷화 및 시각화 도구 지원.
- [ ] **코어 최적화 (JIT)**
    - 장기적으로 인터프리터 방식에서 JIT(Just-In-Time) 컴파일러 도입 검토.

---

## ✅ 4. 완료된 항목 (Completed)
이미 구현 및 검증이 완료된 주요 기능입니다.

### 하드웨어 (Foundation)
- [x] **CPU Core**: MC68020 명령어 셋(ISA), 예외 처리, 어드레싱 모드 기본 구현.
- [x] **VIA 6522**: 타이머(T1/T2), 인터럽트 플래그, 기본 레지스터 로직.
- [x] **RBV (Video/Interrupt)**: 기본 인터럽트 라우팅 및 레지스터 설계.
- [x] **Video**: VRAM (512KB) 매핑, 8비트 CLUT(Color Lookup Table) 지원.
- [x] **RTC**: 초 단위 시계 및 PRAM I/O.

### 아키텍처 (Architecture)
- [x] **모듈화**: `cpu.zig`, `via6522.zig` 등 핵심 컴포넌트의 모듈 분리 및 의존성 정리.
- [x] **이벤트 스케줄러 (Event Scheduler)**: `Scheduler` 구조체 및 우선순위 큐(Priority Queue) 기반의 시간 관리 시스템 도입.
- [x] **소프트웨어 TLB**: 메모리 접근 속도 향상을 위한 주소 변환 캐싱 구현.

### 검증 (Verification)
- [x] **통합 테스트 환경**: `tests/integration/` 구조 정립 및 CI 연동.
- [x] **주요 버그 수정**: 비트필드(Bitfield) 명령어, 확장 워드 디코딩, PC 반환 값 등 핵심 로직 수정.
