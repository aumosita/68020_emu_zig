const std = @import("std");
const testing = std.testing;
const root = @import("m68020");
const Scsi5380 = root.Scsi5380;

test "SCSI: Initial state is BusFree" {
    var scsi = Scsi5380.init();
    try testing.expectEqual(Scsi5380.BusState.BusFree, scsi.bus_state);
    try testing.expectEqual(@as(u8, 0), scsi.read(4)); // Bus status = 0
    // Reg 5: Phase match bit is set because TCR phase (0) matches bus phase (0)
    try testing.expectEqual(Scsi5380.BAS_PHASE_MATCH, scsi.read(5));
}

test "SCSI: Bus reset via ICR sets IRQ and returns to BusFree" {
    var scsi = Scsi5380.init();

    // Assert RST via ICR
    scsi.write(1, Scsi5380.ICR_RST);

    try testing.expectEqual(Scsi5380.BusState.BusFree, scsi.bus_state);
    try testing.expect(scsi.getInterruptOutput());

    // Reading reg 7 clears IRQ
    _ = scsi.read(7);
    try testing.expect(!scsi.getInterruptOutput());
}

test "SCSI: Arbitration starts when mode and ICR are set" {
    var scsi = Scsi5380.init();

    // Enable arbitration mode
    scsi.write(2, Scsi5380.MODE_ARBITRATE);

    // Put initiator ID on data bus and assert DATA_BUS
    scsi.write(0, 0x80); // ID 7 = bit 7
    scsi.write(1, Scsi5380.ICR_DATA_BUS);

    try testing.expectEqual(Scsi5380.BusState.Arbitration, scsi.bus_state);

    // Check ICR read reflects AIP (Arbitration In Progress)
    const icr_read = scsi.read(1);
    try testing.expect((icr_read & Scsi5380.ICR_AIP) != 0);
    // Should not have lost arbitration (only initiator)
    try testing.expect((icr_read & Scsi5380.ICR_LA) == 0);
}

test "SCSI: Selection with no target times out" {
    var scsi = Scsi5380.init();

    // Arbitration
    scsi.write(2, Scsi5380.MODE_ARBITRATE);
    scsi.write(0, 0x80); // ID 7
    scsi.write(1, Scsi5380.ICR_DATA_BUS);
    try testing.expectEqual(Scsi5380.BusState.Arbitration, scsi.bus_state);

    // Put target ID 0 (bit 0) + initiator ID 7 (bit 7) on bus
    scsi.write(0, 0x81); // Target 0 + Initiator 7

    // Assert SEL to enter Selection phase
    scsi.write(1, Scsi5380.ICR_SEL | Scsi5380.ICR_DATA_BUS);
    try testing.expectEqual(Scsi5380.BusState.Selection, scsi.bus_state);

    // Target should NOT respond (no devices connected)
    // Poll bus status — BSY should not be set by target
    var i: u16 = 0;
    while (i < 300) : (i += 1) {
        const status = scsi.read(4);
        _ = status;
    }

    // After timeout, bus status should not have BSY from target
    const final_status = scsi.read(4);
    try testing.expect((final_status & Scsi5380.STAT_BSY) == 0);
}

test "SCSI: Output data register reflects on bus when DATA_BUS asserted" {
    var scsi = Scsi5380.init();

    scsi.write(0, 0xAA); // Set output data
    // bus_data should not change yet (DATA_BUS not asserted)
    try testing.expectEqual(@as(u8, 0), scsi.read(0));

    // Assert DATA_BUS in ICR
    scsi.write(1, Scsi5380.ICR_DATA_BUS);
    // Now write again — should appear on bus
    scsi.write(0, 0x55);
    try testing.expectEqual(@as(u8, 0x55), scsi.read(0));
}

test "SCSI: Reset clears all state" {
    var scsi = Scsi5380.init();
    scsi.write(2, Scsi5380.MODE_ARBITRATE);
    scsi.write(0, 0x80);
    scsi.write(1, Scsi5380.ICR_DATA_BUS);

    scsi.reset();

    try testing.expectEqual(Scsi5380.BusState.BusFree, scsi.bus_state);
    try testing.expectEqual(@as(u8, 0), scsi.mode);
    try testing.expectEqual(@as(u8, 0), scsi.icr);
    try testing.expect(!scsi.arb_in_progress);
    try testing.expect(!scsi.irq_active);
}

test "SCSI: Phase match in Bus and Status register" {
    var scsi = Scsi5380.init();

    // Set TCR phase bits to DataIn (I/O=1, C/D=0, MSG=0 → 0x01)
    scsi.write(3, 0x01);

    // Bus and Status should reflect phase match if bus phase matches
    const bas = scsi.read(5);
    // Bus signals are 0, TCR is 0x01, so they don't match
    try testing.expect((bas & Scsi5380.BAS_PHASE_MATCH) == 0);

    // Set TCR to 0 to match the default bus phase (0)
    scsi.write(3, 0x00);
    const bas2 = scsi.read(5);
    try testing.expect((bas2 & Scsi5380.BAS_PHASE_MATCH) != 0);
}

test "SCSI: Selection succeeds with attached device" {
    const allocator = std.testing.allocator;
    var scsi = Scsi5380.init();
    
    // Create and attach a virtual disk to ID 0
    var disk = try root.ScsiDisk.init(allocator, 0);
    defer disk.deinit();
    scsi.attach(0, disk.device());

    // Arbitration
    scsi.write(2, Scsi5380.MODE_ARBITRATE);
    scsi.write(0, 0x80); // ID 7
    scsi.write(1, Scsi5380.ICR_DATA_BUS);

    // Selection: Target 0 (bit 0) + Initiator 7 (bit 7)
    scsi.write(0, 0x81);
    scsi.write(1, Scsi5380.ICR_SEL | Scsi5380.ICR_DATA_BUS);

    // Should transition to InformationTransfer (immediate in our simplified model)
    try testing.expectEqual(Scsi5380.BusState.InformationTransfer, scsi.bus_state);
    try testing.expect(scsi.target_id == 0);
}

test "SCSI: INQUIRY command returns device info" {
    const allocator = std.testing.allocator;
    var disk = try root.ScsiDisk.init(allocator, 0);
    defer disk.deinit();
    
    const device = disk.device();
    var status: u8 = 0xFF;
    
    // INQUIRY CDB: 12 00 00 00 24 00 (alloc length 36 bytes)
    const cdb = [_]u8{ 0x12, 0x00, 0x00, 0x00, 0x24, 0x00 };
    
    const transfer_len = device.executeCommand(&cdb, &status);
    try testing.expect(transfer_len > 0);
    try testing.expectEqual(@as(u8, 0), status); // Good status

    var buffer: [36]u8 = undefined;
    const read_len = device.readData(&buffer);
    try testing.expectEqual(transfer_len, read_len);
    
    // Check for "APPLE" vendor string in inquiry data
    try testing.expect(std.mem.indexOf(u8, &buffer, "APPLE") != null);
}
