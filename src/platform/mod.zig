const std = @import("std");
const cpu = @import("../cpu.zig");
pub const Pic = @import("pic.zig").Pic;
pub const Timer = @import("timer.zig").Timer;
pub const UartStub = @import("uart_stub.zig").UartStub;

pub const Platform = struct {
    pic: Pic,
    timer: Timer,
    uart: UartStub,

    pub fn init() Platform {
        return .{
            .pic = Pic.init(),
            .timer = Timer.init(20, 2, null), // L2 autovector
            .uart = UartStub.init(3, null), // L3 autovector
        };
    }

    pub fn deinit(self: *Platform, allocator: std.mem.Allocator) void {
        self.uart.deinit(allocator);
    }

    pub fn onCpuStep(self: *Platform, m68k: *cpu.M68k, cycles_used: u32) void {
        _ = self.timer.tick(cycles_used, &self.pic);
        _ = self.pic.deliver(m68k);
    }
};

test "platform timer drives periodic IRQ and CPU handler roundtrip" {
    const allocator = std.testing.allocator;
    var m68k = cpu.M68k.init(allocator);
    defer m68k.deinit();
    var platform = Platform.init();
    defer platform.deinit(allocator);

    // Main loop: BRA.S -2 (self loop) at 0x1000.
    try m68k.memory.write16(0x1000, 0x60FE);
    // Timer IRQ level 2 autovector handler (vector 26): ADDQ.L #1,D7; RTE.
    try m68k.memory.write32(m68k.getExceptionVector(26), 0x2000);
    try m68k.memory.write16(0x2000, 0x5287); // ADDQ.L #1,D7
    try m68k.memory.write16(0x2002, 0x4E73); // RTE

    m68k.pc = 0x1000;
    m68k.a[7] = 0x4000;
    m68k.setSR(0x2000); // supervisor, IPL=0

    var i: usize = 0;
    while (i < 80) : (i += 1) {
        const used = try m68k.step();
        platform.onCpuStep(&m68k, used);
    }

    try std.testing.expect(m68k.d[7] >= 2);
    try std.testing.expectEqual(@as(u32, 0x1000), m68k.pc);
}
