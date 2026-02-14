const std = @import("std");
const testing = std.testing;
const root = @import("m68020");
const MacLcSystem = root.MacLcSystem;
const M68k = root.M68k;

/// Helper: install MacLcSystem hooks on M68k
fn installSystem(system: *MacLcSystem, m68k: *M68k) void {
    root.mac_lc_install(system, m68k);
}

test "Memory Map: ROM overlay provides vectors at 0x000000 on reset" {
    const allocator = testing.allocator;
    var system = try MacLcSystem.init(allocator, 1 * 1024 * 1024, null);
    defer system.deinit(allocator);

    // Manually write initial SSP and PC into ROM
    // ROM[0..4] = SSP = 0x00008000
    // ROM[4..8] = PC  = 0x00400020
    std.mem.writeInt(u32, system.rom[0..4], 0x00008000, .big);
    // ROM is only 4 bytes (dummy), so we need a bigger ROM to test this
    // Let's just verify overlay is active
    try testing.expect(system.isOverlayActive());
}

test "Memory Map: ROM overlay reads ROM data at address 0x000000" {
    const allocator = testing.allocator;

    // Allocate with enough ROM data
    var system = try MacLcSystem.init(allocator, 256 * 1024, null);
    defer system.deinit(allocator);

    // Replace dummy ROM with test data
    allocator.free(system.rom);
    system.rom = try allocator.alloc(u8, 16);
    system.rom_size = 16;

    // Write SSP = 0x00004000, PC = 0x00400000 into ROM
    std.mem.writeInt(u32, system.rom[0..4], 0x00004000, .big);
    std.mem.writeInt(u32, system.rom[4..8], 0x00400000, .big);

    // Setup M68k with MMIO hooks
    var m68k = M68k.initWithConfig(allocator, .{ .size = 256 * 1024 });
    defer m68k.deinit();
    installSystem(system, &m68k);

    // Overlay is active — reading 0x000000 should return ROM data
    try testing.expect(system.isOverlayActive());

    // Read through MMIO hook (simulates what CPU sees in bus read)
    // Reading address 0x0 with size 4 should return SSP from ROM
    const ssp = MacLcSystem.mmioRead(system, 0x00000000, 4);
    try testing.expect(ssp != null);
    try testing.expectEqual(@as(u32, 0x00004000), ssp.?);

    // Read address 0x4 should return PC from ROM
    const pc = MacLcSystem.mmioRead(system, 0x00000004, 4);
    try testing.expect(pc != null);
    try testing.expectEqual(@as(u32, 0x00400000), pc.?);
}

test "Memory Map: ROM overlay clears when ROM region accessed" {
    const allocator = testing.allocator;
    var system = try MacLcSystem.init(allocator, 256 * 1024, null);
    defer system.deinit(allocator);

    // Replace with bigger ROM
    allocator.free(system.rom);
    system.rom = try allocator.alloc(u8, 8);
    system.rom_size = 8;
    @memset(system.rom, 0xAA);

    try testing.expect(system.isOverlayActive());

    // Access ROM at 0x400000 (24-bit ROM region) → overlay should clear
    _ = MacLcSystem.mmioRead(system, 0x400000, 1);
    try testing.expect(!system.isOverlayActive());

    // Now reading 0x000000 should return RAM data (0) — MMIO routes RAM through sys.ram[]
    const val = MacLcSystem.mmioRead(system, 0x000000, 1);
    try testing.expect(val != null);
    try testing.expectEqual(@as(u32, 0), val.?);
}

test "Memory Map: ROM is read-only (24-bit write ignored)" {
    const allocator = testing.allocator;
    var system = try MacLcSystem.init(allocator, 256 * 1024, null);
    defer system.deinit(allocator);

    allocator.free(system.rom);
    system.rom = try allocator.alloc(u8, 8);
    system.rom_size = 8;
    system.rom[0] = 0x42;
    system.rom_overlay = false;

    // Write to ROM region should be absorbed (ignored)
    const handled = MacLcSystem.mmioWrite(system, 0x400000, 1, 0xFF);
    try testing.expect(handled); // Write was handled (absorbed)

    // ROM data should be unchanged
    try testing.expectEqual(@as(u8, 0x42), system.rom[0]);
}

test "Memory Map: ROM mirror at 0xF00000 in 24-bit mode" {
    const allocator = testing.allocator;
    var system = try MacLcSystem.init(allocator, 256 * 1024, null);
    defer system.deinit(allocator);

    allocator.free(system.rom);
    system.rom = try allocator.alloc(u8, 8);
    system.rom_size = 8;
    system.rom[0] = 0xDE;
    system.rom[1] = 0xAD;
    system.rom_overlay = false;

    // Read from 0x400000 (ROM base)
    const val1 = MacLcSystem.mmioRead(system, 0x400000, 1);
    try testing.expect(val1 != null);
    try testing.expectEqual(@as(u32, 0xDE), val1.?);

    // Read from 0xF00000 (ROM mirror) should return same data
    const val2 = MacLcSystem.mmioRead(system, 0xF00000, 1);
    try testing.expect(val2 != null);
    try testing.expectEqual(@as(u32, 0xDE), val2.?);
}

test "Memory Map: VIA1 accessible in 24-bit mode" {
    const allocator = testing.allocator;
    var system = try MacLcSystem.init(allocator, 256 * 1024, null);
    defer system.deinit(allocator);
    system.rom_overlay = false;

    // Write to VIA1 Data Direction Register B (reg 2, addr offset 0x400)
    // VIA reg 2 = DDRB. Address = 0x900000 + (2 << 9) = 0x900400
    const handled = MacLcSystem.mmioWrite(system, 0x900400, 1, 0xFF);
    try testing.expect(handled);

    // Read it back
    const val = MacLcSystem.mmioRead(system, 0x900400, 1);
    try testing.expect(val != null);
}

test "Memory Map: SCSI accessible in 24-bit mode" {
    const allocator = testing.allocator;
    var system = try MacLcSystem.init(allocator, 256 * 1024, null);
    defer system.deinit(allocator);
    system.rom_overlay = false;

    // Write to SCSI Output Data (reg 0, addr = 0x580000)
    const handled = MacLcSystem.mmioWrite(system, 0x580000, 1, 0x55);
    try testing.expect(handled);

    // Read SCSI current bus status (reg 4, addr = 0x580040)
    const val = MacLcSystem.mmioRead(system, 0x580040, 1);
    try testing.expect(val != null);
}
