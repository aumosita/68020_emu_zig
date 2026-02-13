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
    ram_size: u32,
    rom_size: u32,

    // VBL
    vbl_active: bool = false,

    // Address Mode
    address_mode_32: bool = false,

    // ROM Overlay: at reset, ROM appears at 0x000000
    // Cleared when CPU first accesses ROM area (0x400000+)
    rom_overlay: bool = true,

    // ── Mac LC Address Constants ──
    // 24-bit mode
    const RAM_BASE_24: u32 = 0x000000;
    const RAM_END_24: u32 = 0x3FFFFF; // 4MB max in 24-bit
    const ROM_BASE_24: u32 = 0x400000;
    const ROM_END_24: u32 = 0x4FFFFF;
    const SCSI_BASE_24: u32 = 0x580000;
    const SCSI_END_24: u32 = 0x5FFFFF;
    const VIA1_BASE_24: u32 = 0x900000;
    const VIA1_END_24: u32 = 0x9FFFFF;
    const RBV_BASE_24: u32 = 0xD00000;
    const RBV_END_24: u32 = 0xDFFFFF;
    const ROM_MIRROR_BASE_24: u32 = 0xF00000;
    const ROM_MIRROR_END_24: u32 = 0xFFFFFF;

    // 32-bit mode
    const ROM_BASE_32: u32 = 0x40000000;
    const ROM_END_32: u32 = 0x4007FFFF; // 512KB
    const IO_BASE_32: u32 = 0x50000000;
    const VIA1_BASE_32: u32 = 0x50000000;
    const VIA1_END_32: u32 = 0x50001FFF;
    const SCSI_BASE_32: u32 = 0x50010000;
    const SCSI_END_32: u32 = 0x50011FFF;
    const VDAC_BASE_32: u32 = 0x50024000;
    const VDAC_END_32: u32 = 0x50024FFF;
    const RBV_BASE_32: u32 = 0x50026000;
    const RBV_END_32: u32 = 0x50027FFF;
    const VRAM_BASE_32: u32 = 0x50F40000;

    const ROM_SIZE_MAX: u32 = 512 * 1024; // 512KB
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
        sys.rom_overlay = true; // Overlay active after reset
        sys.total_cycles = 0;
        sys.ram_size = ram_size;
        sys.vbl_active = false;

        // Start VBL
        try sys.rbv.start(&sys.scheduler, 0);

        // Allocate RAM
        sys.ram = try allocator.alloc(u8, ram_size);
        @memset(sys.ram, 0);

        // Load ROM
        if (rom_path) |path| {
            const file = std.fs.cwd().openFile(path, .{}) catch {
                // File not found — allocate dummy ROM
                sys.rom = try allocator.alloc(u8, 4);
                @memset(sys.rom, 0);
                sys.rom_size = 4;
                return sys;
            };
            defer file.close();

            const stat = try file.stat();
            const file_size: u32 = @intCast(@min(stat.size, ROM_SIZE_MAX));
            sys.rom = try allocator.alloc(u8, file_size);
            const bytes_read = try file.readAll(sys.rom);
            sys.rom_size = @intCast(bytes_read);
        } else {
            sys.rom = try allocator.alloc(u8, 4); // Dummy
            @memset(sys.rom, 0);
            sys.rom_size = 4;
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

    // ────────────────────────────────────────────
    //  Bus Hooks
    // ────────────────────────────────────────────

    pub fn busHook(context: ?*anyopaque, addr: u32, access: memory.BusAccess) memory.BusSignal {
        _ = context;
        _ = addr;
        _ = access;
        return .ok;
    }

    pub fn addressTranslator(context: ?*anyopaque, addr: u32, access: memory.BusAccess) anyerror!u32 {
        _ = context;
        _ = access;
        return addr; // We handle all mapping in MMIO hooks
    }

    // ────────────────────────────────────────────
    //  MMIO Read
    // ────────────────────────────────────────────

    pub fn mmioRead(context: ?*anyopaque, addr: u32, size: u8) ?u32 {
        var self: *MacLcSystem = @ptrCast(@alignCast(context orelse return null));

        // ── ROM Overlay: ROM at 0x000000 during boot ──
        if (self.rom_overlay) {
            if (addr < self.rom_size) {
                return self.readRom(addr, size);
            }
        }

        if (addr >= IO_BASE_32) {
            // 32-bit I/O space
            return self.mmioRead32bit(addr, size);
        } else if (addr >= ROM_BASE_32 and addr <= ROM_END_32) {
            // 32-bit ROM
            self.rom_overlay = false; // Accessing ROM area clears overlay
            const offset = addr - ROM_BASE_32;
            return self.readRom(offset, size);
        } else if (!self.address_mode_32) {
            // 24-bit mode regions
            return self.mmioRead24bit(addr, size);
        }

        return null; // Fall through to memory.data[]
    }

    fn mmioRead32bit(self: *MacLcSystem, addr: u32, size: u8) ?u32 {
        if (addr >= VIA1_BASE_32 and addr <= VIA1_END_32) {
            const reg: u4 = @truncate((addr >> 9) & 0xF);
            return self.via1.read(reg, self.total_cycles);
        }
        if (addr >= SCSI_BASE_32 and addr <= SCSI_END_32) {
            return self.scsi.read(@truncate((addr >> 4) & 0x7));
        }
        if (addr >= VDAC_BASE_32 and addr <= VDAC_END_32) {
            return self.video.readVdac(addr);
        }
        if (addr >= RBV_BASE_32 and addr <= RBV_END_32) {
            return self.rbv.read(@truncate((addr >> 9) & 0xF));
        }
        if (addr >= VRAM_BASE_32) {
            const offset = addr - VRAM_BASE_32;
            if (offset + size <= self.video.vram.len) {
                return switch (size) {
                    1 => self.video.vram[offset],
                    2 => std.mem.readInt(u16, self.video.vram[offset..][0..2], .big),
                    4 => std.mem.readInt(u32, self.video.vram[offset..][0..4], .big),
                    else => 0xFF,
                };
            }
        }
        return null;
    }

    fn mmioRead24bit(self: *MacLcSystem, addr: u32, size: u8) ?u32 {
        _ = size;

        // ROM (0x400000-0x4FFFFF)
        if (addr >= ROM_BASE_24 and addr <= ROM_END_24) {
            self.rom_overlay = false;
            const offset = addr - ROM_BASE_24;
            return self.readRomByte(offset);
        }

        // ROM mirror (0xF00000-0xFFFFFF)
        if (addr >= ROM_MIRROR_BASE_24 and addr <= ROM_MIRROR_END_24) {
            self.rom_overlay = false;
            const offset = addr - ROM_MIRROR_BASE_24;
            return self.readRomByte(offset);
        }

        // VIA1 (0x900000-0x9FFFFF)
        if (addr >= VIA1_BASE_24 and addr <= VIA1_END_24) {
            const reg: u4 = @truncate((addr >> 9) & 0xF);
            return self.via1.read(reg, self.total_cycles);
        }

        // RBV (0xD00000-0xDFFFFF)
        if (addr >= RBV_BASE_24 and addr <= RBV_END_24) {
            return self.rbv.read(@truncate((addr >> 9) & 0xF));
        }

        // SCSI (0x580000-0x5FFFFF)
        if (addr >= SCSI_BASE_24 and addr <= SCSI_END_24) {
            return self.scsi.read(@truncate((addr >> 4) & 0x7));
        }

        // RAM region — let it fall through to memory.data[]
        return null;
    }

    // ────────────────────────────────────────────
    //  MMIO Write
    // ────────────────────────────────────────────

    pub fn mmioWrite(context: ?*anyopaque, addr: u32, size: u8, value: u32) bool {
        var self: *MacLcSystem = @ptrCast(@alignCast(context orelse return false));

        // ── ROM Overlay write: writing to overlaid area goes to RAM ──
        if (self.rom_overlay and addr < self.rom_size) {
            // Boot code writes to 0x000000 area — this goes to RAM
            // We allow it to fall through to memory.data[]
            self.rom_overlay = false; // Overlay cleared on first write
            return false; // Let memory.data handle it
        }

        _ = size;
        const val8: u8 = @truncate(value);

        if (addr >= IO_BASE_32) {
            return self.mmioWrite32bit(addr, val8, value);
        } else if (addr >= ROM_BASE_32 and addr <= ROM_END_32) {
            // ROM is read-only — ignore writes
            self.rom_overlay = false;
            return true;
        } else if (!self.address_mode_32) {
            return self.mmioWrite24bit(addr, val8, value);
        }

        return false;
    }

    fn mmioWrite32bit(self: *MacLcSystem, addr: u32, val8: u8, value: u32) bool {
        if (addr >= VRAM_BASE_32) {
            const offset = addr - VRAM_BASE_32;
            if (offset < self.video.vram.len) {
                switch (@as(u8, @intCast(@min(4, self.video.vram.len - offset)))) {
                    1 => self.video.vram[offset] = val8,
                    2 => std.mem.writeInt(u16, self.video.vram[offset..][0..2], @truncate(value), .big),
                    4 => std.mem.writeInt(u32, self.video.vram[offset..][0..4], value, .big),
                    else => {},
                }
                return true;
            }
        }
        if (addr >= SCSI_BASE_32 and addr <= SCSI_END_32) {
            self.scsi.write(@truncate((addr >> 4) & 0x7), val8);
            return true;
        }
        if (addr >= VDAC_BASE_32 and addr <= VDAC_END_32) {
            self.video.writeVdac(addr, val8);
            return true;
        }
        if (addr >= VIA1_BASE_32 and addr <= VIA1_END_32) {
            const reg: u4 = @truncate((addr >> 9) & 0xF);
            self.via1.write(reg, val8, self.total_cycles, &self.scheduler) catch @panic("Via write failed");
            if (reg == 0x00) self.updateRtc();
            if (reg == 0x01 or reg == 0x00) self.updateAdb();
            return true;
        }
        if (addr >= RBV_BASE_32 and addr <= RBV_END_32) {
            self.rbv.write(@truncate((addr >> 9) & 0xF), val8);
            return true;
        }
        return false;
    }

    fn mmioWrite24bit(self: *MacLcSystem, addr: u32, val8: u8, value: u32) bool {
        _ = value;

        // ROM writes are ignored (read-only)
        if ((addr >= ROM_BASE_24 and addr <= ROM_END_24) or
            (addr >= ROM_MIRROR_BASE_24 and addr <= ROM_MIRROR_END_24))
        {
            self.rom_overlay = false;
            return true; // Absorbed, ignored
        }

        // VIA1
        if (addr >= VIA1_BASE_24 and addr <= VIA1_END_24) {
            const reg: u4 = @truncate((addr >> 9) & 0xF);
            self.via1.write(reg, val8, self.total_cycles, &self.scheduler) catch @panic("Via write failed");
            if (reg == 0x00) self.updateRtc();
            if (reg == 0x01 or reg == 0x00) self.updateAdb();
            return true;
        }

        // RBV
        if (addr >= RBV_BASE_24 and addr <= RBV_END_24) {
            self.rbv.write(@truncate((addr >> 9) & 0xF), val8);
            return true;
        }

        // SCSI
        if (addr >= SCSI_BASE_24 and addr <= SCSI_END_24) {
            self.scsi.write(@truncate((addr >> 4) & 0x7), val8);
            return true;
        }

        return false; // Not MMIO — falls through to memory.data[]
    }

    // ────────────────────────────────────────────
    //  ROM Access Helpers
    // ────────────────────────────────────────────

    fn readRom(self: *const MacLcSystem, offset: u32, size: u8) ?u32 {
        if (offset >= self.rom_size) return 0xFF;
        return switch (size) {
            1 => self.readRomByte(offset),
            2 => blk: {
                if (offset + 1 >= self.rom_size) break :blk @as(u32, 0xFFFF);
                const hi: u32 = self.rom[offset];
                const lo: u32 = self.rom[offset + 1];
                break :blk (hi << 8) | lo;
            },
            4 => blk: {
                if (offset + 3 >= self.rom_size) break :blk @as(u32, 0xFFFFFFFF);
                const b0: u32 = self.rom[offset];
                const b1: u32 = self.rom[offset + 1];
                const b2: u32 = self.rom[offset + 2];
                const b3: u32 = self.rom[offset + 3];
                break :blk (b0 << 24) | (b1 << 16) | (b2 << 8) | b3;
            },
            else => 0xFF,
        };
    }

    fn readRomByte(self: *const MacLcSystem, offset: u32) u8 {
        if (offset >= self.rom_size) return 0xFF;
        return self.rom[offset];
    }

    // ────────────────────────────────────────────
    //  Peripheral Helpers
    // ────────────────────────────────────────────

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
        if (!((self.via1.ddr_a & 0x80) != 0)) {
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

    // ── Public API ──

    /// Manually disable ROM overlay (for testing)
    pub fn clearOverlay(self: *MacLcSystem) void {
        self.rom_overlay = false;
    }

    /// Check if ROM overlay is active
    pub fn isOverlayActive(self: *const MacLcSystem) bool {
        return self.rom_overlay;
    }

    /// Re-enable ROM overlay (simulates hardware reset)
    pub fn resetOverlay(self: *MacLcSystem) void {
        self.rom_overlay = true;
    }
};
