const pic_mod = @import("pic.zig");

pub const Timer = struct {
    period_cycles: u32,
    accum_cycles: u32 = 0,
    irq_level: u3,
    irq_vector: ?u8 = null,

    pub fn init(period_cycles: u32, irq_level: u3, irq_vector: ?u8) Timer {
        return .{
            .period_cycles = period_cycles,
            .irq_level = irq_level,
            .irq_vector = irq_vector,
        };
    }

    pub fn tick(self: *Timer, elapsed_cycles: u32, pic: *pic_mod.Pic) u32 {
        if (self.period_cycles == 0) return 0;
        self.accum_cycles +|= elapsed_cycles;
        var fired: u32 = 0;
        while (self.accum_cycles >= self.period_cycles) {
            self.accum_cycles -= self.period_cycles;
            pic.raise(self.irq_level, self.irq_vector);
            fired += 1;
        }
        return fired;
    }
};

