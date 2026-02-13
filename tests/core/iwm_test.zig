const std = @import("std");
const Iwm = @import("m68020").Iwm;

test "IWM init returns default state" {
    const iwm = Iwm.init();
    try std.testing.expectEqual(@as(u8, 0), iwm.mode);
    try std.testing.expect(!iwm.motor_on);
    try std.testing.expect(!iwm.q6);
    try std.testing.expect(!iwm.q7);
}

test "IWM read returns 0xFF for all registers" {
    var iwm = Iwm.init();
    // All IWM register reads should return 0xFF = "no drive connected"
    var reg: u32 = 0;
    while (reg < 16) : (reg += 1) {
        const addr: u32 = 0xE00000 + (reg << 1); // Even byte addresses
        try std.testing.expectEqual(@as(u8, 0xFF), iwm.read(addr));
    }
}

test "IWM write is silently absorbed" {
    var iwm = Iwm.init();
    // Writing should not panic or error
    iwm.write(0xE00000, 0x42);
    iwm.write(0xE0001E, 0xFF);
    // State should remain at defaults (stub ignores all writes)
    try std.testing.expectEqual(@as(u8, 0), iwm.mode);
}

test "IWM 32-bit address reads return 0xFF" {
    var iwm = Iwm.init();
    // 32-bit IWM addresses: 0x50016000-0x50017FFF
    try std.testing.expectEqual(@as(u8, 0xFF), iwm.read(0x50016000));
    try std.testing.expectEqual(@as(u8, 0xFF), iwm.read(0x50017FFE));
}

test "IWM reset restores initial state" {
    var iwm = Iwm.init();
    iwm.mode = 0x42;
    iwm.motor_on = true;
    iwm.q6 = true;
    iwm.q7 = true;
    iwm.reset();
    try std.testing.expectEqual(@as(u8, 0), iwm.mode);
    try std.testing.expect(!iwm.motor_on);
    try std.testing.expect(!iwm.q6);
    try std.testing.expect(!iwm.q7);
}
