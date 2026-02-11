# Coprocessor Handler Contract

## 대상

- `src/cpu.zig`의 `M68k.CoprocessorHandler`
- `src/executor.zig`의 `executeCoprocessorDispatch`

## 핸들러 시그니처

```zig
pub const CoprocessorHandler = *const fn (
    ctx: ?*anyopaque,
    m68k: *M68k,
    opcode: u16,
    pc: u32,
) CoprocessorResult;
```

- `ctx`: 외부 상태 포인터(옵션)
- `m68k`: 현재 CPU 인스턴스
- `opcode`: 현재 F-line opcode
- `pc`: 디스패치 시점 PC

## 반환 의미

- `.handled(cycles)`
  - 명령을 소프트웨어 코프로세서가 처리 완료.
  - `m68k.pc`를 핸들러가 변경하지 않으면 실행기는 자동으로 `i.size`만큼 PC를 전진.
  - 반환 `cycles`는 그대로 step cycle에 반영.

- `.unavailable`
  - 코프로세서 부재/미지원으로 간주.
  - 실행기는 line-F 에뮬레이터 예외(`vector 11`)로 폴백.

- `.fault(fault_addr)`
  - 핸들러 내부 fault를 버스 에러로 승격.
  - 실행기는 `vector 2` Format A frame으로 진입하며 `fault_addr`를 프레임에 기록.

## 현재 고정 동작

- `.handled`: 핸들러 반환 cycle 사용
- `.unavailable`: `vector 11`, 예외 cycle 경로 사용
- `.fault`: bus error cycle `50` (dispatch 경로 고정값)

## 테스트 커버리지

- 핸들러 처리 성공:
  - `src/cpu.zig` `test "M68k coprocessor handler can emulate F-line without vector 11"`
- 핸들러 미지원 폴백:
  - `src/cpu.zig` `test "M68k coprocessor handler may defer to unavailable vector 11"`
- 핸들러 fault 버스 에러 승격:
  - `src/cpu.zig` `test "M68k coprocessor handler fault routes to vector 2 format A bus error frame"`
