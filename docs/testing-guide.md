# 68020 Emulator Testing Guide

## Testing Strategy

### 1. Unit Testing Approach

#### Phase 1: Individual Instructions
Test each instruction in isolation with known inputs/outputs.

```python
# Example test structure
def test_move_byte():
    cpu = M68k()
    cpu.write_memory_8(0x1000, 0x42)
    cpu.write_memory_16(0, 0x10C0)  # MOVE.B (A0), D0
    # ... setup A0 = 0x1000
    cpu.step()
    assert cpu.get_reg_d(0) & 0xFF == 0x42
```

#### Phase 2: Instruction Groups
Test related instructions together to verify consistency.

#### Phase 3: Complex Scenarios
- Multi-instruction sequences
- Subroutine calls
- Exception handling

### 2. Automated Test Suites

#### Reference Emulator Comparison
Use Musashi or other known-good emulators as reference:

```python
def test_against_musashi():
    # Setup identical initial state
    our_cpu.pc = musashi_cpu.pc = 0x1000
    # Load identical program
    # Execute N instructions
    # Compare all registers and flags
```

#### Test Generation
Generate random instruction sequences and compare results:

```python
import random

def generate_test_sequence():
    opcodes = []
    for _ in range(100):
        opcode = random.randint(0, 0xFFFF)
        if is_valid_opcode(opcode):
            opcodes.append(opcode)
    return opcodes
```

### 3. Known Test Programs

#### Simple Test ROMs

##### Test 1: Basic Arithmetic
```assembly
    ORG $1000
START:
    MOVEQ   #5, D0          ; D0 = 5
    MOVEQ   #3, D1          ; D1 = 3
    ADD.B   D1, D0          ; D0 = 8
    SUB.B   D1, D0          ; D0 = 5
    MULU    D1, D0          ; D0 = 15
    DIVU    D1, D0          ; D0 = 5
    ILLEGAL                 ; Stop
```

Expected results:
- D0 = 0x00000005
- D1 = 0x00000003

##### Test 2: Memory Operations
```assembly
    ORG $1000
    LEA     DATA, A0
    MOVE.L  (A0)+, D0       ; D0 = $12345678
    MOVE.W  (A0)+, D1       ; D1 = $ABCD
    MOVE.B  (A0), D2        ; D2 = $EF
    ILLEGAL

DATA:
    DC.L    $12345678
    DC.W    $ABCD
    DC.B    $EF
```

##### Test 3: Conditional Branches
```assembly
    MOVEQ   #10, D0
LOOP:
    SUBQ    #1, D0
    BNE     LOOP            ; Loop until D0 = 0
    ILLEGAL
```

Expected: D0 = 0 after 10 iterations

##### Test 4: Subroutines
```assembly
    BSR     FUNC
    ILLEGAL

FUNC:
    MOVEQ   #42, D0
    RTS
```

Expected: D0 = 42, stack properly restored

### 4. Flag Testing

#### Zero Flag (Z)
```assembly
    MOVEQ   #0, D0
    TST.L   D0              ; Should set Z
    MOVEQ   #1, D0
    TST.L   D0              ; Should clear Z
```

#### Negative Flag (N)
```assembly
    MOVEQ   #-1, D0
    TST.L   D0              ; Should set N
    MOVEQ   #1, D0
    TST.L   D0              ; Should clear N
```

#### Carry/Overflow
```assembly
    MOVE.B  #$FF, D0
    ADD.B   #$01, D0        ; Should set C (carry)
    
    MOVE.B  #$7F, D0
    ADD.B   #$01, D0        ; Should set V (overflow)
```

### 5. Addressing Mode Tests

Test each addressing mode with multiple instructions:

```assembly
; Data Register Direct
    MOVE.L  D0, D1

; Address Register Indirect
    MOVE.L  (A0), D0

; Postincrement
    MOVE.L  (A0)+, D0

; Predecrement
    MOVE.L  -(A0), D0

; Displacement
    MOVE.L  16(A0), D0

; Index
    MOVE.L  16(A0,D1.W), D0
    
; Absolute
    MOVE.L  $1000.W, D0
    MOVE.L  $12345678.L, D0

; Immediate
    MOVE.L  #$12345678, D0

; PC Relative
    LEA     DATA(PC), A0
```

### 6. Real-World Software Tests

#### Amiga Kickstart
- Boot Kickstart 1.3, 2.0, or 3.1
- Should reach Workbench insert disk screen
- Verify boot sequence

#### Atari ST TOS
- Load TOS 1.0, 1.04, 1.62
- Should display desktop
- Test file operations

#### Classic Macintosh
- Load System 6 or 7
- Should boot to Finder
- Verify basic operations

#### Games
- Simple games as smoke tests
- Verify graphics, sound, input

### 7. Test Automation Framework

#### Python Test Harness
```python
class M68kTestCase:
    def __init__(self, name, binary, expected_state):
        self.name = name
        self.binary = binary
        self.expected = expected_state
    
    def run(self, emulator):
        emulator.load_binary(self.binary, 0x1000)
        emulator.set_pc(0x1000)
        
        while not emulator.is_halted():
            emulator.step()
        
        return self.verify(emulator)
    
    def verify(self, emulator):
        for reg, value in self.expected.items():
            if emulator.get_register(reg) != value:
                return False
        return True
```

#### Test Suite Runner
```python
def run_test_suite(test_dir):
    results = []
    for test_file in os.listdir(test_dir):
        test = load_test(test_file)
        emulator = M68kEmulator()
        passed = test.run(emulator)
        results.append((test.name, passed))
    
    print_results(results)
```

### 8. Regression Testing

#### Golden Output Capture
```python
def capture_golden_output(test_name):
    emulator = M68kEmulator()
    trace = emulator.run_trace(test_name)
    save_trace(trace, f"{test_name}.golden")

def regression_test(test_name):
    golden = load_trace(f"{test_name}.golden")
    current = run_test(test_name)
    return compare_traces(golden, current)
```

### 9. Performance Benchmarks

#### Instructions Per Second
```python
def benchmark_ips():
    cpu = M68kEmulator()
    start = time.time()
    for _ in range(1_000_000):
        cpu.step()
    elapsed = time.time() - start
    return 1_000_000 / elapsed
```

#### Dhrystone
- Run Dhrystone 2.1 benchmark
- Compare with reference implementation
- Measure DMIPS (Dhrystone MIPS)

### 10. Coverage Analysis

#### Instruction Coverage
Track which instructions have been tested:
```python
covered_instructions = set()

def track_coverage(opcode):
    instruction = decode_instruction(opcode)
    covered_instructions.add(instruction.mnemonic)

# Report
total_instructions = len(all_68020_instructions)
covered = len(covered_instructions)
print(f"Coverage: {covered}/{total_instructions} ({covered/total_instructions*100:.1f}%)")
```

### 11. Debugging Tools

#### Trace Logger
```python
def trace_execution():
    while not cpu.halted:
        state = {
            'pc': cpu.pc,
            'opcode': cpu.read_memory_16(cpu.pc),
            'registers': cpu.get_all_registers(),
            'flags': cpu.get_flags()
        }
        log_state(state)
        cpu.step()
```

#### Disassembler
```python
def disassemble(address, count):
    for _ in range(count):
        opcode = cpu.read_memory_16(address)
        instruction = decode_instruction(opcode)
        print(f"{address:08X}  {opcode:04X}  {instruction}")
        address += instruction.size
```

### 12. Edge Cases to Test

1. **Division by Zero**
   - Should trigger exception vector 5
   - Verify exception handler

2. **Privilege Violations**
   - User mode trying privileged instructions
   - Should trigger exception vector 8

3. **Illegal Instructions**
   - Invalid opcodes
   - Should trigger exception vector 4

4. **Address Errors**
   - Unaligned word/long access (on 68000)
   - Should trigger exception vector 3

5. **Trace Mode**
   - Single-step execution
   - Verify trace exception after each instruction

6. **Overflow Traps**
   - TRAPV after overflow
   - Verify exception handling

### 13. Test Data Sets

#### Instruction Test Binaries
Create test ROMs for each instruction category:
- `test_move.bin` - All MOVE variants
- `test_arithmetic.bin` - ADD, SUB, MUL, DIV
- `test_logic.bin` - AND, OR, EOR, NOT
- `test_shift.bin` - ASL, ASR, LSL, LSR, ROL, ROR
- `test_branch.bin` - All branch instructions
- `test_addressing.bin` - All addressing modes

### 14. Continuous Integration

```yaml
# .github/workflows/test.yml
name: Test Suite
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Build emulator
        run: zig build
      - name: Run tests
        run: python3 test_runner.py
      - name: Check coverage
        run: python3 coverage_report.py
```

### 15. Test Metrics

Track and report:
- **Pass Rate**: Percentage of tests passing
- **Coverage**: Instruction coverage percentage
- **Performance**: Instructions per second
- **Accuracy**: Compared to reference emulator
- **Compatibility**: Software that runs correctly

## Quick Start Testing

### Minimal Test
```python
from m68k_emu import M68k

def quick_test():
    cpu = M68k()
    
    # Write NOP instruction
    cpu.write_memory_16(0, 0x4E71)
    
    # Execute
    cycles = cpu.step()
    
    # Verify
    assert cpu.get_pc() == 2
    assert cycles == 4
    print("✓ Basic test passed")

quick_test()
```

### Run All Tests
```bash
python3 test_runner.py --all
python3 test_runner.py --category arithmetic
python3 test_runner.py --single test_move_byte
```
