const std = @import("std");

/// SCSI Device Interface
/// Defines how the SCSI controller interacts with virtual hardware (disks, etc.)
pub const ScsiDevice = struct {
    ptr: *anyopaque,
    vtable: *const VTable,

    pub const VTable = struct {
        /// Process a SCSI command (CDB)
        /// Returns the number of bytes to transfer (Data In/Out phase length)
        executeCommand: *const fn (ctx: *anyopaque, cdb: []const u8, status: *u8) usize,
        
        /// Get Data In (device to initiator)
        readData: *const fn (ctx: *anyopaque, buffer: []u8) usize,
        
        /// Send Data Out (initiator to device)
        writeData: *const fn (ctx: *anyopaque, buffer: []const u8) void,
        
        /// Reset device state
        reset: *const fn (ctx: *anyopaque) void,
    };

    pub fn executeCommand(self: ScsiDevice, cdb: []const u8, status: *u8) usize {
        return self.vtable.executeCommand(self.ptr, cdb, status);
    }

    pub fn readData(self: ScsiDevice, buffer: []u8) usize {
        return self.vtable.readData(self.ptr, buffer);
    }

    pub fn writeData(self: ScsiDevice, buffer: []const u8) void {
        self.vtable.writeData(self.ptr, buffer);
    }

    pub fn reset(self: ScsiDevice) void {
        self.vtable.reset(self.ptr);
    }
};

pub const ScsiStatus = enum(u8) {
    Good = 0x00,
    CheckCondition = 0x02,
    ConditionMet = 0x04,
    Busy = 0x08,
    Intermediate = 0x10,
    IntermediateConditionMet = 0x14,
    ReservationConflict = 0x18,
    CommandTerminated = 0x22,
    QueueFull = 0x28,
};
