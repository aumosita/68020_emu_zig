# MOVEC 가이드

## 개요

`MOVEC`는 68020 제어 레지스터와 일반 레지스터 간 값을 이동합니다.

- `MOVEC Rc,Rn` / `MOVEC Rn,Rc`
- 구현 위치: 디코더(`Group 4`), 실행기(`executeMovec`)

## 지원 제어 레지스터

- `SFC` (0)
- `DFC` (1)
- `CACR` (2)
- `USP` (0x800)
- `VBR` (0x801)
- `CAAR` (0x802)
- `MSP` (0x803)
- `ISP` (0x804)

## 동작 규칙

- 특권 명령: 사용자 모드(`S=0`)에서 실행 시 privilege violation (vector 8)
- 스택 포인터 계열은 활성 스택 상태와 일관되게 반영
- 지원하지 않는 제어 레지스터는 invalid control register 오류로 처리
