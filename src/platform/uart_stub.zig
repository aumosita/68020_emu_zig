const std = @import("std");
const pic_mod = @import("pic.zig");

pub const UartStub = struct {
    rx_pending: bool = false,
    tx_log: std.ArrayListUnmanaged(u8) = .{},
    irq_level: u3,
    irq_vector: ?u8 = null,

    pub fn init(irq_level: u3, irq_vector: ?u8) UartStub {
        return .{
            .irq_level = irq_level,
            .irq_vector = irq_vector,
        };
    }

    pub fn deinit(self: *UartStub, allocator: std.mem.Allocator) void {
        self.tx_log.deinit(allocator);
    }

    pub fn feedRxByte(self: *UartStub, byte: u8, pic: *pic_mod.Pic) void {
        _ = byte; // Stub: data register model omitted for now.
        self.rx_pending = true;
        pic.raise(self.irq_level, self.irq_vector);
    }

    pub fn clearRxPending(self: *UartStub) void {
        self.rx_pending = false;
    }

    pub fn writeTxByte(self: *UartStub, allocator: std.mem.Allocator, byte: u8) !void {
        try self.tx_log.append(allocator, byte);
    }
};

