const cpu = @import("../cpu.zig");

pub const IrqRequest = struct {
    pending: bool = false,
    vector: ?u8 = null,
};

pub const Pic = struct {
    requests: [8]IrqRequest = [_]IrqRequest{.{}} ** 8, // level 0..7 (0 unused)

    pub fn init() Pic {
        return .{};
    }

    pub fn raise(self: *Pic, level: u3, vector: ?u8) void {
        if (level == 0) return;
        self.requests[level].pending = true;
        if (vector) |v| self.requests[level].vector = v;
    }

    pub fn clear(self: *Pic, level: u3) void {
        if (level == 0) return;
        self.requests[level] = .{};
    }

    pub fn highestPendingLevel(self: *const Pic) u3 {
        var level: u3 = 7;
        while (level > 0) : (level -= 1) {
            if (self.requests[level].pending) return level;
        }
        return 0;
    }

    pub fn deliver(self: *Pic, m68k: *cpu.M68k) bool {
        const level = self.highestPendingLevel();
        if (level == 0) return false;
        const req = self.requests[level];
        self.clear(level);
        if (req.vector) |v| {
            m68k.setInterruptVector(level, v);
        } else {
            m68k.setInterruptLevel(level);
        }
        return true;
    }
};

