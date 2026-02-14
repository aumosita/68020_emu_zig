# 68020 에뮬레이터 개발 로드맵
> **목표**: Macintosh LC ROM 부팅 → System 6.0.8 첫 화면

---

## 🎯 현재 상태 (2026-02-14)

- ✅ **CPU 코어**: 97/105 명령어 구현 (PMMU 8개 제외 시 100%)
- ✅ **테스트**: 216개 통과, 29 빌드 단계 성공
- ✅ **ROM 부팅**: 200+ 명령어 실행 후 예외 루프 진입
- ✅ **코드 정리**: 문서 33→6개, 깨진 테스트 15개 삭제 (-4,988줄)

---

## 📊 주변장치 구현 수준

| 주변장치 | 줄 | 점수 | ROM 영향 | 현황 |
|----------|-----|------|----------|------|
| VIA 6522 | 548 | ⭐⭐⭐⭐ | 🔴 Critical | 타이머+IRQ 동작, SR/핸드셰이크 미구현 |
| ADB | 409 | ⭐⭐⭐⭐ | 🟡 Medium | 프로토콜 완전, VIA 핀 직접 연동 부족 |
| SCSI 5380 | 543 | ⭐⭐⭐ | 🔴 Critical | 셀렉션까지, READ/WRITE 미구현 |
| RBV | 100 | ⭐⭐⭐ | 🔴 Critical | VBL IRQ 동작, 슬롯 라우팅 없음 |
| RTC | 135 | ⭐⭐⭐ | 🟡 Medium | 읽기만, 쓰기/초 카운터 미구현 |
| SCC | 165 | ⭐⭐ | 🟡 Medium | 폴링 통과 스텁, Rx 없음 |
| Video | 63 | ⭐⭐ | 🟢 Low | 팔레트만, 렌더링 없음 |
| IWM | 65 | ⭐ | 🟢 Low | 순수 스텁 (Mac LC에서 충분) |

---

## 🚀 1. 높은 우선순위 — ROM 부팅 진행

### 예외 루프 디버깅
- [ ] Step 19 이후 예외 루프 원인 분석 (PC=0x067C4F4E)
- [ ] 예외 벡터 테이블 정확성 검증
- [ ] MMIO 접근 로그로 하드웨어 기대값 파악

### VIA 타이머 정확도 (ROM 부팅 병목 #1)
- [ ] Timer 1 one-shot 모드 엣지 케이스
- [ ] Shift Register 실동작 (ROM이 사용하는 경우)
- [ ] PCR 기반 외부 핀 에지 감지

### RBV/VBL 타이밍 (ROM 부팅 병목 #2)
- [ ] VBL 인터럽트가 CPU IRQ로 정확히 전달되는지 검증
- [ ] 슬롯 인터럽트 라우팅 (Slot E/F)

### SCSI READ 커맨드 (디스크 부팅 필수)
- [ ] READ(6)/WRITE(6)/TEST UNIT READY 구현
- [ ] ScsiDisk에 디스크 이미지 I/O 추가
- [ ] REQ/ACK 핸드셰이크 및 DMA 전송

---

## 🛠 2. 중간 우선순위

### RTC 완성
- [ ] PRAM 쓰기 구현 (`writeData` 빈 함수)
- [ ] 초 카운터 자동 증가 (스케줄러 연동)
- [ ] PRAM 파일 저장/로드

### SCC 기능 확장
- [ ] Rx 수신 버퍼 구현
- [ ] 인터럽트 벡터링 (RR2)
- [ ] BRG 보드레이트 생성기

### 디버깅 도구
- [ ] 단계별 실행 CLI (step/continue/breakpoint)
- [ ] MMIO 워치포인트
- [ ] 레지스터 상태 가독성 개선

### 테스트 확대
- [ ] ROM 부팅 시나리오 통합 테스트
- [ ] VIA 타이머 엣지 케이스 테스트
- [ ] SCSI 명령어 시퀀스 테스트

---

## 🔮 3. 낮은 우선순위

- [ ] Video 렌더링 파이프라인 (프레임 출력)
- [ ] IWM/SWIM 플로피 실구현 (GCR 디코딩)
- [ ] PMMU 완전 구현 (A/UX 지원)
- [ ] ASC (Apple Sound Chip)
- [ ] GDB 리모트 디버깅
- [ ] executor.zig 모듈 분리 (2,075줄)
- [ ] cpu_test.zig 분할 (2,925줄)

---

## ✅ 완료

### 2026-02-14
- [x] ROM 부팅 디코더 수정 (LEA, MOVE EA 순서, CHK2 가드)
- [x] 예외 처리 wrapping 산술
- [x] 24-bit 주소 마스킹 + ROM overlay 분리
- [x] 문서 통합 (33→6개, -4,763줄)
- [x] 깨진 테스트 삭제 (-2,225줄)
- [x] test_decode.zig 삭제

### 이전 완료
- [x] CPU Core (MC68020 ISA 97/105)
- [x] 구조화된 에러 타입 (anyerror 제거)
- [x] Flat memory → Bus-path 마이그레이션
- [x] 메모리 맵 (ROM overlay, 24/32-bit)
- [x] 이벤트 스케줄러, 인터럽트 시스템
- [x] 버스 사이클 모델, 소프트웨어 TLB
- [x] CI/CD (Linux/Windows/macOS)
- [x] 실행 예제 (fibonacci, bitfield, exception)
