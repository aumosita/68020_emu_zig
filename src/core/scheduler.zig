const std = @import("std");
const PriorityQueue = std.PriorityQueue;

pub const EventCallback = *const fn (context: *anyopaque, time: u64) void;

pub const Event = struct {
    time: u64,
    id: u64, // Unique ID to help with cancellation or stable sorting if needed
    callback: EventCallback,
    context: *anyopaque,
};

fn compareEvents(context: void, a: Event, b: Event) std.math.Order {
    _ = context;
    if (a.time < b.time) return .lt;
    if (a.time > b.time) return .gt;
    // Tie-breaker: use ID to maintain FIFO for same-time events
    if (a.id < b.id) return .lt;
    if (a.id > b.id) return .gt;
    return .eq;
}

pub const Scheduler = struct {
    queue: PriorityQueue(Event, void, compareEvents),
    current_time: u64,
    next_id: u64,
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) Scheduler {
        return .{
            .queue = PriorityQueue(Event, void, compareEvents).init(allocator, {}),
            .current_time = 0,
            .next_id = 0,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *Scheduler) void {
        self.queue.deinit();
    }

    pub fn schedule(self: *Scheduler, time: u64, context: *anyopaque, callback: EventCallback) !u64 {
        const id = self.next_id;
        self.next_id += 1;
        try self.queue.add(.{
            .time = time,
            .id = id,
            .callback = callback,
            .context = context,
        });
        return id;
    }

    pub fn nextEventTime(self: *Scheduler) ?u64 {
        const top = self.queue.peek();
        if (top) |event| {
            return event.time;
        }
        return null;
    }

    /// Run events up to and including `end_time`
    pub fn runUntil(self: *Scheduler, end_time: u64) void {
        while (self.queue.peek()) |event| {
            if (event.time > end_time) break;

            // Remove event
            const current = self.queue.remove();

            // Update current time to event time (optional, but good for causality)
            self.current_time = current.time;

            // Execute
            current.callback(current.context, current.time);
        }
        self.current_time = end_time;
    }

    pub fn reset(self: *Scheduler) void {
        // Clear queue
        while (self.queue.removeOrNull()) |_| {}
        self.current_time = 0;
        self.next_id = 0;
    }
};

const Context = struct {
    executed: bool = false,
    exec_time: u64 = 0,

    fn callback(ctx: *anyopaque, time: u64) void {
        var self: *Context = @ptrCast(@alignCast(ctx));
        self.executed = true;
        self.exec_time = time;
    }
};

test "Scheduler Verification" {
    const testing = std.testing;

    var scheduler = Scheduler.init(std.testing.allocator);
    defer scheduler.deinit();

    var ctx1 = Context{};
    var ctx2 = Context{};

    // Schedule out of order
    _ = try scheduler.schedule(200, &ctx2, Context.callback);
    _ = try scheduler.schedule(100, &ctx1, Context.callback);

    // Run to 50 (nothing should happen)
    scheduler.runUntil(50);
    try testing.expectEqual(false, ctx1.executed);
    try testing.expectEqual(false, ctx2.executed);

    // Run to 150 (ctx1 should execute)
    scheduler.runUntil(150);
    try testing.expectEqual(true, ctx1.executed);
    try testing.expectEqual(100, ctx1.exec_time);
    try testing.expectEqual(false, ctx2.executed); // ctx2 still pending

    // Run to 250 (ctx2 should execute)
    scheduler.runUntil(250);
    try testing.expectEqual(true, ctx2.executed);
    try testing.expectEqual(200, ctx2.exec_time);
}
