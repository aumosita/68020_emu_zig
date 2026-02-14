# Error Handling Guide

## Overview

The 68020 emulator uses structured error types instead of `anyerror` to improve type safety and make error handling more explicit. All error types are defined in `src/core/errors.zig`.

## Error Categories

### Memory Errors (`MemoryError`)

Errors that occur during memory access operations:

- `InvalidAddress`: Address is outside valid memory range
- `BusError`: Bus error occurred during memory access
- `AddressError`: Address alignment violation (e.g., word access on odd address)
- `BusRetry`: Bus requested retry (temporary failure)
- `BusHalt`: Bus halted (critical failure)

**C API Status Codes**: -2 to -6

### CPU Errors (`CpuError`)

Errors that occur during instruction execution:

- `IllegalInstruction`: Illegal instruction encountered
- `PrivilegeViolation`: Privilege violation
- `DivisionByZero`: Division by zero
- `BoundsCheckFailed`: CHK/CHK2 bounds check failed
- `TrapException`: TRAP instruction executed
- `UnimplementedInstruction`: Unimplemented instruction
- `CoprocessorError`: Coprocessor protocol violation

**C API Status Codes**: -10 to -16

### Decode Errors (`DecodeError`)

Errors that occur during instruction decoding:

- `InvalidOpcode`: Invalid opcode encoding
- `InvalidEAMode`: Invalid effective address mode
- `InvalidExtensionWord`: Invalid extension word
- `FetchOutOfBounds`: PC out of bounds during fetch

**C API Status Codes**: -20 to -23

### Configuration Errors (`ConfigError`)

Errors related to emulator configuration:

- `InvalidConfig`: Invalid configuration parameter
- `InvalidMemorySize`: Memory size too small or too large
- `InvalidRegister`: Invalid register index

**C API Status Codes**: -30 to -32

## Combined Error Sets

For convenience, several combined error sets are provided:

- `MemoryAccessError = MemoryError || std.mem.Allocator.Error`
- `ExecutionError = CpuError || MemoryError || DecodeError`
- `EmulatorError = ExecutionError || ConfigError || std.mem.Allocator.Error`

## Usage in Zig Code

### Returning Errors

```zig
const errors = @import("core/errors.zig");

pub fn readMemory(addr: u32) errors.MemoryError!u8 {
    if (addr >= memory_size) {
        return error.InvalidAddress;
    }
    if (addr & 1 != 0) {
        return error.AddressError;
    }
    // ... actual read operation
}
```

### Handling Errors

```zig
const value = readMemory(0x1000) catch |err| {
    std.debug.print("Memory error: {s}\n", .{errors.errorMessage(err)});
    return;
};
```

### Error Sets in Function Signatures

Use the most specific error set that matches your function's behavior:

```zig
// Function that only does memory access
pub fn fetch(addr: u32) errors.MemoryError!u16 { ... }

// Function that decodes instructions
pub fn decode(opcode: u16) errors.DecodeError!Instruction { ... }

// Function that executes instructions (may trigger any error)
pub fn execute(inst: Instruction) errors.ExecutionError!void { ... }
```

## C API Integration

### Status Codes

The C API uses integer status codes. Status code 0 indicates success, negative values indicate specific errors:

| Range | Category |
|-------|----------|
| -1 | Invalid argument |
| -2 to -6 | Memory errors |
| -10 to -16 | CPU errors |
| -20 to -23 | Decode errors |
| -30 to -32 | Config errors |
| -100 | Out of memory |

### Error Conversion

Use the conversion functions to map Zig errors to C status codes:

```zig
const status = errors.memoryErrorToStatus(err);  // For specific error type
const status = errors.errorToStatus(err);        // For EmulatorError union
```

### Example C API Function

```zig
export fn m68k_read_memory_8_status(
    m68k: *M68k,
    addr: u32,
    out_value: *u8,
) c_int {
    const value = m68k.memory.read8(addr) catch |err| {
        return errors.errorToStatus(@errorCast(err));
    };
    out_value.* = value;
    return 0;  // STATUS_OK
}
```

## Error Messages

Get human-readable error descriptions using `errorMessage()`:

```zig
const msg = errors.errorMessage(error.BusError);
std.debug.print("Error: {s}\n", .{msg});
// Output: Error: Bus error during memory access
```

## Best Practices

1. **Use specific error sets**: Prefer `MemoryError` over `anyerror` when you know exactly what errors can occur.

2. **Document error conditions**: Use doc comments to explain when each error can occur:
   ```zig
   /// Read a byte from memory.
   /// Returns `InvalidAddress` if addr >= memory_size.
   /// Returns `BusError` if bus access fails.
   pub fn read8(addr: u32) MemoryError!u8 { ... }
   ```

3. **Handle errors explicitly**: Avoid `catch unreachable` unless you can prove the error is impossible.

4. **Use error unions in tests**: Write tests that verify both success and error paths:
   ```zig
   test "read out of bounds" {
       const result = mem.read8(0xFFFFFFFF);
       try testing.expectError(error.InvalidAddress, result);
   }
   ```

5. **Convert at API boundaries**: Keep Zig errors internal, convert to status codes only at the C API boundary.

## Migration Guide

### From `anyerror` to Structured Errors

**Before:**
```zig
pub fn foo() anyerror!void {
    return error.SomeError;
}
```

**After:**
```zig
const errors = @import("core/errors.zig");

pub fn foo() errors.CpuError!void {
    return error.IllegalInstruction;
}
```

### From Generic `catch` to Specific Error Handling

**Before:**
```zig
value = doSomething() catch return -1;
```

**After:**
```zig
value = doSomething() catch |err| {
    return errors.errorToStatus(@errorCast(err));
};
```

## Testing

The errors module includes unit tests for all conversion functions:

```bash
zig test src/core/errors.zig
```

Key tests verify:
- Error to status code conversion
- Status codes don't overlap between categories
- Error messages are non-empty
- All error types are covered

## Future Enhancements

Planned improvements to error handling:

1. **Error context**: Add context information (e.g., PC, instruction) to errors
2. **Error recovery**: Implement retry logic for transient errors (e.g., `BusRetry`)
3. **Error statistics**: Track error frequencies for debugging
4. **Localization**: Support multiple languages for error messages
