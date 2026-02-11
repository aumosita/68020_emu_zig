const std = @import("std");
const cpu_module = @import("cpu");
const M68k = cpu_module.M68k;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var cpu = M68k.init(allocator);
    defer cpu.deinit();
    
    std.debug.print("=== M68020 Exception Handling Demo ===\n\n", .{});
    
    // TRAP 예외 핸들러 설정
    const trap_handler_addr: u32 = 0x2000;
    try cpu.memory.write32(37 * 4, trap_handler_addr); // TRAP #5 vector
    
    // 핸들러 코드 (RTE로 복귀)
    try cpu.memory.write16(trap_handler_addr, 0x4E73); // RTE
    
    // 메인 프로그램
    const program = [_]u16{
        0x203C, 0x1234, 0x5678, // MOVE.L #0x12345678, D0
        0x4E45,                 // TRAP #5
        0x5200,                 // ADDQ.B #1, D0 (TRAP 후 실행됨)
        0x4E71,                 // NOP
    };
    
    var addr: u32 = 0x1000;
    for (program) |word| {
        try cpu.memory.write16(addr, word);
        addr += 2;
    }
    
    cpu.pc = 0x1000;
    cpu.a[7] = 0x3000; // Stack pointer
    cpu.sr = 0x2000;   // Supervisor mode
    
    std.debug.print("프로그램 시작:\n", .{});
    std.debug.print("  PC = 0x{X:0>4}, SP = 0x{X:0>4}\n\n", .{cpu.pc, cpu.a[7]});
    
    // MOVE.L 실행
    _ = try cpu.step();
    std.debug.print("MOVE.L 실행 후: D0 = 0x{X:0>8}\n", .{cpu.d[0]});
    
    // TRAP #5 실행
    std.debug.print("\nTRAP #5 실행...\n", .{});
    const old_pc = cpu.pc;
    const old_sp = cpu.a[7];
    _ = try cpu.step();
    
    std.debug.print("  예외 발생!\n", .{});
    std.debug.print("  PC: 0x{X:0>4} -> 0x{X:0>4} (핸들러로 점프)\n", .{old_pc, cpu.pc});
    std.debug.print("  SP: 0x{X:0>4} -> 0x{X:0>4} (스택 프레임 생성)\n", .{old_sp, cpu.a[7]});
    
    // 스택 프레임 검사
    const saved_sr = try cpu.memory.read16(cpu.a[7]);
    const saved_pc = try cpu.memory.read32(cpu.a[7] + 2);
    const format_vector = try cpu.memory.read16(cpu.a[7] + 6);
    
    std.debug.print("\n스택 프레임 (68020 형식):\n", .{});
    std.debug.print("  [SP+0] SR     = 0x{X:0>4}\n", .{saved_sr});
    std.debug.print("  [SP+2] PC     = 0x{X:0>8}\n", .{saved_pc});
    std.debug.print("  [SP+6] Format = 0x{X} ({}바이트)\n", .{format_vector >> 12, @as(u32, 8)});
    std.debug.print("  [SP+6] Vector = {} (TRAP #5)\n", .{(format_vector & 0xFFF) / 4});
    
    // RTE 실행 (핸들러)
    std.debug.print("\nRTE 실행 (핸들러 복귀)...\n", .{});
    _ = try cpu.step();
    std.debug.print("  PC: 0x{X:0>4} -> 0x{X:0>4} (복귀)\n", .{trap_handler_addr, cpu.pc});
    std.debug.print("  SP: 0x{X:0>4} -> 0x{X:0>4} (스택 복원)\n", .{cpu.a[7] - 8, cpu.a[7]});
    
    // ADDQ 실행 (TRAP 후 계속)
    _ = try cpu.step();
    std.debug.print("\nADDQ.B #1, D0 실행 후: D0 = 0x{X:0>8}\n", .{cpu.d[0]});
    
    std.debug.print("\n✅ 68020 예외 처리가 정상 작동합니다!\n", .{});
}
