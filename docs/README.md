# 문서 인덱스

68020_emu_zig 프로젝트 기술 문서.

## 문서 목록

| 문서 | 내용 |
|------|------|
| [architecture.md](architecture.md) | 전체 아키텍처, 모듈 구조, 데이터 흐름 |
| [instruction-set.md](instruction-set.md) | 명령어 세트 구현 현황 (97/105, 92%) |
| [internals.md](internals.md) | SP 모델, 에러 처리, MOVEC, 코프로세서 |
| [timing-and-bus.md](timing-and-bus.md) | 사이클 모델, 버스, 캐시, 프로파일러 |
| [guides.md](guides.md) | 테스트, 벤치마크, 플랫폼, Python 연동 |

## 빠른 시작

```bash
zig build test --summary all    # 전체 테스트 실행
zig build run                   # 에뮬레이터 실행
```
