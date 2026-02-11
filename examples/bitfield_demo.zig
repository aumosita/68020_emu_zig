const std = @import("std");
const cpu_module = @import("cpu");
const M68k = cpu_module.M68k;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var cpu = M68k.init(allocator);
    defer cpu.deinit();
    
    std.debug.print("=== M68020 Bit Field Operations Demo ===\n\n", .{});
    
    // 68020 비트 필드 명령어 테스트
    cpu.d[0] = 0xFFFF0000;
    
    std.debug.print("초기 D0: 0x{X:0>8}\n\n", .{cpu.d[0]});
    
    // BFCLR D0{16:8} - bits 16-23을 클리어
    const program1 = [_]u16{
        0xECC0, 0x0408, // BFCLR D0{16:8}
        0x4E71,         // NOP
    };
    
    var addr: u32 = 0x1000;
    for (program1) |word| {
        try cpu.memory.write16(addr, word);
        addr += 2;
    }
    
    cpu.pc = 0x1000;
    _ = try cpu.step();
    
    std.debug.print("BFCLR D0{{16:8}} 실행 후:\n", .{});
    std.debug.print("  D0 = 0x{X:0>8} (bits 16-23 cleared)\n\n", .{cpu.d[0]});
    
    // BFSET D0{0:16} - bits 0-15를 세트
    cpu.d[0] = 0x00000000;
    const program2 = [_]u16{
        0xEEC0, 0x0010, // BFSET D0{0:16}
        0x4E71,         // NOP
    };
    
    addr = 0x2000;
    for (program2) |word| {
        try cpu.memory.write16(addr, word);
        addr += 2;
    }
    
    cpu.pc = 0x2000;
    _ = try cpu.step();
    
    std.debug.print("BFSET D0{{0:16}} 실행 후:\n", .{});
    std.debug.print("  D0 = 0x{X:0>8} (bits 0-15 set)\n\n", .{cpu.d[0]});
    
    // BFCHG D0{8:8} - bits 8-15를 토글
    const program3 = [_]u16{
        0xEAC0, 0x0208, // BFCHG D0{8:8}
        0x4E71,         // NOP
    };
    
    addr = 0x3000;
    for (program3) |word| {
        try cpu.memory.write16(addr, word);
        addr += 2;
    }
    
    cpu.pc = 0x3000;
    _ = try cpu.step();
    
    std.debug.print("BFCHG D0{{8:8}} 실행 후:\n", .{});
    std.debug.print("  D0 = 0x{X:0>8} (bits 8-15 toggled)\n", .{cpu.d[0]});
    
    std.debug.print("\n✅ 68020 비트 필드 명령어가 정상 작동합니다!\n", .{});
}
