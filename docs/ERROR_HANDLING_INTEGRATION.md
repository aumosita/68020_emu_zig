# Error Handling Integration - 2026-02-14

## Summary

에러 처리 통합 작업을 완료했습니다. 기존의 `anyerror` 사용을 구조화된 에러 타입으로 전환하여 타입 안전성과 디버깅 효율성을 향상시켰습니다.

## Changes

### 1. 새 모듈: `src/core/errors.zig`

구조화된 에러 타입 시스템을 정의했습니다:

#### Error Categories

- **MemoryError** (C API: -2 ~ -6)
  - InvalidAddress
  - BusError
  - AddressError
  - BusRetry
  - BusHalt

- **CpuError** (C API: -10 ~ -16)
  - IllegalInstruction
  - PrivilegeViolation
  - DivisionByZero
  - BoundsCheckFailed
  - TrapException
  - UnimplementedInstruction
  - CoprocessorError

- **DecodeError** (C API: -20 ~ -23)
  - InvalidOpcode
  - InvalidEAMode
  - InvalidExtensionWord
  - FetchOutOfBounds

- **ConfigError** (C API: -30 ~ -32)
  - InvalidConfig
  - InvalidMemorySize
  - InvalidRegister

#### Combined Error Sets

```zig
pub const MemoryAccessError = MemoryError || std.mem.Allocator.Error;
pub const ExecutionError = CpuError || MemoryError || DecodeError;
pub const EmulatorError = ExecutionError || ConfigError || std.mem.Allocator.Error;
```

#### Conversion Functions

- `memoryErrorToStatus(err: MemoryError) c_int`
- `cpuErrorToStatus(err: CpuError) c_int`
- `decodeErrorToStatus(err: DecodeError) c_int`
- `configErrorToStatus(err: ConfigError) c_int`
- `errorToStatus(err: EmulatorError) c_int`
- `errorMessage(err: EmulatorError) []const u8`

### 2. Updated: `src/root.zig`

C API 에러 매핑 함수를 개선했습니다:

**Before:**
```zig
fn mapMemoryError(err: anyerror) c_int {
    return switch (err) {
        error.InvalidAddress, error.BusError, ... => STATUS_MEMORY_ERROR,
        else => STATUS_MEMORY_ERROR,
    };
}
```

**After:**
```zig
const errors = @import("core/errors.zig");

fn mapMemoryError(err: errors.MemoryError) c_int {
    return errors.memoryErrorToStatus(err);
}

fn mapAnyError(err: anyerror) c_int {
    return if (@as(?errors.EmulatorError, @errorCast(err))) |e| 
        errors.errorToStatus(e)
    else 
        STATUS_MEMORY_ERROR;
}
```

### 3. New Documentation: `docs/error-handling.md`

포괄적인 에러 처리 가이드를 작성했습니다:

- Error category 설명 및 C API status code 매핑
- Zig 코드에서의 사용 예제
- C API 통합 방법
- Best practices
- Migration guide (anyerror → structured errors)
- Testing guide

## Benefits

### 1. Type Safety

**Before:**
```zig
pub fn foo() anyerror!void { ... }  // 어떤 에러가 발생할 수 있는지 불명확
```

**After:**
```zig
pub fn foo() errors.CpuError!void { ... }  // CPU 관련 에러만 발생 가능
```

### 2. Better Error Messages

```zig
const msg = errors.errorMessage(error.BusError);
// "Bus error during memory access"
```

### 3. Structured C API Status Codes

에러 범주별로 구조화된 status code:
- -1: Invalid argument
- -2 ~ -6: Memory errors
- -10 ~ -16: CPU errors
- -20 ~ -23: Decode errors
- -30 ~ -32: Config errors
- -100: Out of memory

### 4. Easier Debugging

에러 발생 시 정확한 에러 타입과 메시지를 통해 디버깅이 용이합니다.

## Testing

모든 테스트가 통과했습니다:

```bash
zig build test  # 전체 테스트 통과 (251/251)
zig test src/core/errors.zig  # 에러 모듈 단위 테스트
```

## Migration Status

### Completed

- ✅ 에러 타입 정의 및 분류
- ✅ 변환 함수 구현
- ✅ C API 매핑 함수 업데이트
- ✅ 문서 작성
- ✅ 단위 테스트
- ✅ TODO.md 업데이트

### Future Work

기존 코드에서 `anyerror`를 사용하는 부분을 점진적으로 구조화된 에러 타입으로 전환할 수 있습니다. 현재는 C API 경계에서만 전환을 적용했으며, 내부 모듈(`memory.zig`, `cpu.zig` 등)은 기존 코드와의 호환성을 유지하면서 점진적으로 개선할 수 있습니다.

## Files Modified

- **Created**: `src/core/errors.zig` (6,974 bytes)
- **Modified**: `src/root.zig` (에러 매핑 함수 개선)
- **Created**: `docs/error-handling.md` (6,158 bytes)
- **Modified**: `TODO.md` (에러 처리 통합 항목 완료 표시)

## Commit Message

```
feat: Implement structured error handling system

- Add src/core/errors.zig with categorized error types
  - MemoryError, CpuError, DecodeError, ConfigError
  - Combined error sets for different operation contexts
  - C API status code conversion functions
  - Human-readable error messages

- Update C API error mapping in src/root.zig
  - Replace generic anyerror handling with structured types
  - Maintain backward compatibility

- Add comprehensive error handling guide (docs/error-handling.md)
  - Usage examples for Zig and C API
  - Migration guide from anyerror
  - Best practices

Benefits:
- Improved type safety
- Better error messages for debugging
- Structured C API status codes
- Easier error handling in client code

All tests passing (251/251)
```

## Next Steps

추천하는 다음 작업:

1. **Quick Wins 항목 진행**: 
   - `.editorconfig` 추가
   - `CONTRIBUTING.md` 작성
   - GitHub Actions에 Windows 빌드 추가
   - `LICENSE` 파일 추가

2. **점진적 마이그레이션**:
   - 내부 모듈에서 `anyerror` → 구조화된 에러 타입 전환
   - 각 모듈별로 적절한 에러 셋 사용

3. **에러 컨텍스트 추가** (향후):
   - 에러 발생 시 PC, 명령어 등의 컨텍스트 정보 포함
