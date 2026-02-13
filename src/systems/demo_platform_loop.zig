const std = @import("std");
const cpu = @import("cpu.zig");
const platform_mod = @import("platform/mod.zig");

pub fn main() !void {
    const allocator = std.heap.page_allocator;
    var m68k = cpu.M68k.init(allocator);
    defer m68k.deinit();
    var platform = platform_mod.Platform.init();
    defer platform.deinit(allocator);

    // CPU main loop: BRA.S -2 (busy loop).
    try m68k.memory.write16(0x1000, 0x60FE);

    // Timer IRQ level-2 autovector handler: ADDQ.L #1,D7; RTE
    try m68k.memory.write32(m68k.getExceptionVector(26), 0x2000);
    try m68k.memory.write16(0x2000, 0x5287);
    try m68k.memory.write16(0x2002, 0x4E73);

    m68k.pc = 0x1000;
    m68k.a[7] = 0x4000;
    m68k.setSR(0x2000);

    var steps: usize = 0;
    while (steps < 120) : (steps += 1) {
        const used = try m68k.step();
        platform.onCpuStep(&m68k, used);
    }
    var settle: usize = 0;
    while (m68k.pc != 0x1000 and settle < 8) : (settle += 1) {
        const used = try m68k.step();
        platform.onCpuStep(&m68k, used);
    }

    const out = std.io.getStdOut().writer();
    try out.print("platform demo complete: steps={d} irq_count(d7)={d} pc=0x{X} settled_steps={d}\n", .{
        steps, m68k.d[7], m68k.pc, settle,
    });
}
