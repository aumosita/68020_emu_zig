const std = @import("std");
const memory = @import("../core/memory.zig");
const via6522 = @import("../hw/via6522.zig");
const rtc = @import("../hw/rtc.zig");
const rbv = @import("../hw/rbv.zig");
const video = @import("../hw/video.zig");
const scsi = @import("../hw/scsi.zig");
const adb = @import("../hw/adb.zig");

pub const MacLcSystem = struct {
    via1: via6522.Via6522,
    rbv: rbv.Rbv,
    rtc: rtc.Rtc,
    video: video.Video,
    scsi: scsi.Scsi5380,
    adb: adb.Adb,

    // Memory and ROM
    rom_data: []u8,
    ram_size: u32,

    // Address mode: true = 32-bit, false = 24-bit
    address_mode_32: bool = false,

    // Timing
    cycles_since_vbl: u32 = 0,
    const CYCLES_PER_VBL: u32 = 266667; // ~60Hz at 16MHz

    pub fn init(allocator: std.mem.Allocator, ram_size: u32, rom_path: ?[]const u8) !*MacLcSystem {
        const self = try allocator.create(MacLcSystem);
        self.* = .{
            .via1 = via6522.Via6522.init(),
            .rbv = rbv.Rbv.init(),
            .rtc = rtc.Rtc.init(),
            .video = try video.Video.init(allocator, 512 * 1024), // 512KB VRAM
            .scsi = scsi.Scsi5380.init(),
            .adb = adb.Adb.init(),
            .rom_data = &[_]u8{},
            .ram_size = ram_size,
        };

        if (rom_path) |path| {
            const file = try std.fs.cwd().openFile(path, .{});
            defer file.close();
            const size = (try file.stat()).size;
            self.rom_data = try allocator.alloc(u8, @intCast(size));
            _ = try file.readAll(self.rom_data);
        }

        return self;
    }

    pub fn deinit(self: *MacLcSystem, allocator: std.mem.Allocator) void {
        if (self.rom_data.len > 0) {
            allocator.free(self.rom_data);
        }
        self.video.deinit(allocator);
        allocator.destroy(self);
    }

    /// The bus hook that routes memory-mapped I/O
    pub fn busHook(ctx: ?*anyopaque, logical_addr: u32, access: memory.BusAccess) memory.BusSignal {
        const self: *MacLcSystem = @ptrCast(@alignCast(ctx orelse return .bus_error));
        _ = access;

        // Handle 24-bit address wrapping if in 24-bit mode
        const addr = if (self.address_mode_32) logical_addr else (logical_addr & 0x00FFFFFF);

        // Very basic routing logic for now
        if (self.address_mode_32) {
            if (addr >= 0x50000000 and addr <= 0x5FFFFFFF) return .ok;
        } else {
            // 24-bit mode I/O regions
            if (addr >= 0x900000 and addr <= 0x9FFFFF) return .ok; // VIA1
            if (addr >= 0xA00000 and addr <= 0xAFFFFF) return .ok; // SCC
            if (addr >= 0xD00000 and addr <= 0xDFFFFF) return .ok; // VIA2/RBV
            if (addr >= 0xE00000 and addr <= 0xEFFFFF) return .ok; // ASC
            if (addr >= 0xF00000 and addr <= 0xFFFFFF) return .ok; // ROM
        }

        return .ok;
    }

    /// Address translator for Mac LC memory map
    pub fn addressTranslator(ctx: ?*anyopaque, logical_addr: u32, access: memory.BusAccess) anyerror!u32 {
        const self: *MacLcSystem = @ptrCast(@alignCast(ctx orelse return error.BusError));
        _ = access;
        const addr = if (self.address_mode_32) logical_addr else (logical_addr & 0x00FFFFFF);
        if (self.address_mode_32) {
            if (addr < self.ram_size) return addr;
        }
        return addr;
    }

    /// The MMIO read handler
    pub fn mmioRead(ctx: ?*anyopaque, logical_addr: u32, size: u8) ?u32 {
        const self: *MacLcSystem = @ptrCast(@alignCast(ctx orelse return null));
        const addr = if (self.address_mode_32) logical_addr else (logical_addr & 0x00FFFFFF);

        if (self.address_mode_32) {
            if (addr >= 0x50F40000 and addr < 0x50F40000 + self.video.vram.len) {
                const offset = addr - 0x50F40000;
                return switch (size) {
                    1 => self.video.vram[offset],
                    2 => (@as(u16, self.video.vram[offset]) << 8) | self.video.vram[offset + 1],
                    4 => (@as(u32, self.video.vram[offset]) << 24) | (@as(u32, self.video.vram[offset + 1]) << 16) | (@as(u32, self.video.vram[offset + 2]) << 8) | self.video.vram[offset + 3],
                    else => null,
                };
            }
            if (addr >= 0x50010000 and addr <= 0x50011FFF) return self.scsi.read(@truncate((addr >> 4) & 0x7));
            if (addr >= 0x50024000 and addr <= 0x50024FFF) return self.video.readVdac(addr);
            if (addr >= 0x50000000 and addr <= 0x50001FFF) return self.via1.read(@truncate((addr >> 9) & 0xF));
            if (addr >= 0x50026000 and addr <= 0x50027FFF) return self.rbv.read(@truncate((addr >> 9) & 0xF));
        } else {
            if (addr >= 0x900000 and addr <= 0x9FFFFF) return self.via1.read(@truncate((addr >> 9) & 0xF));
            if (addr >= 0xD00000 and addr <= 0xDFFFFF) return self.rbv.read(@truncate((addr >> 9) & 0xF));
            if (addr >= 0xF00000 and addr <= 0xFFFFFF) {
                const offset = addr - 0xF00000;
                if (offset < self.rom_data.len) {
                    return switch (size) {
                        1 => self.rom_data[offset],
                        2 => (@as(u16, self.rom_data[offset]) << 8) | self.rom_data[offset + 1],
                        4 => (@as(u32, self.rom_data[offset]) << 24) | (@as(u32, self.rom_data[offset + 1]) << 16) | (@as(u32, self.rom_data[offset + 2]) << 8) | self.rom_data[offset + 3],
                        else => null,
                    };
                }
            }
        }
        return null;
    }

    /// The MMIO write handler
    pub fn mmioWrite(ctx: ?*anyopaque, logical_addr: u32, size: u8, value: u32) bool {
        const self: *MacLcSystem = @ptrCast(@alignCast(ctx orelse return false));
        const addr = if (self.address_mode_32) logical_addr else (logical_addr & 0x00FFFFFF);

        if (self.address_mode_32) {
            if (addr >= 0x50F40000 and addr < 0x50F40000 + self.video.vram.len) {
                const offset = addr - 0x50F40000;
                switch (size) {
                    1 => self.video.vram[offset] = @truncate(value),
                    2 => {
                        self.video.vram[offset] = @truncate(value >> 8);
                        self.video.vram[offset + 1] = @truncate(value & 0xFF);
                    },
                    4 => {
                        self.video.vram[offset] = @truncate(value >> 24);
                        self.video.vram[offset + 1] = @truncate(value >> 16);
                        self.video.vram[offset + 2] = @truncate(value >> 8);
                        self.video.vram[offset + 3] = @truncate(value & 0xFF);
                    },
                    else => return false,
                }
                return true;
            }
            if (addr >= 0x50010000 and addr <= 0x50011FFF) {
                self.scsi.write(@truncate((addr >> 4) & 0x7), @truncate(value));
                return true;
            }
            if (addr >= 0x50024000 and addr <= 0x50024FFF) {
                self.video.writeVdac(addr, @truncate(value));
                return true;
            }
            if (addr >= 0x50000000 and addr <= 0x50001FFF) {
                const reg: u4 = @truncate((addr >> 9) & 0xF);
                self.via1.write(reg, @truncate(value));
                if (reg == 0x00) self.updateRtc();
                if (reg == 0x01 or reg == 0x00) self.updateAdb();
                return true;
            }
            if (addr >= 0x50026000 and addr <= 0x50027FFF) {
                self.rbv.write(@truncate((addr >> 9) & 0xF), @truncate(value));
                return true;
            }
        } else {
            if (addr >= 0x900000 and addr <= 0x9FFFFF) {
                const reg: u4 = @truncate((addr >> 9) & 0xF);
                self.via1.write(reg, @truncate(value));
                if (reg == 0x00) self.updateRtc();
                if (reg == 0x01 or reg == 0x00) self.updateAdb();
                return true;
            }
            if (addr >= 0xD00000 and addr <= 0xDFFFFF) {
                self.rbv.write(@truncate((addr >> 9) & 0xF), @truncate(value));
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
        self.via1.step(cycles);
        // self.rbv.step(cycles); // RBV might not have step() yet

        // VBL Logic
        self.cycles_since_vbl += cycles;
        if (self.cycles_since_vbl >= CYCLES_PER_VBL) {
            self.cycles_since_vbl -= CYCLES_PER_VBL;
            // Trigger VBL in RBV (and VIA1?)
            self.rbv.setInterrupt(rbv.Rbv.BIT_VBL);
            // Mac LC might also use VIA1 CA1/CA2 for VBL, typically 60Hz tick
            self.via1.setInterrupt(via6522.Via6522.INT_CA1);
        }

        // Update Interrupts... (rest is fine)
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
