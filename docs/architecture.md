# Architecture Overview

## High-Level Structure

```
┌─────────────────────────────────────────────────────────────┐
│                        C/Python API                          │
│                      (src/root.zig)                          │
└─────────────────────┬───────────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────────┐
│                      Core Emulator                           │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│  │   CPU    │  │ Decoder  │  │ Executor │  │  Memory  │   │
│  │ (cpu.zig)│◄─┤(decoder) │◄─┤(executor)│◄─┤(memory)  │   │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘   │
│       │              │              │              │        │
│       └──────────────┴──────────────┴──────────────┘        │
└─────────────────────┬───────────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────────┐
│                    Hardware Layer                            │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │
│  │   VIA    │  │   RTC    │  │   RBV    │  │   SCSI   │   │
│  │ (6522)   │  │(Pram/Clk)│  │(VIA2/VBL)│  │ (NCR 53  │   │
│  └──────────┘  └──────────┘  └──────────┘  └──────────┘   │
│  ┌──────────┐  ┌──────────┐                                │
│  │  Video   │  │   ADB    │                                │
│  │(Framebuf)│  │(Kbd/Mous)│                                │
│  └──────────┘  └──────────┘                                │
└─────────────────────┬───────────────────────────────────────┘
                      │
┌─────────────────────▼───────────────────────────────────────┐
│                   System Integrations                        │
│                 (src/systems/mac_lc.zig)                     │
│           Mac LC / Amiga / Atari ST / Generic                │
└─────────────────────────────────────────────────────────────┘
```

## Module Breakdown

### Core Layer (`src/core/`)

#### `cpu.zig` - CPU State and Control
- **Responsibility**: CPU state machine, execution loop, exception handling
- **Key Types**:
  - `M68k`: Main CPU state structure
  - `CpuConfig`: Configuration options
- **Key Functions**:
  - `init()`: Initialize CPU with memory
  - `step()`: Execute one instruction
  - `reset()`: Reset CPU to initial state
  - `raiseException()`: Exception entry logic
- **Dependencies**: Memory, Decoder, Executor, Registers, Exception, Interrupt

#### `registers.zig` - Register Access
- **Responsibility**: Register file management (D0-D7, A0-A7, PC, SR)
- **Features**:
  - Stack pointer banking (USP/ISP/MSP)
  - Supervisor/User mode switching
  - Register read/write with validation

#### `exception.zig` - Exception Handling
- **Responsibility**: Exception vector table, exception frame construction
- **Key Functions**:
  - `buildExceptionFrame()`: Construct stack frames (Format A/B/etc)
  - `handleBusError()`, `handleAddressError()`: Specific exception handlers
  - Vector routing (Illegal, Privilege, Trap, etc.)

#### `interrupt.zig` - Interrupt Processing
- **Responsibility**: IRQ handling, interrupt priority, autovector/vectored IRQ
- **Key Functions**:
  - `checkPendingInterrupt()`: IRQ priority check
  - `acknowledgeInterrupt()`: IRQ ack and vector fetch
  - `setIRQ()`, `setIRQVector()`, `setSpuriousIRQ()`: External IRQ API

#### `decoder.zig` - Instruction Decoding
- **Responsibility**: Opcode → Instruction structure
- **Key Types**:
  - `Instruction`: Decoded instruction representation
  - `EffectiveAddress`: EA mode and register
- **Features**:
  - 68000/68020 instruction set support
  - Extension word parsing
  - Effective address calculation

#### `executor.zig` - Instruction Execution
- **Responsibility**: Execute decoded instructions
- **Organization**: Grouped by instruction family
  - Data movement: `MOVE`, `MOVEM`, `LEA`, `PEA`
  - Arithmetic: `ADD`, `SUB`, `MUL`, `DIV`
  - Logic: `AND`, `OR`, `EOR`, `NOT`
  - Shifts: `LSL`, `ASR`, `ROL`, `ROXL`
  - Branches: `BRA`, `Bcc`, `BSR`, `JMP`, `JSR`
  - System: `RTE`, `STOP`, `RESET`, `TRAP`
  - 68020 extensions: `CALLM`, `RTM`, bitfields, `CAS/CAS2`

#### `memory.zig` - Memory Subsystem
- **Responsibility**: Memory access, bus protocol, address translation
- **Features**:
  - 8/16/32-bit read/write operations
  - Alignment enforcement
  - Bus hook/translator callbacks
  - Dynamic bus sizing (8/16/32-bit ports)
  - Software TLB (8-entry direct-mapped cache)
  - Wait state regions
  - Bus cycle statistics

#### `errors.zig` - Error Types
- **Responsibility**: Structured error type definitions
- **Error Categories**:
  - `MemoryError`: Address/Bus/Alignment errors
  - `CpuError`: Illegal instruction, privilege violations
  - `DecodeError`: Invalid opcode/EA
  - `ConfigError`: Configuration errors
- **Features**: C API status code conversion, error messages

#### Other Core Modules
- `ea_cycles.zig`: EA mode cycle calculation
- `bus_cycle.zig`: Bus cycle state machine (S0-S3, wait states)
- `scheduler.zig`: Event scheduler for timed operations
- `external_vectors.zig`: External test vector loader (JSON)

### Hardware Layer (`src/hw/`)

#### `via6522.zig` - VIA (Versatile Interface Adapter)
- **Chip**: MOS 6522
- **Features**: Timers (T1/T2), I/O ports, interrupt flags
- **Use Case**: Mac LC system timing, peripheral I/O

#### `rtc.zig` - Real-Time Clock
- **Features**: Second counter, 256-byte PRAM (parameter RAM)
- **Use Case**: Mac LC system clock and non-volatile settings

#### `rbv.zig` - RBV (RAM-Based Video)
- **Features**: VBL (vertical blank) interrupt, interrupt routing
- **Use Case**: Mac LC VIA2 replacement, video sync

#### `video.zig` - Video Framebuffer
- **Features**: VRAM, 8-bit palette (VDAC), pixel rendering
- **Use Case**: Mac LC video output

#### `scsi.zig` - SCSI Controller
- **Chip**: NCR 5380
- **Features**: Register interface, basic command handling
- **Status**: Minimal stub implementation

#### `adb.zig` - Apple Desktop Bus
- **Features**: Keyboard/mouse communication protocol
- **Status**: Basic integration complete

### Platform Layer (`src/platform/`)

#### `mod.zig` - Platform Abstraction
- **Responsibility**: Define platform-agnostic interfaces

#### `pic.zig` - Programmable Interrupt Controller
- **Features**: IRQ priority encoding, masking
- **Use Case**: External interrupt routing to CPU

#### `timer.zig` - System Timer
- **Features**: Periodic tick generation
- **Use Case**: Platform-level timing events

#### `uart_stub.zig` - UART Stub
- **Features**: Serial I/O placeholder
- **Status**: Minimal implementation for testing

### System Integrations (`src/systems/`)

#### `mac_lc.zig` - Macintosh LC System
- **Integration**: CPU + Memory + VIA + RTC + RBV + Video + SCSI + ADB
- **Features**: Mac LC memory map, ROM loading, peripheral routing
- **Goal**: Boot System 6.0.8 / System 7

#### Future Systems
- Amiga 500/1200
- Atari ST
- Generic 68000 board

## Data Flow

### Instruction Execution Flow

```
1. CPU.step()
   ↓
2. Decoder.decode(opcode)
   ↓
3. Executor.execute(instruction)
   ↓
4. Memory.read/write(addr)
   ↓
5. Bus hook / Address translator (optional)
   ↓
6. Actual memory access or peripheral I/O
```

### Exception Flow

```
1. Exception occurs (e.g., Bus Error, Illegal Instruction)
   ↓
2. CPU.raiseException(vector)
   ↓
3. Exception.buildExceptionFrame()
   ↓
4. Stack frame push (Format A/B)
   ↓
5. Vector fetch from memory
   ↓
6. PC ← vector address
   ↓
7. Resume execution at exception handler
```

### Interrupt Flow

```
1. External device raises IRQ (e.g., VIA timer)
   ↓
2. PIC encodes IRQ level
   ↓
3. CPU.setIRQ(level)
   ↓
4. CPU.step() checks pending interrupt
   ↓
5. Interrupt.acknowledgeInterrupt()
   ↓
6. Vector fetch (autovector or vectored)
   ↓
7. Exception entry (same as exception flow)
```

## Memory Map Example (Mac LC)

```
0x000000 - 0x3FFFFF   RAM (4 MB)
0x400000 - 0x4FFFFF   ROM (1 MB)
0x500000 - 0x5FFFFF   Video RAM
0x900000 - 0x9FFFFF   I/O Space
  0x900000 - 0x9003FF   VIA 6522
  0x900400 - 0x9007FF   RTC
  0x900800 - 0x900BFF   RBV
  0xF00000 - 0xF0FFFF   SCSI (NCR 5380)
```

## Key Design Principles

### 1. Layered Architecture
- **Core** layer is hardware-agnostic
- **Hardware** layer implements specific chips
- **System** layer integrates everything

### 2. Bus Abstraction
- Memory accesses go through `Memory` module
- Bus hooks allow platform-specific behavior
- Address translators enable virtual memory (PMMU)

### 3. Error Handling
- Structured error types (`errors.zig`)
- C API boundary converts to status codes
- Internal Zig code uses error unions

### 4. Testability
- Unit tests per module
- Integration tests via `root.zig`
- External validation vectors (JSON)

### 5. Performance
- Cycle accuracy is optional (configurable)
- Translation cache for PMMU lookups
- Split cycle penalty tracking

## Extension Points

### Adding a New Instruction
1. Add opcode pattern to `decoder.zig`
2. Implement execution in `executor.zig`
3. Add cycle cost to `ea_cycles.zig` (if applicable)
4. Write unit tests

### Adding a New Peripheral
1. Create module in `src/hw/`
2. Implement register interface
3. Integrate into system (`src/systems/*.zig`)
4. Map I/O addresses in memory map

### Adding a New System
1. Create module in `src/systems/`
2. Define memory map
3. Instantiate CPU + peripherals
4. Implement ROM loading
5. Add boot sequence

## Build System

Zig's `build.zig` defines:
- Library targets (`libm68020-emu`)
- Test targets (`test`, `test-68020`, `test-phase1`, etc.)
- Example executables (`fibonacci`, `bitfield-demo`, etc.)
- CI integration (`.github/workflows/ci.yml`)

### Key Build Commands

```bash
zig build              # Build library and examples
zig build test         # Run all tests
zig test src/core/cpu.zig   # Run specific module tests
```

## Documentation Structure

```
docs/
├── README.md                    # Documentation index
├── architecture.md              # This file
├── error-handling.md            # Error handling guide
├── instruction-set.md           # Instruction reference
├── 68020-reference.md           # 68020 specifics
├── testing-guide.md             # Testing procedures
├── cycle-model.md               # Cycle accuracy policy
├── bus-cycle-state-machine.md   # Bus protocol details
├── platform-layer.md            # Platform abstraction
└── ...
```

## Further Reading

- [Instruction Set](instruction-set.md) - Detailed instruction documentation
- [Error Handling](error-handling.md) - Error types and C API mapping
- [Testing Guide](testing-guide.md) - How to write and run tests
- [Cycle Model](cycle-model.md) - Cycle accuracy policy
- [Bus Cycle State Machine](bus-cycle-state-machine.md) - Memory access timing

---

**Last Updated**: 2026-02-14
