/// 68020 Emulator Error Types
/// 
/// This module defines structured error types used throughout the emulator.
/// Using specific error sets improves type safety and makes error handling more explicit.

const std = @import("std");

/// Memory access errors
pub const MemoryError = error{
    /// Address is outside valid memory range
    InvalidAddress,
    
    /// Bus error occurred during memory access
    BusError,
    
    /// Address alignment violation (e.g., word access on odd address)
    AddressError,
    
    /// Bus requested retry (temporary failure)
    BusRetry,
    
    /// Bus halted (critical failure)
    BusHalt,
};

/// CPU execution errors
pub const CpuError = error{
    /// Illegal instruction encountered
    IllegalInstruction,
    
    /// Privilege violation
    PrivilegeViolation,
    
    /// Division by zero
    DivisionByZero,
    
    /// CHK/CHK2 bounds check failed
    BoundsCheckFailed,
    
    /// TRAP instruction executed
    TrapException,
    
    /// Unimplemented instruction
    UnimplementedInstruction,
    
    /// Coprocessor protocol violation
    CoprocessorError,
};

/// Decoder errors
pub const DecodeError = error{
    /// Invalid opcode encoding
    InvalidOpcode,
    
    /// Invalid effective address mode
    InvalidEAMode,
    
    /// Invalid extension word
    InvalidExtensionWord,
    
    /// PC out of bounds during fetch
    FetchOutOfBounds,
};

/// Configuration errors
pub const ConfigError = error{
    /// Invalid configuration parameter
    InvalidConfig,
    
    /// Memory size too small or too large
    InvalidMemorySize,
    
    /// Invalid register index
    InvalidRegister,
};

/// Combined error set for memory operations
pub const MemoryAccessError = MemoryError || std.mem.Allocator.Error;

/// Combined error set for CPU step operations
pub const ExecutionError = CpuError || MemoryError || DecodeError;

/// Combined error set for all emulator operations
pub const EmulatorError = ExecutionError || ConfigError || std.mem.Allocator.Error;

/// Convert memory error to C API status code
pub fn memoryErrorToStatus(err: MemoryError) c_int {
    return switch (err) {
        error.InvalidAddress => -2,
        error.BusError => -3,
        error.AddressError => -4,
        error.BusRetry => -5,
        error.BusHalt => -6,
    };
}

/// Convert CPU error to C API status code
pub fn cpuErrorToStatus(err: CpuError) c_int {
    return switch (err) {
        error.IllegalInstruction => -10,
        error.PrivilegeViolation => -11,
        error.DivisionByZero => -12,
        error.BoundsCheckFailed => -13,
        error.TrapException => -14,
        error.UnimplementedInstruction => -15,
        error.CoprocessorError => -16,
    };
}

/// Convert decode error to C API status code
pub fn decodeErrorToStatus(err: DecodeError) c_int {
    return switch (err) {
        error.InvalidOpcode => -20,
        error.InvalidEAMode => -21,
        error.InvalidExtensionWord => -22,
        error.FetchOutOfBounds => -23,
    };
}

/// Convert config error to C API status code
pub fn configErrorToStatus(err: ConfigError) c_int {
    return switch (err) {
        error.InvalidConfig => -30,
        error.InvalidMemorySize => -31,
        error.InvalidRegister => -32,
    };
}

/// Convert any emulator error to C API status code
pub fn errorToStatus(err: EmulatorError) c_int {
    return switch (err) {
        // Memory errors
        error.InvalidAddress,
        error.BusError,
        error.AddressError,
        error.BusRetry,
        error.BusHalt => |e| memoryErrorToStatus(e),
        
        // CPU errors
        error.IllegalInstruction,
        error.PrivilegeViolation,
        error.DivisionByZero,
        error.BoundsCheckFailed,
        error.TrapException,
        error.UnimplementedInstruction,
        error.CoprocessorError => |e| cpuErrorToStatus(e),
        
        // Decode errors
        error.InvalidOpcode,
        error.InvalidEAMode,
        error.InvalidExtensionWord,
        error.FetchOutOfBounds => |e| decodeErrorToStatus(e),
        
        // Config errors
        error.InvalidConfig,
        error.InvalidMemorySize,
        error.InvalidRegister => |e| configErrorToStatus(e),
        
        // Allocator errors
        error.OutOfMemory => -100,
    };
}

/// Get human-readable error message
pub fn errorMessage(err: EmulatorError) []const u8 {
    return switch (err) {
        // Memory errors
        error.InvalidAddress => "Address is outside valid memory range",
        error.BusError => "Bus error during memory access",
        error.AddressError => "Address alignment violation",
        error.BusRetry => "Bus requested retry",
        error.BusHalt => "Bus halted",
        
        // CPU errors
        error.IllegalInstruction => "Illegal instruction",
        error.PrivilegeViolation => "Privilege violation",
        error.DivisionByZero => "Division by zero",
        error.BoundsCheckFailed => "Bounds check failed",
        error.TrapException => "TRAP exception",
        error.UnimplementedInstruction => "Unimplemented instruction",
        error.CoprocessorError => "Coprocessor error",
        
        // Decode errors
        error.InvalidOpcode => "Invalid opcode encoding",
        error.InvalidEAMode => "Invalid effective address mode",
        error.InvalidExtensionWord => "Invalid extension word",
        error.FetchOutOfBounds => "Instruction fetch out of bounds",
        
        // Config errors
        error.InvalidConfig => "Invalid configuration",
        error.InvalidMemorySize => "Invalid memory size",
        error.InvalidRegister => "Invalid register index",
        
        // Allocator errors
        error.OutOfMemory => "Out of memory",
    };
}

test "error to status code conversion" {
    const testing = std.testing;
    
    // Memory errors
    try testing.expectEqual(@as(c_int, -2), memoryErrorToStatus(error.InvalidAddress));
    try testing.expectEqual(@as(c_int, -3), memoryErrorToStatus(error.BusError));
    try testing.expectEqual(@as(c_int, -4), memoryErrorToStatus(error.AddressError));
    
    // CPU errors
    try testing.expectEqual(@as(c_int, -10), cpuErrorToStatus(error.IllegalInstruction));
    try testing.expectEqual(@as(c_int, -11), cpuErrorToStatus(error.PrivilegeViolation));
    
    // Decode errors
    try testing.expectEqual(@as(c_int, -20), decodeErrorToStatus(error.InvalidOpcode));
    try testing.expectEqual(@as(c_int, -21), decodeErrorToStatus(error.InvalidEAMode));
    
    // Config errors
    try testing.expectEqual(@as(c_int, -30), configErrorToStatus(error.InvalidConfig));
    try testing.expectEqual(@as(c_int, -31), configErrorToStatus(error.InvalidMemorySize));
}

test "error messages" {
    const testing = std.testing;
    
    const msg1 = errorMessage(error.BusError);
    try testing.expect(msg1.len > 0);
    
    const msg2 = errorMessage(error.IllegalInstruction);
    try testing.expect(msg2.len > 0);
}
