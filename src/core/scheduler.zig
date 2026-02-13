const std = @import("std");

/// A prioritized event in the emulator timeline.
pub const Event = struct {
    callback: *const fn (ctx: ?*anyopaque, current_cycles: u64) void,
    ctx: ?*anyopaque,
    target_cycles: u64,
    description: []const u8 = "unknown",
};

/// Central Event Scheduler for cycle-accurate timing.
/// Uses a simple sorted list for event management.
pub const Scheduler = struct {
    events: std.ArrayList(Event),
    current_cycles: u64 = 0,

    pub fn init(allocator: std.mem.Allocator) Scheduler {
        return .{
            .events = std.ArrayList(Event).init(allocator),
            .current_cycles = 0,
        };
    }

    pub fn deinit(self: *Scheduler) void {
        self.events.deinit();
    }

    /// Schedule a new event at relative 'delay' cycles from now.
    pub fn schedule(self: *Scheduler, delay: u64, callback: *const fn (ctx: ?*anyopaque, cycles: u64) void, ctx: ?*anyopaque, desc: []const u8) !void {
        const target = self.current_cycles + delay;
        const new_event = Event{
            .callback = callback,
            .ctx = ctx,
            .target_cycles = target,
            .description = desc,
        };

        // Find insertion point to keep events sorted by target_cycles
        var insert_idx: usize = 0;
        for (self.events.items, 0..) |event, i| {
            if (event.target_cycles > target) {
                insert_idx = i;
                break;
            }
            insert_idx = i + 1;
        }

        try self.events.insert(insert_idx, new_event);
    }

    /// Advance time and run all expired events.
    pub fn tick(self: *Scheduler, delta_cycles: u32) void {
        self.current_cycles += delta_cycles;
        
        while (self.events.items.len > 0) {
            const next_event = self.events.items[0];
            if (next_event.target_cycles <= self.current_cycles) {
                // Remove first and call
                _ = self.events.orderedRemove(0);
                next_event.callback(next_event.ctx, self.current_cycles);
            } else {
                break;
            }
        }
    }

    /// Get cycles until the next event fires.
    pub fn cyclesToNextEvent(self: *const Scheduler) ?u64 {
        if (self.events.items.len == 0) return null;
        const target = self.events.items[0].target_cycles;
        if (target <= self.current_cycles) return 0;
        return target - self.current_cycles;
    }
};
