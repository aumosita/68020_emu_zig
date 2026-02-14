# Examples

This directory contains example programs demonstrating various features of the 68020 emulator.

## Running Examples

Build all examples:
```bash
zig build
```

The compiled binaries will be in `zig-out/bin/`:
- `fibonacci` - Fibonacci sequence calculator
- `bitfield-demo` - Bitfield instruction demonstration
- `exception-demo` - Exception handling example

## Examples Overview

### 1. Fibonacci (`fibonacci.zig`)

Calculates Fibonacci numbers using 68020 assembly.

**Run:**
```bash
./zig-out/bin/fibonacci
```

**Expected Output:**
```
Fibonacci sequence (68020 emulator):
F(0) = 0
F(1) = 1
F(2) = 1
F(3) = 2
F(4) = 3
F(5) = 5
F(6) = 8
F(7) = 13
F(8) = 21
F(9) = 34
F(10) = 55
```

**What it demonstrates:**
- Basic CPU initialization
- Loading binary code into memory
- Arithmetic operations (`ADD.L`)
- Loop control (`DBRA`)
- Register usage (D0-D2)

**Assembly pseudocode:**
```asm
    MOVE.L #0, D0      ; fib(0) = 0
    MOVE.L #1, D1      ; fib(1) = 1
    MOVE.L #10, D2     ; counter
loop:
    MOVE.L D1, D3      ; temp = current
    ADD.L D0, D1       ; current += previous
    MOVE.L D3, D0      ; previous = temp
    DBRA D2, loop      ; loop 10 times
```

---

### 2. Bitfield Demo (`bitfield_demo.zig`)

Demonstrates 68020 bitfield instructions (`BFEXTU`, `BFINS`, `BFTST`).

**Run:**
```bash
./zig-out/bin/bitfield-demo
```

**Expected Output:**
```
68020 Bitfield Instructions Demo
=================================

Initial value: 0xABCD1234

BFEXTU D0{8:8} -> Extract bits 8-15 (width 8)
Extracted value: 0x00000012

BFINS D1{16:8}, D0 -> Insert 0xFF at bits 16-23
Result: 0xABFF1234

BFTST D0{24:4} -> Test bits 24-27
Z flag: false (bits are set)
N flag: true (MSB of field is 1)

All bitfield operations completed successfully!
```

**What it demonstrates:**
- 68020 bitfield instructions
- Bit extraction with zero-extension (`BFEXTU`)
- Bit insertion (`BFINS`)
- Bit testing with flag updates (`BFTST`)
- CCR (Condition Code Register) flag behavior

**Instructions used:**
```asm
BFEXTU D0{offset:width}, Dn  ; Extract and zero-extend
BFINS Dn, D0{offset:width}   ; Insert bits
BFTST D0{offset:width}       ; Test bits, set Z/N flags
```

---

### 3. Exception Demo (`exception_demo.zig`)

Shows exception handling for illegal instructions, privilege violations, and traps.

**Run:**
```bash
./zig-out/bin/exception-demo
```

**Expected Output:**
```
68020 Exception Handling Demo
==============================

Test 1: Illegal Instruction
---------------------------
Executing illegal opcode: 0x4AFC
Exception caught: Illegal instruction (vector 4)
PC after exception: 0x00000010
SR: 0x2700 (supervisor mode)

Test 2: Privilege Violation
----------------------------
Attempting MOVE to SR in user mode
Exception caught: Privilege violation (vector 8)
Switched to supervisor mode
PC: 0x00000020

Test 3: TRAP Instruction
-------------------------
Executing TRAP #5
Exception caught: Trap #5 (vector 37)
Vector address: 0x00000094
PC after TRAP: 0x00000030

Test 4: Division by Zero
-------------------------
Executing DIVU D1, D0 with D1 = 0
Exception caught: Division by zero (vector 5)
PC: 0x00000040

All exception tests passed!
```

**What it demonstrates:**
- Exception vector table
- Illegal instruction detection (vector 4)
- Privilege violation (vector 8)
- TRAP instruction (vectors 32-47)
- Division by zero (vector 5)
- Exception stack frames
- Supervisor/user mode switching

**Exception Flow:**
```
1. Exception occurs
2. Current PC and SR pushed to stack
3. PC ← (vector_address)
4. SR ← supervisor mode, interrupts masked
5. Handler executes
6. RTE restores PC and SR
```

---

## Writing Your Own Examples

### Basic Template

```zig
const std = @import("std");
const m68k = @import("m68020-emu");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Create CPU with 64KB memory
    var cpu = m68k.M68k.init(allocator, .{ .size = 64 * 1024 });
    defer cpu.deinit();

    // Load your code
    const code = [_]u8{
        0x70, 0x05,  // MOVEQ #5, D0
        0x4E, 0x75,  // RTS
    };
    try cpu.memory.loadBinary(0x1000, &code);
    cpu.setPC(0x1000);

    // Execute
    while (cpu.getPC() != 0x0000) {
        _ = try cpu.step();
    }

    // Read result
    const result = cpu.getRegD(0);
    std.debug.print("D0 = {}\n", .{result});
}
```

### Adding to Build System

Edit `build.zig`:

```zig
const my_example = b.addExecutable(.{
    .name = "my-example",
    .root_source_file = b.path("examples/my_example.zig"),
    .target = target,
    .optimize = optimize,
});
my_example.root_module.addImport("m68020-emu", lib.root_module);
b.installArtifact(my_example);
```

## Tips

1. **Memory Size**: Use powers of 2 for memory size (64KB, 1MB, 16MB)
2. **Code Placement**: Load code at addresses > 0x400 to avoid exception vector table (0x000-0x3FF)
3. **Debugging**: Use `cpu.getPC()`, `cpu.getRegD()`, `cpu.getRegA()` to inspect state
4. **Endianness**: 68020 is big-endian (MSB first)
5. **Alignment**: Word/long accesses must be aligned (even addresses)

## Further Reading

- [Instruction Set Reference](../docs/instruction-set.md)
- [68020 User's Manual](../docs/68020-reference.md)
- [Testing Guide](../docs/testing-guide.md)
