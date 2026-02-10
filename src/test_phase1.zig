const std = @import("std");
const cpu = @import("cpu.zig");

pub fn main() !void {
    const stdout = std.io.getStdOut().writer();
    
    try stdout.print("Motorola 68020 에뮬레이터 - Phase 1 명령어 테스트\n", .{});
    try stdout.print("=================================================\n\n", .{});
    
    var m68k = cpu.M68k.init(std.heap.page_allocator);
    defer m68k.deinit();
    
    var passed: u32 = 0;
    var total: u32 = 0;
    
    // Test JMP
    total += 1;
    try stdout.print("테스트 {}: JMP $2000 (무조건 점프)\n", .{total});
    m68k.pc = 0x1000;
    try m68k.memory.write16(0x1000, 0x4EF9); // JMP xxx.L
    try m68k.memory.write32(0x1002, 0x00002000);
    _ = try m68k.step();
    if (m68k.pc == 0x00002000) {
        try stdout.print("  ✓ 통과 (PC=0x{X})\n", .{m68k.pc});
        passed += 1;
    } else {
        try stdout.print("  ✗ 실패 (PC=0x{X})\n", .{m68k.pc});
    }
    
    // Test BSR
    total += 1;
    try stdout.print("\n테스트 {}: BSR +10 (서브루틴 분기)\n", .{total});
    m68k.pc = 0x1000;
    m68k.a[7] = 0x00003000; // 스택 포인터
    try m68k.memory.write16(0x1000, 0x610A); // BSR +10
    _ = try m68k.step();
    
    const return_addr = try m68k.memory.read32(m68k.a[7]);
    if (m68k.pc == 0x0000100C and m68k.a[7] == 0x00002FFC and return_addr == 0x00001002) {
        try stdout.print("  ✓ 통과 (PC=0x{X}, SP=0x{X}, return=0x{X})\n", .{m68k.pc, m68k.a[7], return_addr});
        passed += 1;
    } else {
        try stdout.print("  ✗ 실패 (PC=0x{X}, SP=0x{X}, return=0x{X})\n", .{m68k.pc, m68k.a[7], return_addr});
    }
    
    // Test DBcc (DBRA - always loop)
    total += 1;
    try stdout.print("\n테스트 {}: DBRA D0, -8 (루프 제어)\n", .{total});
    m68k.pc = 0x1000;
    m68k.d[0] = 3; // 루프 3번
    var loop_count: u32 = 0;
    
    // DBRA D0, -8 (0x51C8, displacement -8)
    try m68k.memory.write16(0x1000, 0x51C8); // DBRA D0
    try m68k.memory.write16(0x1002, 0xFFF8); // -8 displacement
    
    while ((m68k.d[0] & 0xFFFF) != 0xFFFF and loop_count < 10) : (loop_count += 1) {
        m68k.pc = 0x1000;
        _ = try m68k.step();
    }
    
    if (loop_count == 4 and m68k.pc == 0x1004) { // 3회 루프 + 1회 종료
        try stdout.print("  ✓ 통과 ({}회 반복 후 종료)\n", .{loop_count});
        passed += 1;
    } else {
        try stdout.print("  ✗ 실패 ({}회 반복, PC=0x{X})\n", .{loop_count, m68k.pc});
    }
    
    // Test Scc (SEQ - Set if Equal)
    total += 1;
    try stdout.print("\n테스트 {}: SEQ D1 (Z=1이면 0xFF)\n", .{total});
    m68k.d[1] = 0x12345678;
    m68k.setFlag(cpu.M68k.FLAG_Z, true); // Z 플래그 설정
    try m68k.memory.write16(0x1000, 0x57C1); // SEQ D1
    m68k.pc = 0x1000;
    _ = try m68k.step();
    
    if ((m68k.d[1] & 0xFF) == 0xFF) {
        try stdout.print("  ✓ 통과 (D1=0x{X}, 하위 바이트=0xFF)\n", .{m68k.d[1]});
        passed += 1;
    } else {
        try stdout.print("  ✗ 실패 (D1=0x{X})\n", .{m68k.d[1]});
    }
    
    // Test Scc (SNE - Set if Not Equal)
    total += 1;
    try stdout.print("\n테스트 {}: SNE D2 (Z=0이면 0xFF)\n", .{total});
    m68k.d[2] = 0xABCDEF00;
    m68k.setFlag(cpu.M68k.FLAG_Z, false); // Z 플래그 클리어
    try m68k.memory.write16(0x1000, 0x56C2); // SNE D2
    m68k.pc = 0x1000;
    _ = try m68k.step();
    
    if ((m68k.d[2] & 0xFF) == 0xFF) {
        try stdout.print("  ✓ 통과 (D2=0x{X}, 하위 바이트=0xFF)\n", .{m68k.d[2]});
        passed += 1;
    } else {
        try stdout.print("  ✗ 실패 (D2=0x{X})\n", .{m68k.d[2]});
    }
    
    // Test Scc false condition
    total += 1;
    try stdout.print("\n테스트 {}: SEQ D3 (Z=0이면 0x00)\n", .{total});
    m68k.d[3] = 0xFFFFFFFF;
    m68k.setFlag(cpu.M68k.FLAG_Z, false); // Z 플래그 클리어
    try m68k.memory.write16(0x1000, 0x57C3); // SEQ D3
    m68k.pc = 0x1000;
    _ = try m68k.step();
    
    if ((m68k.d[3] & 0xFF) == 0x00) {
        try stdout.print("  ✓ 통과 (D3=0x{X}, 하위 바이트=0x00)\n", .{m68k.d[3]});
        passed += 1;
    } else {
        try stdout.print("  ✗ 실패 (D3=0x{X})\n", .{m68k.d[3]});
    }
    
    // Test DBcc with true condition (should not loop)
    total += 1;
    try stdout.print("\n테스트 {}: DBEQ D4 (Z=1이면 루프 안함)\n", .{total});
    m68k.pc = 0x1000;
    m68k.d[4] = 5;
    m68k.setFlag(cpu.M68k.FLAG_Z, true); // 조건 true
    try m68k.memory.write16(0x1000, 0x57C8); // DBEQ D4
    try m68k.memory.write16(0x1002, 0xFFFC); // -4 displacement
    _ = try m68k.step();
    
    if (m68k.d[4] == 5 and m68k.pc == 0x1004) { // 카운터 변경 없음, PC 다음으로
        try stdout.print("  ✓ 통과 (D4 그대로, PC=0x{X})\n", .{m68k.pc});
        passed += 1;
    } else {
        try stdout.print("  ✗ 실패 (D4={}, PC=0x{X})\n", .{m68k.d[4], m68k.pc});
    }
    
    // 요약
    try stdout.print("\n" ++ "=" ** 50 ++ "\n", .{});
    try stdout.print("테스트 결과: {} / {} 통과 ({d:.1}%)\n", .{
        passed, total, @as(f64, @floatFromInt(passed)) / @as(f64, @floatFromInt(total)) * 100.0
    });
    
    if (passed == total) {
        try stdout.print("\n🎉 모든 Phase 1 명령어 테스트 통과!\n", .{});
    } else {
        try stdout.print("\n⚠️  일부 테스트 실패\n", .{});
    }
    
    try stdout.print("\n📊 구현된 Phase 1 명령어:\n", .{});
    try stdout.print("  ✓ JMP - 무조건 점프 (조건 없이 대상 주소로)\n", .{});
    try stdout.print("  ✓ BSR - 서브루틴 분기 (return address push + 분기)\n", .{});
    try stdout.print("  ✓ DBcc - 루프 제어 (감소 & 조건부 분기)\n", .{});
    try stdout.print("  ✓ Scc - 조건부 설정 (조건에 따라 0x00/0xFF)\n", .{});
    
    try stdout.print("\n  기능:\n", .{});
    try stdout.print("    - JMP: JSR과 유사하지만 스택 사용 안함\n", .{});
    try stdout.print("    - BSR: BRA + return address (서브루틴용)\n", .{});
    try stdout.print("    - DBcc: 14가지 조건 + 카운터 감소\n", .{});
    try stdout.print("    - Scc: 14가지 조건 + 바이트 설정\n", .{});
    try stdout.print("    - for/while 루프 구현에 필수적\n", .{});
    
    try stdout.print("\n🎯 총 구현된 명령어: 61개 (57 + 4)\n", .{});
}
