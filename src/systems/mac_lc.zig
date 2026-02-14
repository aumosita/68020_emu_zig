const std = @import("std");
const memory = @import("../core/memory.zig");
const via6522 = @import("../hw/via6522.zig");
const rbv = @import("../hw/rbv.zig");
const video = @import("../hw/video.zig");
const scsi = @import("../hw/scsi.zig");
const adb = @import("../hw/adb.zig");
const rtc = @import("../hw/rtc.zig");
const scc_mod = @import("../hw/scc.zig");
const iwm_mod = @import("../hw/iwm.zig");
const scsi_disk = @import("../hw/scsi_disk.zig");
const bus_cycle = @import("../core/bus_cycle.zig");
const Scheduler = @import("../core/scheduler.zig").Scheduler;

pub const MacLcSystem = struct {
    via1: via6522.Via6522,
    rbv: rbv.Rbv,
    video: video.Video,
    scsi: scsi.Scsi5380,
    adb: adb.Adb,
    rtc: rtc.Rtc,
    scc: scc_mod.Scc,
    iwm: iwm_mod.Iwm,

    // Virtual Disks
    scsi0: ?*scsi_disk.ScsiDisk = null,

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
    const SCC_BASE_24: u32 = 0xC00000;
    const SCC_END_24: u32 = 0xCFFFFF;
    const ROM_MIRROR_BASE_24: u32 = 0xF00000;
    const ROM_MIRROR_END_24: u32 = 0xFFFFFF;
    const IWM_BASE_24: u32 = 0xE00000;
    const IWM_END_24: u32 = 0xEFFFFF;

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
    const SCC_BASE_32: u32 = 0x50004000;
    const SCC_END_32: u32 = 0x50005FFF;
    const IWM_BASE_32: u32 = 0x50016000;
    const IWM_END_32: u32 = 0x50017FFF;
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
        sys.scc = scc_mod.Scc.init();
        sys.scc.channels[0].tx_callback = sccDefaultTxCallback; // Channel A
        sys.scc.channels[1].tx_callback = sccDefaultTxCallback; // Channel B

        sys.iwm = iwm_mod.Iwm.init();
        sys.scheduler = Scheduler.init(allocator);

        // Attach virtual disk to SCSI ID 0
        sys.scsi0 = try scsi_disk.ScsiDisk.init(allocator, 0);
        sys.scsi.attach(0, sys.scsi0.?.device());

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

    /// Configure bus cycle wait states for Mac LC hardware.
    /// Call after mac_lc_install() to enable accurate bus timing.
    pub fn configureBusCycles(mem: *memory.Memory) void {
        // Mac LC (16MHz 68020) wait states:
        //   RAM (0x000000-0x3FFFFF): 0 wait states
        //   ROM (0x400000-0x4FFFFF): 2 wait states
        //   I/O (0x500000-0x9FFFFF): 4 wait states  (VIA, SCSI, SCC, etc.)
        //   RBV/Misc (0xC00000-0xFFFFFF): 4 wait states
        const S = struct {
            const regions = [_]bus_cycle.WaitStateRegion{
                .{ .start = 0x000000, .end_exclusive = 0x400000, .wait_states = 0 }, // RAM
                .{ .start = 0x400000, .end_exclusive = 0x500000, .wait_states = 2 }, // ROM
                .{ .start = 0x500000, .end_exclusive = 0xA00000, .wait_states = 4 }, // I/O
                .{ .start = 0xC00000, .end_exclusive = 0x1000000, .wait_states = 4 }, // SCC/IWM/ROM mirror
            };
        };
        mem.bus_cycle_sm.config = .{
            .default_wait_states = 0,
            .region_wait_states = &S.regions,
        };
        mem.setBusCycleEnabled(true);
    }

    pub fn deinit(self: *MacLcSystem, allocator: std.mem.Allocator) void {
        if (self.scsi0) |s0| s0.deinit();
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

    pub fn addressTranslator(context: ?*anyopaque, addr: u32, access: memory.BusAccess) memory.errors.MemoryError!u32 {
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
            self.rom_overlay = false;
            const offset = addr - ROM_BASE_32;
            return self.readRom(offset, size);
        } else if (!self.address_mode_32) {
            // 24-bit mode I/O regions
            if (self.mmioRead24bit(addr, size)) |val| return val;
        }

        // ── RAM: route ALL RAM accesses through sys.ram[] ──
        if (addr < self.ram_size) {
            return self.readRam(addr, size);
        }

        return 0; // Unmapped regions read as 0
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
        if (addr >= SCC_BASE_32 and addr <= SCC_END_32) {
            return self.scc.read(addr);
        }
        if (addr >= IWM_BASE_32 and addr <= IWM_END_32) {
            return self.iwm.read(addr);
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

        // ROM (0x400000-0x4FFFFF)
        if (addr >= ROM_BASE_24 and addr <= ROM_END_24) {
            self.rom_overlay = false;
            const offset = addr - ROM_BASE_24;
            return self.readRom(offset, size);
        }

        // ROM mirror (0xF00000-0xFFFFFF)
        if (addr >= ROM_MIRROR_BASE_24 and addr <= ROM_MIRROR_END_24) {
            self.rom_overlay = false;
            const offset = addr - ROM_MIRROR_BASE_24;
            return self.readRom(offset, size);
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

        // SCC (0xC00000-0xCFFFFF)
        if (addr >= SCC_BASE_24 and addr <= SCC_END_24) {
            return self.scc.read(addr);
        }

        // IWM (0xE00000-0xEFFFFF)
        if (addr >= IWM_BASE_24 and addr <= IWM_END_24) {
            return self.iwm.read(addr);
        }

        return null; // Not an I/O register — handled by mmioRead's RAM fallback
    }

    // ────────────────────────────────────────────
    //  MMIO Write
    // ────────────────────────────────────────────

    pub fn mmioWrite(context: ?*anyopaque, addr: u32, size: u8, value: u32) bool {
        var self: *MacLcSystem = @ptrCast(@alignCast(context orelse return false));

        // ── ROM Overlay write: writing to overlaid area goes to RAM ──
        if (self.rom_overlay and addr < self.rom_size) {
            self.rom_overlay = false;
        }

        const val8: u8 = @truncate(value);

        if (addr >= IO_BASE_32) {
            return self.mmioWrite32bit(addr, val8, value);
        } else if (addr >= ROM_BASE_32 and addr <= ROM_END_32) {
            self.rom_overlay = false;
            return true; // ROM is read-only — ignore
        } else if (!self.address_mode_32) {
            if (self.mmioWrite24bit(addr, val8, value)) return true;
        }

        // ── RAM: route ALL RAM writes through sys.ram[] ──
        if (addr < self.ram_size) {
            self.writeRam(addr, size, value);
            return true;
        }

        return true; // Absorb writes to unmapped regions
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
        if (addr >= SCC_BASE_32 and addr <= SCC_END_32) {
            self.scc.write(addr, val8);
            return true;
        }
        if (addr >= IWM_BASE_32 and addr <= IWM_END_32) {
            self.iwm.write(addr, val8);
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

        // SCC
        if (addr >= SCC_BASE_24 and addr <= SCC_END_24) {
            self.scc.write(addr, val8);
            return true;
        }

        // IWM
        if (addr >= IWM_BASE_24 and addr <= IWM_END_24) {
            self.iwm.write(addr, val8);
            return true;
        }

        return false; // Not an I/O register — handled by mmioWrite's RAM fallback
    }

    // ────────────────────────────────────────────
    //  RAM Access Helpers
    // ────────────────────────────────────────────

    fn readRam(self: *const MacLcSystem, addr: u32, size: u8) u32 {
        if (addr >= self.ram_size) return 0;
        return switch (size) {
            1 => self.ram[addr],
            2 => blk: {
                if (addr + 1 >= self.ram_size) break :blk @as(u32, 0);
                const hi: u32 = self.ram[addr];
                const lo: u32 = self.ram[addr + 1];
                break :blk (hi << 8) | lo;
            },
            4 => blk: {
                if (addr + 3 >= self.ram_size) break :blk @as(u32, 0);
                const b0: u32 = self.ram[addr];
                const b1: u32 = self.ram[addr + 1];
                const b2: u32 = self.ram[addr + 2];
                const b3: u32 = self.ram[addr + 3];
                break :blk (b0 << 24) | (b1 << 16) | (b2 << 8) | b3;
            },
            else => 0,
        };
    }

    fn writeRam(self: *MacLcSystem, addr: u32, size: u8, value: u32) void {
        if (addr >= self.ram_size) return;
        switch (size) {
            1 => {
                self.ram[addr] = @truncate(value);
            },
            2 => {
                if (addr + 1 >= self.ram_size) return;
                self.ram[addr] = @truncate(value >> 8);
                self.ram[addr + 1] = @truncate(value);
            },
            4 => {
                if (addr + 3 >= self.ram_size) return;
                self.ram[addr] = @truncate(value >> 24);
                self.ram[addr + 1] = @truncate(value >> 16);
                self.ram[addr + 2] = @truncate(value >> 8);
                self.ram[addr + 3] = @truncate(value);
            },
            else => {},
        }
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
        // RTC data-out drives PB0 as external input (when PB0 is configured as input)
        if (data_out) {
            self.via1.port_b_input |= 0x01;
        } else {
            self.via1.port_b_input &= ~@as(u8, 0x01);
        }
    }

    fn updateAdb(self: *MacLcSystem) void {
        const pb = self.via1.port_b;
        const st0 = (pb & 0x10) != 0;
        const st1 = (pb & 0x20) != 0;
        const data_in = self.via1.port_a;
        const data_out = self.adb.step(st0, st1, data_in);
        // ADB data-out drives PA as external input
        self.via1.port_a_input = data_out;
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

    // Default SCC output callback (prints to stdout)
    pub fn sccDefaultTxCallback(_: ?*anyopaque, char: u8) void {
        const stdout = std.io.getStdOut().writer();
        stdout.print("{c}", .{char}) catch {};
    }
};
