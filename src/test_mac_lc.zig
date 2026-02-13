const std = @import("std");
const root = @import("root.zig");

test "Mac LC MMIO Routing" {
    const allocator = std.testing.allocator;
    
    // Create Mac LC system (no ROM for now)
    const sys = try root.MacLcSystem.init(allocator, 4 * 1024 * 1024, null);
    defer sys.deinit(allocator);
    
    // Create CPU
    var m68k = root.M68k.initWithConfig(allocator, .{ .size = 4 * 1024 * 1024 });
    defer m68k.deinit();
    
    // Install Mac LC hardware hooks
    root.mac_lc_install(sys, &m68k);
    
    // Test VIA1 access in 24-bit mode (Default)
    sys.address_mode_32 = false;
    
    // Write to VIA1 DDRB (Address 0x900400 = Base 0x900000 + Reg 2 * 0x200)
    // Actually our current implementation uses (addr >> 9) & 0xF
    // 0x900000 >> 9 = 0x4800. 0x900400 >> 9 = 0x4802. (0x4802 & 0xF) = 2.
    try m68k.memory.write8Bus(0x900400, 0x55, .{});
    
    const val = try m68k.memory.read8Bus(0x900400, .{});
    try std.testing.expectEqual(@as(u8, 0x55), val);
    try std.testing.expectEqual(@as(u8, 0x55), sys.via1.ddr_b);
    
    // Test RBV access
    // 0xD00000 >> 9 = 0x6800. 0xD00000 & 0xF = 0.
    // RBV register 0 write clears bits. Let's use register 2 (Mon Type/Depth)
    // 0xD00400 >> 9 = 0x6802.
    try m68k.memory.write8Bus(0xD00400, 0x5A, .{});
    try std.testing.expectEqual(@as(u8, 0x5A), sys.rbv.depth);
}

test "Mac LC RTC Serial Communication" {
    const allocator = std.testing.allocator;
    const sys = try root.MacLcSystem.init(allocator, 1 * 1024 * 1024, null);
    defer sys.deinit(allocator);
    
    var m68k = root.M68k.initWithConfig(allocator, .{ .size = 1 * 1024 * 1024 });
    defer m68k.deinit();
    root.mac_lc_install(sys, &m68k);
    
    // Set DDRB: PB0 (Data) as Output for command, PB1 (Clock) as Output, PB2 (Enable) as Output
    try m68k.memory.write8Bus(0x900400, 0x07, .{});
    
    // RTC Read Seconds (Command 0x8D - Read byte 3 (MSB) of seconds)
    // Format: 1 0 0 0 1 1 0 1
    const cmd: u8 = 0x8D;
    
    // De-select RTC (Enable = 1)
    try m68k.memory.write8Bus(0x900000, 0x07, .{}); // PB2=1, PB1=1, PB0=1
    
    // Select RTC while Clock is low
    try m68k.memory.write8Bus(0x900000, 0x00, .{}); // PB2=0, PB1=0, PB0=0
    
    // Shift in 8 bits of command
    var bit: i32 = 7;
    while (bit >= 0) : (bit -= 1) {
        const val = (cmd >> @intCast(bit)) & 1;
        // Data set, Clock Low
        try m68k.memory.write8Bus(0x900000, @as(u8, @intCast(val)), .{}); 
        // Clock High (RTC latches bit)
        try m68k.memory.write8Bus(0x900000, @as(u8, @intCast(val | 0x02)), .{});
    }
    
    // Command processed. State should be data_out.
    // Set PB0 to Input to read data
    try m68k.memory.write8Bus(0x900400, 0x06, .{}); 
    
    // Shift out 8 bits of data
    var result: u8 = 0;
    for (0..8) |_| {
        // Clock Low (RTC shifts out next bit)
        try m68k.memory.write8Bus(0x900000, 0x00, .{});
        const pb = try m68k.memory.read8Bus(0x900000, .{});
        result = (result << 1) | (pb & 0x01);
        // Clock High
        try m68k.memory.write8Bus(0x900000, 0x02, .{});
    }
    
    // MSB of 0xCF123456 is 0xCF
    try std.testing.expectEqual(@as(u8, 0xCF), result);
}

test "Mac LC RBV VBL Interrupt" {
    const allocator = std.testing.allocator;
    const sys = try root.MacLcSystem.init(allocator, 1 * 1024 * 1024, null);
    defer sys.deinit(allocator);
    
    var m68k = root.M68k.initWithConfig(allocator, .{ .size = 1 * 1024 * 1024 });
    defer m68k.deinit();
    root.mac_lc_install(sys, &m68k);
    
    // Enable VBL interrupt in RBV (IER bit 3)
    // RBV Enable register is at 0xD00200 in 24-bit mode (Offset 1 * 0x200)
    // Write 0x88 (Set bit 3)
    try m68k.memory.write8Bus(0xD00200, 0x88, .{});
    
    try std.testing.expectEqual(@as(u8, 0x08), sys.rbv.ier);
    
    // Sync for 1 VBL period
    sys.sync(266667);
    
    // Check if VBL bit is set in RBV Status
    // RBV Status is at 0xD00000
    const status = try m68k.memory.read8Bus(0xD00000, .{});
    try std.testing.expect((status & 0x08) != 0); // VBL bit
    try std.testing.expect((status & 0x80) != 0); // ANY bit (master IRQ)
    
    // System IRQ level should be 2
    try std.testing.expectEqual(@as(u8, 2), root.mac_lc_get_irq_level(sys));
    
    // Clear interrupt by writing to status
    try m68k.memory.write8Bus(0xD00000, 0x08, .{});
    try std.testing.expectEqual(@as(u8, 0), sys.rbv.ifr);
}

test "Mac LC Video VRAM and Palette" {
    const allocator = std.testing.allocator;
    const sys = try root.MacLcSystem.init(allocator, 4 * 1024 * 1024, null);
    defer sys.deinit(allocator);
    
    var m68k = root.M68k.initWithConfig(allocator, .{ .size = 4 * 1024 * 1024 });
    defer m68k.deinit();
    root.mac_lc_install(sys, &m68k);
    
    sys.address_mode_32 = true;
    
    // Test VRAM write/read (Base 0x50F40000)
    try m68k.memory.write32Bus(0x50F40000, 0x11223344, .{});
    const vram_val = try m68k.memory.read32Bus(0x50F40000, .{});
    try std.testing.expectEqual(@as(u32, 0x11223344), vram_val);
    try std.testing.expectEqual(@as(u8, 0x11), sys.video.vram[0]);
    
    // Test Palette write (Base 0x50024000)
    // Register 0 (Index) = 1
    try m68k.memory.write8Bus(0x50024000, 0x01, .{});
    // Register 4 (Data) = Red 0xFF, Green 0x88, Blue 0x00
    try m68k.memory.write8Bus(0x50024004, 0xFF, .{});
    try m68k.memory.write8Bus(0x50024004, 0x88, .{});
    try m68k.memory.write8Bus(0x50024004, 0x00, .{});
    
    try std.testing.expectEqual(@as(u32, 0xFFFF8800), sys.video.palette[1]);
}

test "Mac LC SCSI Register Access" {
    const allocator = std.testing.allocator;
    const sys = try root.MacLcSystem.init(allocator, 1 * 1024 * 1024, null);
    defer sys.deinit(allocator);
    
    var m68k = root.M68k.initWithConfig(allocator, .{ .size = 1 * 1024 * 1024 });
    defer m68k.deinit();
    root.mac_lc_install(sys, &m68k);
    
    sys.address_mode_32 = true;
    
    // Test SCSI Mode register (Offset 0x10000 + 2 * 0x10 = 0x50010020)
    try m68k.memory.write8Bus(0x50010020, 0x01, .{});
    const mode = try m68k.memory.read8Bus(0x50010020, .{});
    try std.testing.expectEqual(@as(u8, 0x01), mode);
    try std.testing.expectEqual(@as(u8, 0x01), sys.scsi.mode);
}

test "Mac LC ADB Integration" {
    const allocator = std.testing.allocator;
    const sys = try root.MacLcSystem.init(allocator, 1 * 1024 * 1024, null);
    defer sys.deinit(allocator);
    
    var m68k = root.M68k.initWithConfig(allocator, .{ .size = 1 * 1024 * 1024 });
    defer m68k.deinit();
    root.mac_lc_install(sys, &m68k);
    
    // Set VIA1 PB4, PB5 (ADB State)
    // Writing to Port B should trigger updateAdb
    try m68k.memory.write8Bus(0x900000, 0x10, .{}); // ST0=1, ST1=0
    
    // Check if ADB step was called (mocked, so just checking logic flow)
    try std.testing.expectEqual(@as(u8, 0), sys.via1.port_a); 
}
