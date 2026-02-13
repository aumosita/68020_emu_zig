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
- 스택 포인터 모델 1차 검증 완료:
  - `S/M` 전환 매트릭스 회귀 테스트 추가
  - `MOVE USP` 구현 + 특권 위반(`vector 8`) 회귀 추가
  - `MOVEC USP/ISP/MSP` raw register 동작(A7 비자동 동기화) 회귀 추가
  - User/ISP/MSP 전환 + 중첩 IRQ + RTE 복귀 조합 회귀 추가
  - `docs/stack-pointer-model.md` 체크리스트 검증 완료로 갱신
- 예외 프레임 정확도 2차 보강 완료:
  - vector 2/3를 Format A 프레임 정책으로 통일
  - `fault address`, `access word`, `IR` 필드 기록 강화
  - 디코더 확장 워드 fetch 실패 시 precise fault address 보존 회귀 추가
- `root.zig` 외부 API 검증 확대 완료:
  - `m68k_set_irq`, `m68k_set_irq_vector`, `m68k_set_spurious_irq` C API 통합 테스트 추가
  - STOP 상태 인터럽트 재개 시 `cycle/PC/SR` 검증 추가
  - `zig test src/root.zig` 기준 IRQ/STOP 관련 회귀 자동 검증
- C API 에러 가시성/안전성 1차 보강 완료:
  - status-code 기반 메모리 API(`*_memory_*_status`) 추가
  - out-parameter 기반 read API로 실패 원인 식별 가능 경로 제공
  - 전역 `gpa` 접근에 mutex 적용(create/destroy 경합 완화)
  - context 기반 생성/파괴 API(`m68k_context_*`, `m68k_create_in_context`, `m68k_destroy_in_context`) 추가
  - context allocator callback 주입 API(`m68k_context_set_allocator_callbacks`) 추가
  - root API에서 out-of-range/alignment/null-pointer 실패 경로 회귀 추가
- 불법 인코딩/확장 워드 예외 커버리지 확장 완료:
  - `CALLM/RTM`, `TRAPcc`, line-A/F, `MOVEC` 경계 인코딩 회귀 강화
  - `MOVEC` invalid control register 인코딩의 vector 4 라우팅 검증 추가
  - line-A/F 경계 opcode(`AFFF`, `FFFF`)의 vector/return PC 일관성 검증 추가

## 높은 우선순위

- 스택 포인터 모델 세부 규칙 완성 ✅(완료)

- 예외 프레임 정확도 2차 보강 ✅(완료)

- `root.zig` 외부 API 검증 확대 ✅(완료)

- C API 에러 가시성/안전성 강화 ✅(완료)
  - ✅ status code + out-parameter 기반 메모리 접근 API 추가(`*_status`)
  - ✅ 버스/정렬/인자 오류를 반환 코드로 노출하는 회귀 테스트 추가
  - ✅ 전역 `gpa` create/destroy 경로 mutex 보호
  - ✅ context 주입 생성/파괴 API 추가(allocator 도메인 분리)
  - ✅ 구 API(`m68k_read/write_memory_*`) deprecate/권장 경로 README 문서화
  - ✅ 외부 allocator callback 주입 API 추가

- 불법 인코딩/확장 워드 예외 커버리지 확장 ✅(완료)

- 소프트웨어 TLB(주소 변환 캐시) 도입 ✅(완료)
  - ✅ `address_translator` 경로에 8-entry direct-mapped TLB fast-path 추가
  - ✅ key(page + FC + space + R/W), value(physical page base) 캐싱 반영
  - ✅ flush/invalidate API 제공(`Memory.invalidateTranslationCache`, `m68k_invalidate_translation_cache`)
  - ✅ translator 콜백 호출 감소/flush 일관성 회귀 테스트 추가
  - ✅ 설계/무효화 정책 + 벤치 비교 수치 문서화(`docs/translation-cache.md`)

## 중간 우선순위

- 사이클 모델 정리(기능 정확도 유지, 선택적 정밀화) ✅(완료)
  - ✅ 현재 고정 사이클 반환 경로 문서화(`docs/cycle-model.md`)
  - ✅ `README.md`에 "근사/검증됨" 표기 규칙 반영
  - 진행: `MOVEM` 비용 모델/회귀 반영 완료, 분기/bitfield 사이즈·오퍼랜드별 사이클 정밀화 반영 완료
  - 진행: 분기(`BRA/Bcc`) 변위 크기별 taken/not-taken 비용 반영 + 회귀 테스트 추가
  - 진행: bitfield 명령의 reg/mem 오퍼랜드별 비용 반영 + 회귀 테스트 추가
  - 진행: 예외/트랩 경로(Illegal/LineA/LineF/BKPT/AddressError/Privilege) cycle assertion 회귀 확장
  - 진행: fault subtype(`instruction fetch=50`, `decode ext fetch=52`, `execute data access=54`) 세분화 + 회귀 반영
  - 진행: `TRAP/TRAPV/RESET(supervisor)/TRAPcc/RTE/illegal decode` 고정 cycle assertion 회귀 추가
  - 진행: `ABCD/SBCD/NBCD/MOVEP/CAS2/CMPM/SHIFT/MOVEA/STOP/ORI-ANDI-EORI` cycle assertion 회귀 추가
  - 진행: `CHK2/CMP2/CALLM-RTM/TAS/MUL*_L/DIV*_L` cycle assertion 회귀 추가
  - 진행: `PACK/UNPK/MOVEC/ComplexEA/extended-EA/memory shift` cycle assertion 회귀 추가
  - ✅ 핵심 명령 cycle 회귀 테스트 범위 확장 완료

- `MOVEM` 비용 모델 세분화 ✅(완료)
  - 레지스터 개수, 방향(mem->reg/reg->mem), predecrement/postincrement 별 비용 반영
  - word/long 전송 폭 차등 반영
  - 6개 모드 조합 cycle 테스트 통과

- 코프로세서 호환 레이어 정리 ✅(완료)
  - ✅ coprocessor handler 계약(입력 opcode/PC, 반환 semantics) 문서화(`docs/coprocessor-handler.md`)
  - ✅ 핸들러 부재/거부/fault 반환의 표준 동작 고정 + 회귀 테스트 반영

- 버스 추상화 고도화 ✅(완료)
  - ✅ FC 기반 접근 정책(사용자/슈퍼바이저 + 프로그램/데이터) CPU fetch/data 경로 회귀 테스트 강화
  - ✅ `retry/halt/bus_error` 시 CPU step의 재시도/정지/예외 진입 규칙 회귀 테스트 추가
  - ✅ data access 경로를 bus hook/translator 경로와 통합(`read/write*Bus`)하고 회귀 검증 반영

- Dynamic Bus Sizing(8/16/32-bit 포트) 모델 도입 ✅(완료)
  - ✅ 메모리 영역별 port width 속성 정의
  - ✅ 32-bit 접근의 분할 버스 사이클(예: 8-bit 포트에서 4회 접근) 모델링
  - ✅ 포트 폭별 read/write 분할 회귀 테스트 추가(`src/memory.zig`)
  - ✅ 기능 정확도와 독립적인 cycle 비용 계산 경로 분리(`memory.takeSplitCyclePenalty` + `cpu.step` opt-in 연동)
  - ✅ cycle 기대값 테스트 추가(포트 폭 분할 fetch/data 경로)

- I-Cache 구조 고증 정합성 보강(68020 256B) ✅(완료)
  - ✅ line 데이터 폭을 longword 중심으로 재정의(64 entries x 4 bytes)
  - ✅ fetch/fill 로직을 32-bit 정렬 기반으로 조정
  - ✅ 기존 경량 모델과 호환되는 옵션/마이그레이션 정책 유지
  - ✅ cache hit/miss/invalidate 회귀 + 용량/정렬 정책 문서화

- 파이프라인 스톨 모델 정밀화(옵션 기반) ✅(완료)
  - ✅ `PipelineMode.approx`: taken branch flush penalty(`+2`) + memory-dst overlap 보정(`-1`) 반영
  - ✅ `PipelineMode.detailed`: 초기 골격(`+4`/`-2`) 반영(세부 상태머신은 후속 단계)
  - ✅ 기능 정확도 경로(`off`)와 분리된 cycle 모델 유지
  - ✅ 모드별 cycle 회귀 테스트 + 정책 문서(`docs/cycle-model.md`) 업데이트

## 낮은 우선순위

- PMMU-ready 확장 준비 ✅(완료)
  - ✅ PMMU 명령 감지/상태 레지스터 최소 모델 초안(coprocessor-id=0 감지, MMUSR 최소 상태)
  - ✅ 실제 페이지 워크 없이도 OS probe가 즉시 실패하지 않는 호환 레이어(옵션 플래그 기반) 추가
  - ✅ 옵션 플래그 기반 최소 동작 명세서 작성(`docs/pmmu-ready.md`)

- 캐시/파이프라인 옵션 고도화(비기본) ✅(완료)
  - ✅ I-cache 경량 모델 통계(hit/miss 카운터) 노출(`getICacheStats`, root API getter)
  - ✅ fetch miss penalty 옵션 조정 경로 추가(`setICacheFetchMissPenalty`)
  - ✅ 파이프라인 모드 플래그(`off/approx/detailed`) 추가(동작 확장 포인트 예약)
  - ✅ 기능 플래그 + 문서화 반영

- 플랫폼 주변장치/PIC 레이어 준비 ✅(완료)
  - ✅ CPU 외부 모듈로 PIC(priority encoder), timer tick, 최소 UART 스텁 구현(`src/platform/*`)
  - ✅ 코어와 플랫폼 경계(IRQ 주입/ack/vector 계약) 문서화(`docs/platform-layer.md`)
  - ✅ 샘플 플랫폼 루프에서 주기 IRQ/핸들러 왕복 데모 동작(`src/demo_platform_loop.zig`)

- 벤치마크/품질 측정 ✅(완료)
  - ✅ 대표 워크로드 3개 기준 회귀 성능 측정 실행기 추가(`src/bench_workloads.zig`)
  - ✅ CPI/MIPS는 참고 지표, 기능 회귀 우선 게이트 정책 명시
  - ✅ 재현 가능한 벤치 실행 절차/기준 수치 문서화(`docs/benchmark-guide.md`)

- 외부 검증 스위트 연동 ✅(완료)
  - ✅ 외부 68k validation vectors(JSON) 로드 테스트 러너 추가(`src/external_vectors.zig`)
  - ✅ 희소 인코딩(bitfield/packed decimal/exception return PC) subset 벡터 우선 연동(`external_vectors/subset`)
  - ✅ `zig build test` 경로와 CI(`.github/workflows/ci.yml`)에서 subset 자동 실행

## 후속 유지보수 모음

- 예외 프레임 정확도 보강 시 stack/frame 상호영향 회귀 유지
- Format B 및 드문 fault subtype 세분 필드 검증 확장
- C API 에러 코드형 ABI(v2) 추가 시 동일 시나리오를 새 API로 병행 검증
- 구 API 제거 시기/버전 정책 확정(선택)
- bitfield 희소 인코딩 및 외부 validation vector와의 교차검증
- 신규 명령/사이클 정책 변경 시 고정 cycle assertion 테스트 동반 갱신
- 핸들러 반환 타입 확장 시 코프로세서 계약 문서/회귀 동시 갱신
- 소프트웨어 TLB 도입 후 translator/hook 변경 시 flush/invalidate 누락 회귀 테스트 유지

---

## 신규 개선 과제 (2026-02-13 분석)

### 높은 우선순위

- **코드 모듈화 개선**
  - `cpu.zig` 분리: 예외 처리(`exception.zig`), 인터럽트(`interrupt.zig`), 레지스터 접근(`registers.zig`)
  - 목표: 단일 파일 3,600줄 → 각 모듈 1,000줄 이하로 분할
  - 이유: 유지보수성 향상, 컴파일 시간 단축

- **에러 처리 통합**
  - Zig 내부 `anyerror` → 구조화된 에러 타입 전환
  - C API 에러 매핑 함수(`mapMemoryError` 등) 확장 및 문서화
  - 목표: 타입 안전성 강화, 디버깅 효율성 향상

### 중간 우선순위

- **메모리 할당 최적화**
  - Arena allocator 도입으로 빠른 할당/해제 경로 추가
  - Context별 allocator 풀링으로 멀티스레드 성능 개선
  - 벤치마크 목표: 멀티 인스턴스 생성/파괴 처리량 50% 향상

- **I-Cache 구조 개선**
  - 현재: 64 entry direct-mapped → 제안: 2-way set associative
  - 충돌 감소로 히트율 향상 기대 (벤치 워크로드 기준 측정 필요)
  - 옵션 플래그로 기존 모델과 병행 지원

- **테스트 통합 및 자동화**
  - 통합 테스트 러너 추가 (`zig build test-all`)
  - 테스트 결과 리포트 생성 (JSON/HTML)
  - Coverage 도구 연동 검토 (kcov, Zig 0.14+ 네이티브 지원 대기)
  - CI/CD 성능 회귀 검사 통합 (벤치마크 자동 실행 + 추이 그래프)

### 낮은 우선순위

- **문서 자동화**
  - Zig doc comments 표준화
  - `zig build docs` 명령으로 HTML 문서 생성
  - C API 참고 문서 자동화 (Doxygen 스타일)

- **예제 확장**
  - 실용적 예제 추가:
    - 간단한 OS 부트로더 시뮬레이션
    - Atari ST 게임 일부 에뮬레이션 (예: Pong 클론)
    - 어셈블러 통합 예제 (vasm/asmx 연동)

- **디버깅 지원 강화**
  - GDB 리모트 프로토콜 stub 구현
  - 메모리/레지스터 덤프 포맷터 (JSON/human-readable)
  - 실행 추적(trace) 로그 옵션 (CSV/바이너리)

- **플러그인 아키텍처**
  - 주변장치(PIC/Timer/UART) 동적 로딩 지원
  - 사용자 정의 버스 컨트롤러 등록 API 강화
  - 플러그인 예제 및 가이드 문서 작성

### 장기 과제

- **PMMU 완전 구현**
  - 현재: 최소 호환 레이어만 존재
  - 목표: OS 부팅 가능 수준 (Unix/AmigaOS)
  - 단계별: TLB 구현 → 페이지 폴트 → 보호 도메인

### 기술 부채 정리

- **빌드 시스템 정리**
  - 개별 실행 파일 12개 → 타겟 그룹화 (`test-*`, `demo-*`)
  - 불필요한 artifact 제거 또는 조건부 빌드

- **플랫폼 지원 확대**
  - Windows/Linux 검증 완료 → macOS 명시적 테스트 추가
  - CI에 macOS runner 추가 (GitHub Actions)

- **의존성 정책 수립**
  - 현재: zero-dependency 유지 중
  - 검토: JSON 파서(std.json 충분), 외부 라이브러리 도입 기준 명시

### Quick Wins (즉시 실행 가능)

- [ ] `.editorconfig` 추가 (코딩 스타일 통일)
- [ ] `CONTRIBUTING.md` 작성 (PR 가이드라인, 커밋 컨벤션)
- [ ] GitHub Actions에 Windows 빌드 추가 (현재 Linux만)
- [ ] 예제에 실행 결과 스크린샷/출력 추가 (`examples/README.md`)
- [ ] `docs/architecture.md` 작성 (전체 구조 다이어그램)
- [ ] LICENSE 파일 명시 (현재 없음, MIT/Apache 2.0 검토)
