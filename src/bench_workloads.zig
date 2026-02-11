const std = @import("std");
const cpu = @import("cpu.zig");
const platform_mod = @import("platform/mod.zig");

const BenchResult = struct {
    name: []const u8,
    steps: usize,
    cpu_cycles: u64,
    elapsed_ns: u64,
};

fn runSequentialNop(allocator: std.mem.Allocator, steps: usize) !BenchResult {
    var m68k = cpu.M68k.initWithConfig(allocator, .{ .size = 2 * 1024 * 1024 });
    defer m68k.deinit();

    const base: u32 = 0x1000;
    var addr = base;
    while (addr < base + 0x20000) : (addr += 2) {
        try m68k.memory.write16(addr, 0x4E71); // NOP
    }
    m68k.pc = base;

    var timer = try std.time.Timer.start();
    var i: usize = 0;
    while (i < steps) : (i += 1) {
        _ = try m68k.step();
    }
    return .{
        .name = "sequential_nop",
        .steps = steps,
        .cpu_cycles = m68k.cycles,
        .elapsed_ns = timer.read(),
    };
}

fn runTightBranchLoop(allocator: std.mem.Allocator, steps: usize) !BenchResult {
    var m68k = cpu.M68k.init(allocator);
    defer m68k.deinit();

    try m68k.memory.write16(0x2000, 0x60FE); // BRA.S -2
    m68k.pc = 0x2000;

    var timer = try std.time.Timer.start();
    var i: usize = 0;
    while (i < steps) : (i += 1) {
        _ = try m68k.step();
    }
    return .{
        .name = "tight_branch_loop",
        .steps = steps,
        .cpu_cycles = m68k.cycles,
        .elapsed_ns = timer.read(),
    };
}

fn runPlatformIrqLoop(allocator: std.mem.Allocator, steps: usize) !BenchResult {
    var m68k = cpu.M68k.init(allocator);
    defer m68k.deinit();
    var platform = platform_mod.Platform.init();
    defer platform.deinit(allocator);

    try m68k.memory.write16(0x3000, 0x60FE); // BRA.S -2
    try m68k.memory.write32(m68k.getExceptionVector(26), 0x4000); // L2 autovector
    try m68k.memory.write16(0x4000, 0x5287); // ADDQ.L #1,D7
    try m68k.memory.write16(0x4002, 0x4E73); // RTE

    m68k.pc = 0x3000;
    m68k.a[7] = 0x7000;
    m68k.setSR(0x2000);

    var timer = try std.time.Timer.start();
    var i: usize = 0;
    while (i < steps) : (i += 1) {
        const used = try m68k.step();
        platform.onCpuStep(&m68k, used);
    }
    return .{
        .name = "platform_irq_loop",
        .steps = steps,
        .cpu_cycles = m68k.cycles,
        .elapsed_ns = timer.read(),
    };
}

fn printResult(writer: anytype, result: BenchResult) !void {
    const secs = @as(f64, @floatFromInt(result.elapsed_ns)) / 1_000_000_000.0;
    const inst = @as(f64, @floatFromInt(result.steps));
    const cycles = @as(f64, @floatFromInt(result.cpu_cycles));
    const mips = if (secs > 0) inst / secs / 1_000_000.0 else 0.0;
    const cpi = if (inst > 0) cycles / inst else 0.0;
    try writer.print(
        "{s}: steps={d} cycles={d} elapsed_ns={d} mips={d:.3} cpi={d:.3}\n",
        .{ result.name, result.steps, result.cpu_cycles, result.elapsed_ns, mips, cpi },
    );
}

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    const stdout = std.io.getStdOut().writer();
    const steps: usize = 200_000;

    try stdout.print("68020 bench workloads (steps={d})\n", .{steps});
    const r1 = try runSequentialNop(allocator, steps);
    try printResult(stdout, r1);

    const r2 = try runTightBranchLoop(allocator, steps);
    try printResult(stdout, r2);

    const r3 = try runPlatformIrqLoop(allocator, steps);
    try printResult(stdout, r3);
}

