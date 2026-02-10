# 68020 Emulator - Python Usage Examples

## Installation

```bash
# Build the library
cd m68020-emu
zig-windows-x86_64-0.13.0/zig.exe build

# The DLL will be in zig-out/lib/m68020-emu.dll
```

## Basic Usage

### Example 1: Simple Execution

```python
import ctypes

# Load the emulator library
lib = ctypes.CDLL('./zig-out/lib/m68020-emu.dll')

# Define function signatures
lib.m68k_create.restype = ctypes.c_void_p
lib.m68k_destroy.argtypes = [ctypes.c_void_p]
lib.m68k_reset.argtypes = [ctypes.c_void_p]
lib.m68k_step.argtypes = [ctypes.c_void_p]
lib.m68k_step.restype = ctypes.c_int

# Create CPU instance
cpu = lib.m68k_create()

# Reset CPU
lib.m68k_reset(cpu)

# Execute one instruction
cycles = lib.m68k_step(cpu)
print(f"Executed in {cycles} cycles")

# Cleanup
lib.m68k_destroy(cpu)
```

### Example 2: Memory Operations

```python
import ctypes

lib = ctypes.CDLL('./zig-out/lib/m68020-emu.dll')

# Setup
lib.m68k_create.restype = ctypes.c_void_p
lib.m68k_write_memory_8.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint8]
lib.m68k_write_memory_16.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint16]
lib.m68k_write_memory_32.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint32]
lib.m68k_read_memory_8.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
lib.m68k_read_memory_8.restype = ctypes.c_uint8

cpu = lib.m68k_create()

# Write to memory
lib.m68k_write_memory_8(cpu, 0x1000, 0x42)
lib.m68k_write_memory_16(cpu, 0x2000, 0x1234)
lib.m68k_write_memory_32(cpu, 0x3000, 0x12345678)

# Read from memory
byte_val = lib.m68k_read_memory_8(cpu, 0x1000)
word_val = lib.m68k_read_memory_16(cpu, 0x2000)
long_val = lib.m68k_read_memory_32(cpu, 0x3000)

print(f"Byte: 0x{byte_val:02X}")
print(f"Word: 0x{word_val:04X}")
print(f"Long: 0x{long_val:08X}")

lib.m68k_destroy(cpu)
```

### Example 3: Register Access

```python
import ctypes

lib = ctypes.CDLL('./zig-out/lib/m68020-emu.dll')

lib.m68k_create.restype = ctypes.c_void_p
lib.m68k_set_reg_d.argtypes = [ctypes.c_void_p, ctypes.c_uint8, ctypes.c_uint32]
lib.m68k_get_reg_d.argtypes = [ctypes.c_void_p, ctypes.c_uint8]
lib.m68k_get_reg_d.restype = ctypes.c_uint32
lib.m68k_set_reg_a.argtypes = [ctypes.c_void_p, ctypes.c_uint8, ctypes.c_uint32]
lib.m68k_get_reg_a.argtypes = [ctypes.c_void_p, ctypes.c_uint8]
lib.m68k_get_reg_a.restype = ctypes.c_uint32

cpu = lib.m68k_create()

# Set data registers
for i in range(8):
    lib.m68k_set_reg_d(cpu, i, i * 0x1111)

# Set address registers
for i in range(7):
    lib.m68k_set_reg_a(cpu, i, 0x10000 + i * 0x1000)

# Read back
print("Data Registers:")
for i in range(8):
    val = lib.m68k_get_reg_d(cpu, i)
    print(f"  D{i}: 0x{val:08X}")

print("\nAddress Registers:")
for i in range(7):
    val = lib.m68k_get_reg_a(cpu, i)
    print(f"  A{i}: 0x{val:08X}")

lib.m68k_destroy(cpu)
```

### Example 4: Program Counter Control

```python
import ctypes

lib = ctypes.CDLL('./zig-out/lib/m68020-emu.dll')

lib.m68k_create.restype = ctypes.c_void_p
lib.m68k_set_pc.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
lib.m68k_get_pc.argtypes = [ctypes.c_void_p]
lib.m68k_get_pc.restype = ctypes.c_uint32

cpu = lib.m68k_create()

# Set program counter
lib.m68k_set_pc(cpu, 0x1000)

# Read it back
pc = lib.m68k_get_pc(cpu)
print(f"PC: 0x{pc:08X}")

lib.m68k_destroy(cpu)
```

### Example 5: Load and Execute Binary

```python
import ctypes

def load_binary(cpu, lib, filepath, address):
    """Load a binary file into emulator memory"""
    with open(filepath, 'rb') as f:
        data = f.read()
    
    for i, byte in enumerate(data):
        lib.m68k_write_memory_8(cpu, address + i, byte)

# Setup
lib = ctypes.CDLL('./zig-out/lib/m68020-emu.dll')
lib.m68k_create.restype = ctypes.c_void_p
lib.m68k_write_memory_8.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint8]
lib.m68k_set_pc.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
lib.m68k_step.argtypes = [ctypes.c_void_p]
lib.m68k_step.restype = ctypes.c_int

cpu = lib.m68k_create()

# Load program
load_binary(cpu, lib, 'test.bin', 0x1000)

# Set PC to start of program
lib.m68k_set_pc(cpu, 0x1000)

# Execute 100 instructions
for i in range(100):
    cycles = lib.m68k_step(cpu)
    if cycles < 0:
        print(f"Error at instruction {i}")
        break

lib.m68k_destroy(cpu)
```

### Example 6: Python Wrapper Class

```python
import ctypes

class M68020:
    def __init__(self, lib_path='./zig-out/lib/m68020-emu.dll'):
        self.lib = ctypes.CDLL(lib_path)
        
        # Setup function signatures
        self.lib.m68k_create.restype = ctypes.c_void_p
        self.lib.m68k_destroy.argtypes = [ctypes.c_void_p]
        self.lib.m68k_reset.argtypes = [ctypes.c_void_p]
        self.lib.m68k_step.argtypes = [ctypes.c_void_p]
        self.lib.m68k_step.restype = ctypes.c_int
        self.lib.m68k_execute.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
        self.lib.m68k_execute.restype = ctypes.c_int
        
        self.lib.m68k_set_pc.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
        self.lib.m68k_get_pc.argtypes = [ctypes.c_void_p]
        self.lib.m68k_get_pc.restype = ctypes.c_uint32
        
        self.lib.m68k_set_reg_d.argtypes = [ctypes.c_void_p, ctypes.c_uint8, ctypes.c_uint32]
        self.lib.m68k_get_reg_d.argtypes = [ctypes.c_void_p, ctypes.c_uint8]
        self.lib.m68k_get_reg_d.restype = ctypes.c_uint32
        
        self.lib.m68k_set_reg_a.argtypes = [ctypes.c_void_p, ctypes.c_uint8, ctypes.c_uint32]
        self.lib.m68k_get_reg_a.argtypes = [ctypes.c_void_p, ctypes.c_uint8]
        self.lib.m68k_get_reg_a.restype = ctypes.c_uint32
        
        self.lib.m68k_write_memory_8.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint8]
        self.lib.m68k_write_memory_16.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint16]
        self.lib.m68k_write_memory_32.argtypes = [ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint32]
        
        self.lib.m68k_read_memory_8.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
        self.lib.m68k_read_memory_8.restype = ctypes.c_uint8
        self.lib.m68k_read_memory_16.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
        self.lib.m68k_read_memory_16.restype = ctypes.c_uint16
        self.lib.m68k_read_memory_32.argtypes = [ctypes.c_void_p, ctypes.c_uint32]
        self.lib.m68k_read_memory_32.restype = ctypes.c_uint32
        
        self.cpu = self.lib.m68k_create()
        if not self.cpu:
            raise RuntimeError("Failed to create M68k instance")
    
    def __del__(self):
        if hasattr(self, 'cpu') and self.cpu:
            self.lib.m68k_destroy(self.cpu)
    
    def reset(self):
        self.lib.m68k_reset(self.cpu)
    
    def step(self):
        """Execute one instruction. Returns cycles used or -1 on error."""
        return self.lib.m68k_step(self.cpu)
    
    def execute(self, cycles):
        """Execute instructions for approximately N cycles."""
        return self.lib.m68k_execute(self.cpu, cycles)
    
    @property
    def pc(self):
        return self.lib.m68k_get_pc(self.cpu)
    
    @pc.setter
    def pc(self, value):
        self.lib.m68k_set_pc(self.cpu, value)
    
    def get_d(self, reg):
        """Get data register D0-D7"""
        if 0 <= reg <= 7:
            return self.lib.m68k_get_reg_d(self.cpu, reg)
        raise ValueError("Register must be 0-7")
    
    def set_d(self, reg, value):
        """Set data register D0-D7"""
        if 0 <= reg <= 7:
            self.lib.m68k_set_reg_d(self.cpu, reg, value & 0xFFFFFFFF)
        else:
            raise ValueError("Register must be 0-7")
    
    def get_a(self, reg):
        """Get address register A0-A7"""
        if 0 <= reg <= 7:
            return self.lib.m68k_get_reg_a(self.cpu, reg)
        raise ValueError("Register must be 0-7")
    
    def set_a(self, reg, value):
        """Set address register A0-A7"""
        if 0 <= reg <= 7:
            self.lib.m68k_set_reg_a(self.cpu, reg, value & 0xFFFFFFFF)
        else:
            raise ValueError("Register must be 0-7")
    
    def read8(self, addr):
        return self.lib.m68k_read_memory_8(self.cpu, addr)
    
    def read16(self, addr):
        return self.lib.m68k_read_memory_16(self.cpu, addr)
    
    def read32(self, addr):
        return self.lib.m68k_read_memory_32(self.cpu, addr)
    
    def write8(self, addr, value):
        self.lib.m68k_write_memory_8(self.cpu, addr, value & 0xFF)
    
    def write16(self, addr, value):
        self.lib.m68k_write_memory_16(self.cpu, addr, value & 0xFFFF)
    
    def write32(self, addr, value):
        self.lib.m68k_write_memory_32(self.cpu, addr, value & 0xFFFFFFFF)
    
    def load_binary(self, filepath, address):
        """Load binary file into memory"""
        with open(filepath, 'rb') as f:
            data = f.read()
        for i, byte in enumerate(data):
            self.write8(address + i, byte)
    
    def dump_registers(self):
        """Print all registers"""
        print("Data Registers:")
        for i in range(8):
            print(f"  D{i}: 0x{self.get_d(i):08X}")
        print("\nAddress Registers:")
        for i in range(8):
            print(f"  A{i}: 0x{self.get_a(i):08X}")
        print(f"\nPC: 0x{self.pc:08X}")

# Usage
if __name__ == "__main__":
    cpu = M68020()
    
    # Set some registers
    cpu.set_d(0, 0x12345678)
    cpu.set_a(0, 0x00001000)
    cpu.pc = 0x1000
    
    # Write to memory
    cpu.write32(0x1000, 0x4E714E71)  # Two NOP instructions
    
    # Execute
    cpu.step()
    cpu.step()
    
    # Dump state
    cpu.dump_registers()
```

### Example 7: Testing Framework

```python
from m68020_wrapper import M68020

class TestCase:
    def __init__(self, name, setup, verify):
        self.name = name
        self.setup = setup
        self.verify = verify
    
    def run(self):
        cpu = M68020()
        self.setup(cpu)
        
        # Execute until error or max steps
        for _ in range(1000):
            cycles = cpu.step()
            if cycles < 0:
                break
        
        return self.verify(cpu)

# Test: MOVEQ
def test_moveq():
    def setup(cpu):
        # MOVEQ #42, D0 = 0x7029
        cpu.write16(0x1000, 0x702A)
        cpu.pc = 0x1000
    
    def verify(cpu):
        return cpu.get_d(0) == 42 and cpu.pc == 0x1002
    
    test = TestCase("MOVEQ", setup, verify)
    result = test.run()
    print(f"Test MOVEQ: {'PASS' if result else 'FAIL'}")

test_moveq()
```

## Advanced Usage

### Debugging Helper

```python
class M68020Debugger(M68020):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.breakpoints = set()
        self.trace = []
    
    def add_breakpoint(self, addr):
        self.breakpoints.add(addr)
    
    def step_debug(self):
        pc = self.pc
        opcode = self.read16(pc)
        
        # Log execution
        self.trace.append({
            'pc': pc,
            'opcode': opcode,
            'd': [self.get_d(i) for i in range(8)],
            'a': [self.get_a(i) for i in range(8)]
        })
        
        # Execute
        cycles = self.step()
        
        # Check breakpoint
        if self.pc in self.breakpoints:
            print(f"Breakpoint hit at 0x{self.pc:08X}")
            self.dump_registers()
            return None
        
        return cycles
    
    def dump_trace(self):
        for entry in self.trace[-10:]:
            print(f"PC: 0x{entry['pc']:08X}  Opcode: 0x{entry['opcode']:04X}")
```

This provides a comprehensive set of examples for using the 68020 emulator from Python!
