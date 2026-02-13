const std = @import("std");

/// NCR 5380 SCSI Controller
/// Used in Macintosh for hard disk and CD-ROM access.
pub const Scsi5380 = struct {
    // Registers
    cur_data: u8 = 0,    // 0: Current SCSI data
    out_data: u8 = 0,    // 0: Output data (Write)
    ini_cmd: u8 = 0,     // 1: Initiator command
    sel_ena: u8 = 0,     // 1: Select enable (Write)
    mode: u8 = 0,        // 2: Mode register
    tar_cmd: u8 = 0,     // 3: Target command
    cur_stat: u8 = 0,    // 4: Current status (Read)
    sel_out: u8 = 0,     // 4: Select output (Write)
    bus_stat: u8 = 0,    // 5: Bus and status (Read)
    start_send: u8 = 0,  // 5: Start send (Write)
    in_data: u8 = 0,     // 6: Input data (Read)
    start_recv: u8 = 0,  // 6: Start receive (Write)
    reset_par: u8 = 0,   // 7: Reset parity (Read)
    start_recv_i: u8 = 0,// 7: Start receive (Write)
    
    // Internal state
    irq_active: bool = false,
    drq_active: bool = false,

    pub fn init() Scsi5380 {
        return .{};
    }

    pub fn read(self: *Scsi5380, addr: u3) u8 {
        return switch (addr) {
            0 => self.cur_data,
            1 => self.ini_cmd,
            2 => self.mode,
            3 => self.tar_cmd,
            4 => self.cur_stat,
            5 => self.bus_stat,
            6 => self.in_data,
            7 => self.reset_par,
        };
    }

    pub fn write(self: *Scsi5380, addr: u3, value: u8) void {
        switch (addr) {
            0 => self.out_data = value,
            1 => self.sel_ena = value,
            2 => self.mode = value,
            3 => self.tar_cmd = value,
            4 => self.sel_out = value,
            5 => self.start_send = value,
            6 => self.start_recv = value,
            7 => self.start_recv_i = value,
        }
    }
};
