const std = @import("std");
const scsi_device = @import("scsi_device.zig");
const ScsiDevice = scsi_device.ScsiDevice;
const ScsiStatus = scsi_device.ScsiStatus;

/// Simple SCSI Disk Emulation
pub const ScsiDisk = struct {
    allocator: std.mem.Allocator,
    id: u3,
    data_buffer: []u8,
    data_len: usize = 0,
    data_ptr: usize = 0,

    pub fn init(allocator: std.mem.Allocator, id: u3) !*ScsiDisk {
        const disk = try allocator.create(ScsiDisk);
        disk.* = .{
            .allocator = allocator,
            .id = id,
            .data_buffer = try allocator.alloc(u8, 1024), // Buffer for small transfers
        };
        return disk;
    }

    pub fn deinit(self: *ScsiDisk) void {
        self.allocator.free(self.data_buffer);
        self.allocator.destroy(self);
    }

    pub fn device(self: *ScsiDisk) ScsiDevice {
        return .{
            .ptr = self,
            .vtable = &.{
                .executeCommand = executeCommand,
                .readData = readData,
                .writeData = writeData,
                .reset = reset,
            },
        };
    }

    fn executeCommand(ctx: *anyopaque, cdb: []const u8, status: *u8) usize {
        var self: *ScsiDisk = @ptrCast(@alignCast(ctx));
        const opcode = cdb[0];
        self.data_ptr = 0;
        self.data_len = 0;
        status.* = @intFromEnum(ScsiStatus.Good);

        switch (opcode) {
            0x00 => { // TEST UNIT READY
                return 0;
            },
            0x12 => { // INQUIRY
                const alloc_len = cdb[4];
                const inquiry_data = [_]u8{
                    0x00, // Direct Access Device (HDD)
                    0x00, // Removable: No
                    0x02, // SCSI-2 compliance
                    0x02, // Response format
                    31,   // Additional length
                    0, 0, 0,
                    'A', 'P', 'P', 'L', 'E', ' ', ' ', ' ', // Vendor
                    'H', 'A', 'R', 'D', 'D', 'I', 'S', 'K', // Product
                    ' ', ' ', ' ', ' ', '1', '.', '0', '0', // Revision
                };
                self.data_len = @min(alloc_len, inquiry_data.len);
                @memcpy(self.data_buffer[0..self.data_len], inquiry_data[0..self.data_len]);
                return self.data_len;
            },
            else => {
                // Unknown command
                status.* = @intFromEnum(ScsiStatus.CheckCondition);
                return 0;
            }
        }
    }

    fn readData(ctx: *anyopaque, buffer: []u8) usize {
        var self: *ScsiDisk = @ptrCast(@alignCast(ctx));
        const remain = self.data_len - self.data_ptr;
        const count = @min(remain, buffer.len);
        if (count > 0) {
            @memcpy(buffer[0..count], self.data_buffer[self.data_ptr .. self.data_ptr + count]);
            self.data_ptr += count;
        }
        return count;
    }

    fn writeData(_: *anyopaque, _: []const u8) void {
        // TODO: Implement WRITE
    }

    fn reset(ctx: *anyopaque) void {
        var self: *ScsiDisk = @ptrCast(@alignCast(ctx));
        self.data_ptr = 0;
        self.data_len = 0;
    }
};
