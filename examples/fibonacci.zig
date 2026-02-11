const std = @import("std");
const cpu_module = @import("cpu");
const M68k = cpu_module.M68k;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();
    
    var cpu = M68k.init(allocator);
    defer cpu.deinit();
    
    std.debug.print("=== M68020 Fibonacci Calculator ===\n", .{});
    
    // 피보나치 계산 프로그램 (어셈블리를 기계어로 변환)
    // D0 = n (입력)
    // D1 = fib(n-2)
    // D2 = fib(n-1)
    // D3 = 결과
    
    const program = [_]u16{
        0x7209,         // MOVEQ #9, D1       ; n = 9
        0x7401,         // MOVEQ #1, D2       ; fib(n-1) = 1  
        0x7601,         // MOVEQ #1, D3       ; fib(n) = 1
        // loop: (0x1006)
        0x2002,         // MOVE.L D2, D0      ; temp = fib(n-1)
        0x2403,         // MOVE.L D3, D2      ; fib(n-1) = fib(n)
        0xD680,         // ADD.L D0, D3       ; fib(n) += temp
        0x5341,         // SUBQ.W #1, D1      ; counter--
        0x66F6,         // BNE loop           ; if (counter != 0) goto loop
        0x4E71,         // NOP
    };
    
    // 프로그램을 메모리에 로드
    var addr: u32 = 0x1000;
    for (program) |word| {
        try cpu.memory.write16(addr, word);
        addr += 2;
    }
    
    cpu.pc = 0x1000;
    cpu.a[7] = 0x10000; // 스택 포인터 초기화 (중요!)
    
    // 프로그램 실행
    var cycles: u64 = 0;
    var instructions: u32 = 0;
    
    while (cpu.pc < 0x1000 + program.len * 2) : (instructions += 1) {
        const step_cycles = cpu.step() catch |err| {
            std.debug.print("Error at PC=0x{X}: {}\n", .{cpu.pc, err});
            break;
        };
        cycles += step_cycles;
        
        if (instructions > 1000) {
            std.debug.print("Too many instructions, stopping\n", .{});
            break;
        }
    }
    
    std.debug.print("\n결과:\n", .{});
    std.debug.print("  Fibonacci(10) = {}\n", .{cpu.d[3]});
    std.debug.print("  실행된 명령어: {}\n", .{instructions});
    std.debug.print("  총 사이클: {}\n", .{cycles});
    std.debug.print("\n레지스터 상태:\n", .{});
    std.debug.print("  D0={X:0>8}  D1={X:0>8}  D2={X:0>8}  D3={X:0>8}\n", .{cpu.d[0], cpu.d[1], cpu.d[2], cpu.d[3]});
}
