# 68020 Complete Instruction Set

## Data Movement Instructions

### MOVE - Move Data
**Syntax**: `MOVE.{B|W|L} <src>, <dst>`
**Operation**: dst ← src
**Flags**: N, Z, V(0), C(0), X(-)
**Description**: General-purpose data transfer. Most flexible instruction.

### MOVEA - Move Address
**Syntax**: `MOVEA.{W|L} <src>, An`
**Operation**: An ← src (sign-extended if word)
**Flags**: None
**Description**: Load address register, no flags affected.

### MOVEQ - Move Quick
**Syntax**: `MOVEQ #<data>, Dn`
**Operation**: Dn ← sign-extended 8-bit immediate
**Flags**: N, Z, V(0), C(0), X(-)
**Range**: -128 to +127

### MOVEM - Move Multiple
**Syntax**: `MOVEM.{W|L} <list>, <ea>` or `MOVEM.{W|L} <ea>, <list>`
**Operation**: Save/restore multiple registers
**Example**: `MOVEM.L D0-D7/A0-A6, -(SP)`

### MOVEP - Move Peripheral
**Syntax**: `MOVEP.{W|L} Dn, d(An)` or `MOVEP.{W|L} d(An), Dn`
**Description**: Transfer data to/from 8-bit peripherals at alternate addresses

### LEA - Load Effective Address
**Syntax**: `LEA <ea>, An`
**Operation**: An ← ea
**Flags**: None

### PEA - Push Effective Address
**Syntax**: `PEA <ea>`
**Operation**: -(SP) ← ea

### EXG - Exchange Registers
**Syntax**: `EXG Rx, Ry`
**Operation**: Rx ↔ Ry

### SWAP - Swap Register Halves
**Syntax**: `SWAP Dn`
**Operation**: Dn[31:16] ↔ Dn[15:0]

## Arithmetic Instructions

### ADD - Add
**Syntax**: `ADD.{B|W|L} <src>, <dst>`
**Operation**: dst ← dst + src
**Flags**: X, N, Z, V, C

### ADDA - Add Address
**Syntax**: `ADDA.{W|L} <src>, An`
**Flags**: None

### ADDI - Add Immediate
**Syntax**: `ADDI.{B|W|L} #<data>, <dst>`

### ADDQ - Add Quick
**Syntax**: `ADDQ.{B|W|L} #<1-8>, <dst>`
**Description**: Fast add of small constant

### ADDX - Add Extended
**Syntax**: `ADDX.{B|W|L} Dx, Dy` or `ADDX.{B|W|L} -(Ax), -(Ay)`
**Operation**: dst ← dst + src + X
**Use**: Multi-precision arithmetic

### SUB, SUBA, SUBI, SUBQ, SUBX
Similar to ADD variants but subtract

### MULS - Multiply Signed
**Syntax**: `MULS.W <src>, Dn`
**Operation**: Dn[31:0] ← Dn[15:0] × src[15:0] (signed)
**Result**: 32-bit signed product

### MULU - Multiply Unsigned
**Syntax**: `MULU.W <src>, Dn`
**Operation**: Dn[31:0] ← Dn[15:0] × src[15:0] (unsigned)

### DIVS - Divide Signed
**Syntax**: `DIVS.W <src>, Dn`
**Operation**: 
- Dn[15:0] ← Dn[31:0] ÷ src (quotient)
- Dn[31:16] ← Dn[31:0] mod src (remainder)

### DIVU - Divide Unsigned
**Syntax**: `DIVU.W <src>, Dn`

### NEG - Negate
**Syntax**: `NEG.{B|W|L} <dst>`
**Operation**: dst ← 0 - dst

### NEGX - Negate with Extend
**Syntax**: `NEGX.{B|W|L} <dst>`
**Operation**: dst ← 0 - dst - X

### CLR - Clear
**Syntax**: `CLR.{B|W|L} <dst>`
**Operation**: dst ← 0

### EXT - Sign Extend
**Syntax**: `EXT.W Dn` or `EXT.L Dn`
**Operation**: 
- EXT.W: Dn[15:8] ← Dn[7] (byte to word)
- EXT.L: Dn[31:16] ← Dn[15] (word to long)

### EXTB - Sign Extend Byte (68020)
**Syntax**: `EXTB.L Dn`
**Operation**: Dn[31:8] ← Dn[7] (byte to long)

## Logical Instructions

### AND - Logical AND
**Syntax**: `AND.{B|W|L} <src>, <dst>`
**Operation**: dst ← dst AND src

### ANDI - AND Immediate
**Syntax**: `ANDI.{B|W|L} #<data>, <dst>`

### OR - Logical OR
**Syntax**: `OR.{B|W|L} <src>, <dst>`

### ORI - OR Immediate
**Syntax**: `ORI.{B|W|L} #<data>, <dst>`

### EOR - Exclusive OR
**Syntax**: `EOR.{B|W|L} Dn, <dst>`

### EORI - EOR Immediate
**Syntax**: `EORI.{B|W|L} #<data>, <dst>`

### NOT - Logical Complement
**Syntax**: `NOT.{B|W|L} <dst>`
**Operation**: dst ← ~dst

## Shift and Rotate Instructions

### ASL - Arithmetic Shift Left
**Syntax**: `ASL.{B|W|L} Dx, Dy` or `ASL.{B|W|L} #<1-8>, Dy`
```
C ← [MSB ← ... ← LSB] ← 0
X ←
```

### ASR - Arithmetic Shift Right
```
MSB → [MSB → ... → LSB] → C
              → X
```

### LSL - Logical Shift Left
```
C ← [MSB ← ... ← LSB] ← 0
X ←
```

### LSR - Logical Shift Right
```
0 → [MSB → ... → LSB] → C
              → X
```

### ROL - Rotate Left
```
    ┌─────────────────┐
C ← └ [MSB ← ... ← LSB] ←
```

### ROR - Rotate Right
```
┌─────────────────┐
→ [MSB → ... → LSB] ┘ → C
```

### ROXL - Rotate Left through Extend
```
C ← X ← [MSB ← ... ← LSB] ←
  ↑________________________|
```

### ROXR - Rotate Right through Extend
```
  → [MSB → ... → LSB] → X → C
  |________________________↓
```

## Bit Manipulation

### BCHG - Test Bit and Change
**Syntax**: `BCHG Dn, <dst>` or `BCHG #<bit>, <dst>`
**Operation**: Z ← ~bit; bit ← ~bit

### BCLR - Test Bit and Clear
**Operation**: Z ← ~bit; bit ← 0

### BSET - Test Bit and Set
**Operation**: Z ← ~bit; bit ← 1

### BTST - Test Bit
**Operation**: Z ← ~bit

## BCD Instructions

### ABCD - Add BCD with Extend
**Syntax**: `ABCD Dx, Dy` or `ABCD -(Ax), -(Ay)`

### SBCD - Subtract BCD with Extend
**Syntax**: `SBCD Dx, Dy` or `SBCD -(Ax), -(Ay)`

### NBCD - Negate BCD
**Syntax**: `NBCD <dst>`

## Program Control

### BRA - Branch Always
**Syntax**: `BRA <label>` or `BRA.S <label>`
**Range**: .S = -128 to +126, .W = -32K to +32K

### BSR - Branch to Subroutine
**Syntax**: `BSR <label>`
**Operation**: -(SP) ← PC; PC ← PC + displacement

### Bcc - Branch Conditionally
| Mnemonic | Condition | Test |
|----------|-----------|------|
| BHI | Higher | C̄·Z̄ |
| BLS | Lower or Same | C+Z |
| BCC/BHS | Carry Clear | C̄ |
| BCS/BLO | Carry Set | C |
| BNE | Not Equal | Z̄ |
| BEQ | Equal | Z |
| BVC | Overflow Clear | V̄ |
| BVS | Overflow Set | V |
| BPL | Plus | N̄ |
| BMI | Minus | N |
| BGE | Greater or Equal | N·V+N̄·V̄ |
| BLT | Less Than | N·V̄+N̄·V |
| BGT | Greater Than | N·V·Z̄+N̄·V̄·Z̄ |
| BLE | Less or Equal | Z+N·V̄+N̄·V |

### DBcc - Decrement and Branch
**Syntax**: `DBcc Dn, <label>`
**Operation**:
1. If condition true, continue to next instruction
2. Else: Dn ← Dn - 1; if Dn ≠ -1, branch to label

### Scc - Set Conditionally
**Syntax**: `Scc <dst>`
**Operation**: If condition true, dst ← $FF; else dst ← $00

### JMP - Jump
**Syntax**: `JMP <ea>`
**Operation**: PC ← ea

### JSR - Jump to Subroutine
**Syntax**: `JSR <ea>`
**Operation**: -(SP) ← PC; PC ← ea

### RTS - Return from Subroutine
**Operation**: PC ← (SP)+

### RTR - Return and Restore CCR
**Operation**: CCR ← (SP)+; PC ← (SP)+

### RTE - Return from Exception
**Operation**: SR ← (SP)+; PC ← (SP)+
**Privileged**

### NOP - No Operation
**Operation**: None (PC ← PC + 2)

## System Control

### TRAP - Trap
**Syntax**: `TRAP #<0-15>`
**Operation**: SSP ← SSP - 6; (SSP) ← SR, PC; SR[S] ← 1; PC ← vector

### TRAPV - Trap on Overflow
**Operation**: If V=1, take overflow exception

### CHK - Check Register Against Bounds
**Syntax**: `CHK <src>, Dn`
**Operation**: If Dn < 0 or Dn > src, take CHK exception

### ILLEGAL - Illegal Instruction
**Operation**: Take illegal instruction exception

### RESET - Reset External Devices
**Privileged**

### STOP - Load SR and Stop
**Syntax**: `STOP #<data>`
**Privileged**

## Comparison

### CMP - Compare
**Syntax**: `CMP.{B|W|L} <src>, Dn`
**Operation**: Dn - src (result discarded, flags set)

### CMPA - Compare Address
**Syntax**: `CMPA.{W|L} <src>, An`

### CMPI - Compare Immediate
**Syntax**: `CMPI.{B|W|L} #<data>, <dst>`

### CMPM - Compare Memory
**Syntax**: `CMPM.{B|W|L} (Ax)+, (Ay)+`

### TST - Test
**Syntax**: `TST.{B|W|L} <dst>`
**Operation**: dst - 0 (only flags affected)

## Stack Operations

### LINK - Allocate Stack Frame
**Syntax**: `LINK An, #<displacement>`
**Operation**:
```
SP ← SP - 4
(SP) ← An
An ← SP
SP ← SP + displacement
```

### UNLK - Deallocate Stack Frame
**Syntax**: `UNLK An`
**Operation**:
```
SP ← An
An ← (SP)
SP ← SP + 4
```

## 68020-Specific Instructions

### BFCHG, BFCLR, BFEXTS, BFEXTU, BFFFO, BFINS, BFSET, BFTST
**Bitfield operations**

### CAS, CAS2 - Compare and Swap
**Syntax**: `CAS.{B|W|L} Dc, Du, <ea>`

### CHK2 - Check Register Against Bounds
**Syntax**: `CHK2.{B|W|L} <ea>, Rn`

### CMP2 - Compare Register Against Bounds
**Syntax**: `CMP2.{B|W|L} <ea>, Rn`

### DIVL, DIVSLL - Divide Long
**Syntax**: `DIVL.L <ea>, Dr:Dq` or `DIVL.L <ea>, Dq`
**Operation**: 64÷32 or 32÷32 division

### MULL, MULSL - Multiply to Long
**Syntax**: `MULL.L <ea>, Dl` or `MULL.L <ea>, Dh:Dl`
**Operation**: 32×32→32 or 32×32→64

### PACK, UNPK - Pack/Unpack BCD

### RTM - Return from Module (68020 only, later removed)

### TRAPcc - Trap on Condition
**Syntax**: `TRAPcc` or `TRAPcc #<data>`

## Instruction Format Summary

| Bits 15-12 | Instruction Group |
|------------|-------------------|
| 0000 | Bit manipulation, MOVEP, Immediate |
| 0001 | MOVE Byte |
| 0010 | MOVE Long |
| 0011 | MOVE Word |
| 0100 | Miscellaneous |
| 0101 | ADDQ/SUBQ/Scc/DBcc |
| 0110 | Bcc/BSR/BRA |
| 0111 | MOVEQ |
| 1000 | OR/DIV/SBCD |
| 1001 | SUB/SUBX |
| 1010 | (Unassigned, reserved) |
| 1011 | CMP/EOR |
| 1100 | AND/MUL/ABCD/EXG |
| 1101 | ADD/ADDX |
| 1110 | Shift/Rotate |
| 1111 | (Unassigned, reserved) |

## Cycle Counts (Approximate)

| Instruction Type | Best Case | Typical |
|------------------|-----------|---------|
| Register-register | 2-4 | 4-8 |
| Register-memory | 8-12 | 12-20 |
| Memory-memory | 12-20 | 20-40 |
| Multiply | 27-44 | 40-70 |
| Divide | 44-84 | 80-140 |
| Branch taken | 10 | 10-18 |
| Branch not taken | 8-12 | 8-12 |

**Note**: Actual cycle counts vary based on:
- Addressing mode complexity
- Memory access alignment
- Cache hits/misses
- Bus contention
