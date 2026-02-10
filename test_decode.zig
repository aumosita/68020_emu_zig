const std = @import("std");
const decoder = @import("decoder.zig");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    
    // Test ADDQ #4, A0
    const opcode: u16 = 0x5888;
    try stdout.print("Decoding opcode: 0x{X:0>4}\n", .{opcode});
    
    const inst = try decoder.Instruction.decode(opcode);
    
    try stdout.print("Mnemonic: {}\n", .{inst.mnemonic});
    try stdout.print("Data size: {}\n", .{inst.data_size});
    try stdout.print("Source: {}\n", .{inst.src});
    try stdout.print("Dest: {}\n", .{inst.dst});
    
    // Bit analysis
    const high4 = (opcode >> 12) & 0xF;
    const mode = (opcode >> 3) & 0x7;
    const reg = opcode & 0x7;
    const imm_data = (opcode >> 9) & 0x7;
    const size_bits = (opcode >> 6) & 0x3;
    
    try stdout.print("\nBit analysis:\n", .{});
    try stdout.print("  high4 (15-12): 0x{X} ({})\n", .{high4, high4});
    try stdout.print("  imm_data (11-9): {} (raw: {})\n", .{if (imm_data == 0) @as(u8, 8) else @as(u8, @truncate(imm_data)), imm_data});
    try stdout.print("  size (7-6): {} (0=byte, 1=word, 2=long)\n", .{size_bits});
    try stdout.print("  mode (5-3): {} (0=Dn, 1=An, 2=(An), ...)\n", .{mode});
    try stdout.print("  reg (2-0): {}\n", .{reg});
}
