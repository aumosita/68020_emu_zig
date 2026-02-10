# Motorola 68020 Emulator

A high-performance Motorola 68020 processor emulator written in Zig 0.13.

## Features

- ✅ **Full 68020 architecture**
  - 8 data registers (D0-D7, 32-bit)
  - 8 address registers (A0-A7, 32-bit)
  - Program counter and status register
  - 16MB integrated memory (configurable)

- ✅ **Implemented Instructions**
  - MOVEQ - Move quick immediate
  - NOP - No operation
  - ADDQ/SUBQ - Quick add/subtract
  - CLR - Clear register
  - TST - Test operand
  - SWAP - Swap register halves
  - RTS - Return from subroutine
  - BRA/Bcc - Branch instructions

- ✅ **Memory System**
  - Big-endian byte order (Motorola standard)
  - Configurable memory size
  - Integrated with CPU for performance
  - 24-bit addressing (16MB max)

- ✅ **C API**
  - Usable from Python, C, C++, and other languages
  - Static and dynamic libraries
  - Simple and clean interface

## Building

### Prerequisites
- Zig 0.13.0 or later

### Build Instructions

```bash
# Using included Zig compiler (Windows)
zig-windows-x86_64-0.13.0\zig.exe build

# Or if Zig is in PATH
zig build
```

**Output:**
- `zig-out/lib/m68020-emu.lib` - Static library
- `zig-out/lib/m68020-emu.dll` - Dynamic library
- `zig-out/bin/m68020-emu-test.exe` - Test executable

### Running Tests

```bash
# Run test executable
zig-out\bin\m68020-emu-test.exe

# Run Zig unit tests
zig build test
```

## Usage

### Zig API

```zig
const std = @import("std");
const cpu = @import("cpu.zig");

pub fn main() !void {
    var m68k = cpu.M68k.init(std.heap.page_allocator);
    defer m68k.deinit();
    
    // Write program to memory
    try m68k.memory.write16(0x1000, 0x702A);  // MOVEQ #42, D0
    
    // Set PC and execute
    m68k.pc = 0x1000;
    _ = try m68k.step();
    
    // D0 now contains 42
    std.debug.print("D0 = {}\n", .{m68k.d[0]});
}
```

### Python API

```python
import ctypes

# Load library
lib = ctypes.CDLL('./zig-out/lib/m68020-emu.dll')

# Setup function signatures
lib.m68k_create.restype = ctypes.c_void_p
lib.m68k_destroy.argtypes = [ctypes.c_void_p]
lib.m68k_step.argtypes = [ctypes.c_void_p]
lib.m68k_step.restype = ctypes.c_int

# Create CPU
cpu = lib.m68k_create()

# Execute instruction
cycles = lib.m68k_step(cpu)

# Cleanup
lib.m68k_destroy(cpu)
```

See `docs/python-examples.md` for more examples.

### C API Reference

```c
// Lifecycle
void* m68k_create();
void* m68k_create_with_memory(uint32_t memory_size);
void m68k_destroy(void* cpu);
void m68k_reset(void* cpu);

// Execution
int m68k_step(void* cpu);
int m68k_execute(void* cpu, uint32_t cycles);

// Program Counter
void m68k_set_pc(void* cpu, uint32_t pc);
uint32_t m68k_get_pc(void* cpu);

// Registers
void m68k_set_reg_d(void* cpu, uint8_t reg, uint32_t value);
uint32_t m68k_get_reg_d(void* cpu, uint8_t reg);
void m68k_set_reg_a(void* cpu, uint8_t reg, uint32_t value);
uint32_t m68k_get_reg_a(void* cpu, uint8_t reg);

// Memory Access
void m68k_write_memory_8(void* cpu, uint32_t addr, uint8_t value);
void m68k_write_memory_16(void* cpu, uint32_t addr, uint16_t value);
void m68k_write_memory_32(void* cpu, uint32_t addr, uint32_t value);
uint8_t m68k_read_memory_8(void* cpu, uint32_t addr);
uint16_t m68k_read_memory_16(void* cpu, uint32_t addr);
uint32_t m68k_read_memory_32(void* cpu, uint32_t addr);

// Info
uint32_t m68k_get_memory_size(void* cpu);
int m68k_load_binary(void* cpu, const uint8_t* data, uint32_t length, uint32_t start_addr);
```

## Project Structure

```
m68020-emu/
├── src/
│   ├── main.zig        # Test executable
│   ├── root.zig        # C API exports
│   ├── cpu.zig         # CPU state and control
│   ├── memory.zig      # Memory subsystem
│   ├── decoder.zig     # Instruction decoder
│   └── executor.zig    # Instruction executor
├── docs/
│   ├── README.md                # Documentation index
│   ├── 68020-reference.md       # CPU architecture reference
│   ├── instruction-set.md       # Complete instruction set
│   ├── testing-guide.md         # Testing strategies
│   └── python-examples.md       # Python usage examples
├── build.zig           # Build configuration
├── build.zig.zon       # Dependencies
└── README.md           # This file
```

## Documentation

Comprehensive documentation is available in the `docs/` directory:

- **[68020-reference.md](docs/68020-reference.md)** - Technical reference and architecture
- **[instruction-set.md](docs/instruction-set.md)** - Complete 68020 instruction set
- **[testing-guide.md](docs/testing-guide.md)** - Testing strategies and examples
- **[python-examples.md](docs/python-examples.md)** - Python integration guide

## Implementation Status

### Completed ✅
- Basic CPU architecture
- Memory subsystem (configurable size)
- Instruction decoder framework
- Basic instruction execution
- Core instructions (MOVEQ, NOP, ADDQ, etc.)
- C API for external use
- Build system (static + dynamic libraries)

### In Progress 🚧
- Complete instruction set implementation
- All addressing modes
- Exception handling

### Planned ⏳
- Cycle-accurate timing
- Instruction cache simulation
- Complete test suite
- Real software compatibility (Amiga, Atari ST, Mac)

## Performance

Target: 10+ million instructions/second on modern hardware

Current status: TBD (benchmarking needed)

## Contributing

Contributions welcome! Areas of interest:
- Implementing missing instructions
- Adding test cases
- Performance optimization
- Documentation improvements

## References

- [MC68020 User's Manual](https://www.nxp.com/docs/en/data-sheet/MC68020UM.pdf)
- [M68000 Family Programmer's Reference](https://www.nxp.com/docs/en/reference-manual/M68000PRM.pdf)
- [Musashi](https://github.com/kstenerud/Musashi) - Reference 680x0 emulator

## License

This project is provided as-is for educational and development purposes.

## Credits

Developed with reference to official Motorola 68020 documentation and various reference implementations.

---

**Version**: 0.1.0-dev  
**Last Updated**: 2026-02-11
