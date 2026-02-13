const std = @import("std");
const memory = @import("../core/memory.zig");
const via6522 = @import("../hw/via6522.zig");
const rbv = @import("../hw/rbv.zig");
const video = @import("../hw/video.zig");
const scsi = @import("../hw/scsi.zig");
const adb = @import("../hw/adb.zig");
const rtc = @import("../hw/rtc.zig");
const Scheduler = @import("../core/scheduler.zig").Scheduler;

pub const MacLcSystem = struct {
    via1: via6522.Via6522,
    rbv: rbv.Rbv,
    video: video.Video,
    scsi: scsi.Scsi5380,
    adb: adb.Adb,
    rtc: rtc.Rtc,

    // Scheduler
    scheduler: Scheduler,
    total_cycles: u64 = 0,

    // Memory
    ram: []u8,
    rom: []u8,

    // VBL
    vbl_active: bool = false,

    // Address Mode
    address_mode_32: bool = false,

    const RAM_BASE = 0x000000;
    const ROM_BASE = 0x400000; // Example
    const CYCLES_PER_VBL = 266667; // ~60Hz at 16MHz

    pub fn init(allocator: std.mem.Allocator, ram_size: u32, rom_path: ?[]const u8) !*MacLcSystem {
        const sys = try allocator.create(MacLcSystem);
        sys.via1 = via6522.Via6522.init();
        sys.rbv = rbv.Rbv.init();
        sys.video = try video.Video.init(allocator, 512 * 1024);
        sys.scsi = scsi.Scsi5380.init();
        sys.adb = adb.Adb.init();
        sys.rtc = rtc.Rtc.init();
        sys.scheduler = Scheduler.init(allocator);
        sys.address_mode_32 = false; // Default to 24-bit
        sys.total_cycles = 0;

        // Start VBL
        try sys.rbv.start(&sys.scheduler, 0);

        sys.ram = try allocator.alloc(u8, ram_size);
        @memset(sys.ram, 0);

        if (rom_path) |path| {
            // Load ROM TODO
            _ = path;
            sys.rom = try allocator.alloc(u8, 512 * 1024); // Dummy
            @memset(sys.rom, 0);
        } else {
            sys.rom = try allocator.alloc(u8, 4); // Dummy
            @memset(sys.rom, 0);
        }

        return sys;
    }

    pub fn deinit(self: *MacLcSystem, allocator: std.mem.Allocator) void {
        self.scheduler.deinit();
        self.video.deinit(allocator);
        allocator.free(self.ram);
        allocator.free(self.rom);
        allocator.destroy(self);
    }

    // Bus Hooks
    pub fn busHook(context: ?*anyopaque, addr: u32, access: memory.BusAccess) memory.BusSignal {
        _ = context;
        _ = addr;
        _ = access;
        return .ok;
    }

    pub fn addressTranslator(context: ?*anyopaque, addr: u32, access: memory.BusAccess) anyerror!u32 {
        _ = context;
        _ = access;
        return addr; // Physical = Logical for now
    }

    pub fn mmioRead(context: ?*anyopaque, addr: u32, size: u8) ?u32 {
        var self: *MacLcSystem = @ptrCast(@alignCast(context orelse return null));

        // 24-bit mode mapping approximation
        // 0x9XXXXX -> VIA1
        // 0xDXXXXX -> RBV/Video
        // 0xFXXXXX -> ROM?

        // 32-bit mode
        // 0x50000000...

        if (addr >= 0x50000000) {
            if (addr >= 0x50000000 and addr <= 0x50001FFF) {
                const reg: u4 = @truncate((addr >> 9) & 0xF);
                return self.via1.read(reg, self.total_cycles);
            }
            if (addr >= 0x50F40000) {
                // VRAM
                const offset = addr - 0x50F40000;
                if (offset + size <= self.video.vram.len) {
                    return switch (size) {
                        1 => self.video.vram[offset],
                        2 => std.mem.readInt(u16, self.video.vram[offset..][0..2], .big),
                        4 => std.mem.readInt(u32, self.video.vram[offset..][0..4], .big),
                        else => 0xFF,
                    };
                }
            }
            if (addr >= 0x50024000 and addr <= 0x50024FFF) {
                return self.video.readVdac(addr);
            }
            if (addr >= 0x50026000 and addr <= 0x50027FFF) {
                return self.rbv.read(@truncate((addr >> 9) & 0xF));
            }
            if (addr >= 0x50010000 and addr <= 0x50011FFF) {
                return self.scsi.read(@truncate((addr >> 4) & 0x7));
            }
        } else {
            // 24-bit map
            if (addr >= 0x900000 and addr <= 0x9FFFFF) {
                const reg: u4 = @truncate((addr >> 9) & 0xF);
                return self.via1.read(reg, self.total_cycles);
            }
            if (addr >= 0xD00000 and addr <= 0xDFFFFF) {
                return self.rbv.read(@truncate((addr >> 9) & 0xF));
            }
        }

        if (addr < self.ram.len) return self.ram[addr];
        return 0xFF; // Handled? Return null means not handled?
        // Wait, memory.zig says if read returns val, return it.
        // If null, proceed to array read?
        // No, mmio_read is checked FIRST.
        // If it returns null, memory continues to normal resolution.
        // But here logic covers MMIO regions.
        // If we are here, we ARE in MMIO hook.
        // But addressTranslator maps to physical.
        // If we return value, core uses it.
        // If we return null, core reads self.data.
        // MacLcSystem logic above handles MMIO ranges.
        // If not in range, return null?
        // The logic above returns u8/u32.
        // So we implicitly return ?u32.
    }

    pub fn mmioWrite(context: ?*anyopaque, addr: u32, size: u8, value: u32) bool {
        var self: *MacLcSystem = @ptrCast(@alignCast(context orelse return false));

        const val8: u8 = @truncate(value); // Most MMIO are 8-bit here

        if (addr >= 0x50000000) {
            // ... (RAM write check removed for MMIO path, usually handled by core if RAM)

            if (addr >= 0x50F40000) {
                // VRAM
                // Simple VRAM Mirror/Mapping
                const offset = addr - 0x50F40000;
                if (offset + size <= self.video.vram.len) {
                    switch (size) {
                        1 => self.video.vram[offset] = val8,
                        2 => std.mem.writeInt(u16, self.video.vram[offset..][0..2], @truncate(value), .big),
                        4 => std.mem.writeInt(u32, self.video.vram[offset..][0..4], value, .big),
                        else => {},
                    }
                    return true;
                }
            }
            if (addr >= 0x50010000 and addr <= 0x50011FFF) {
                self.scsi.write(@truncate((addr >> 4) & 0x7), @truncate(val8));
                return true;
            }
            if (addr >= 0x50024000 and addr <= 0x50024FFF) {
                self.video.writeVdac(addr, @truncate(val8));
                return true;
            }
            if (addr >= 0x50000000 and addr <= 0x50001FFF) {
                const reg: u4 = @truncate((addr >> 9) & 0xF);
                self.via1.write(reg, @truncate(val8), self.total_cycles, &self.scheduler) catch @panic("Via write failed");
                if (reg == 0x00) self.updateRtc();
                if (reg == 0x01 or reg == 0x00) self.updateAdb();
                return true;
            }
            if (addr >= 0x50026000 and addr <= 0x50027FFF) {
                self.rbv.write(@truncate((addr >> 9) & 0xF), @truncate(val8));
                return true;
            }
        } else {
            if (addr >= 0x900000 and addr <= 0x9FFFFF) {
                const reg: u4 = @truncate((addr >> 9) & 0xF);
                self.via1.write(reg, @truncate(val8), self.total_cycles, &self.scheduler) catch @panic("Via write failed");
                if (reg == 0x00) self.updateRtc();
                if (reg == 0x01 or reg == 0x00) self.updateAdb();
                return true;
            }
            if (addr >= 0xD00000 and addr <= 0xDFFFFF) {
                self.rbv.write(@truncate((addr >> 9) & 0xF), @truncate(val8));
                return true;
            }
        }
        return false;
    }

    fn updateRtc(self: *MacLcSystem) void {
        const pb = self.via1.port_b;
        const data_in = (pb & 0x01) != 0;
        const clk = (pb & 0x02) != 0;
        const enable = (pb & 0x04) == 0;
        const data_out = self.rtc.step(clk, data_in, enable);
        if (enable and !((self.via1.ddr_b & 0x01) != 0)) {
            if (data_out) self.via1.port_b |= 0x01 else self.via1.port_b &= ~@as(u8, 0x01);
        }
    }

    fn updateAdb(self: *MacLcSystem) void {
        const pb = self.via1.port_b;
        const st0 = (pb & 0x10) != 0;
        const st1 = (pb & 0x20) != 0;
        const data_in = self.via1.port_a;
        const data_out = self.adb.step(st0, st1, data_in);
        // If ADB outputs data, reflect in Port A
        if (!((self.via1.ddr_a & 0x80) != 0)) { // Simplified
            self.via1.port_a = data_out;
        }
    }

    pub fn sync(self: *MacLcSystem, cycles: u32) void {
        self.total_cycles += cycles;
        self.scheduler.runUntil(self.total_cycles);
    }

    pub fn getIrqLevel(self: *MacLcSystem) u8 {
        var level: u8 = 0;
        if (self.via1.getInterruptOutput()) {
            level = 1;
        }
        if (self.rbv.getInterruptOutput()) {
            if (level < 2) level = 2;
        }
        return level;
    }
};
