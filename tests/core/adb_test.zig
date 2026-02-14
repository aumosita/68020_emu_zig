const std = @import("std");
const testing = std.testing;
const root = @import("m68020");
const Adb = root.Adb;

test "ADB: Initial state is idle" {
    var a = Adb.init();
    try testing.expectEqual(Adb.State.idle, a.state);
    try testing.expect(!a.hasSrq());
}

test "ADB: SendReset resets all devices" {
    var a = Adb.init();

    // Enqueue a key to make keyboard have data
    a.enqueueKey(0x00); // key 'A' press
    try testing.expect(a.hasSrq());

    // Send ADB Reset command: addr=0, cmd=0 (SendReset), reg=0 → byte 0x00
    _ = a.step(false, false, 0); // Idle
    _ = a.step(true, false, 0x00); // Command: SendReset
    _ = a.step(false, false, 0); // Back to Idle → process command

    try testing.expect(!a.hasSrq());
}

test "ADB: Talk Register 3 returns device address and handler" {
    var a = Adb.init();

    // Talk Reg 3 to Keyboard (addr=2):
    // byte = (2 << 4) | (3 << 2) | 3 = 0x2F
    _ = a.step(false, false, 0); // Idle
    _ = a.step(true, false, 0x2F); // Command: Talk R3 to addr 2
    _ = a.step(false, false, 0); // Process → prepare response

    // Response should be in talk_response state
    // Reg 3 for keyboard: address=2, handler=2 → 0x0202
    try testing.expectEqual(@as(u8, 0x02), a.response_data[0]);
    try testing.expectEqual(@as(u8, 0x02), a.response_data[1]);
    try testing.expectEqual(@as(u8, 2), a.response_len);
}

test "ADB: Keyboard input enqueue and dequeue via Talk R0" {
    var a = Adb.init();

    // Enqueue two keys
    a.enqueueKey(0x00); // 'A' press
    a.enqueueKey(0x80); // 'A' release
    try testing.expect(a.hasSrq());

    // Talk R0 to keyboard (addr=2):
    // byte = (2 << 4) | (3 << 2) | 0 = 0x2C
    _ = a.step(false, false, 0);
    _ = a.step(true, false, 0x2C); // Command: Talk R0 to addr 2
    _ = a.step(false, false, 0); // Process

    try testing.expectEqual(@as(u8, 0x00), a.response_data[0]); // 'A' press
    try testing.expectEqual(@as(u8, 0x80), a.response_data[1]); // 'A' release
    try testing.expectEqual(@as(u8, 2), a.response_len);
}

test "ADB: Keyboard with no keys returns 0xFF 0xFF" {
    var a = Adb.init();

    // Talk R0 to keyboard
    _ = a.step(false, false, 0);
    _ = a.step(true, false, 0x2C);
    _ = a.step(false, false, 0);

    try testing.expectEqual(@as(u8, 0xFF), a.response_data[0]);
    try testing.expectEqual(@as(u8, 0xFF), a.response_data[1]);
}

test "ADB: Mouse state returns packed dx/dy/button" {
    var a = Adb.init();

    // Set mouse movement
    a.setMouseState(10, -5, true); // dx=10, dy=-5, button released

    // Talk R0 to mouse (addr=3):
    // byte = (3 << 4) | (3 << 2) | 0 = 0x3C
    _ = a.step(false, false, 0);
    _ = a.step(true, false, 0x3C);
    _ = a.step(false, false, 0);

    try testing.expectEqual(@as(u8, 2), a.response_len);
    // Button released = 0x80 | (dy & 0x7F)
    // dy = -5 → as u8 = 0xFB, & 0x7F = 0x7B
    const expected_y = 0x80 | (@as(u8, @bitCast(@as(i8, -5))) & 0x7F);
    try testing.expectEqual(expected_y, a.response_data[0]);
    // dx = 10 → 0x0A & 0x7F = 0x0A
    try testing.expectEqual(@as(u8, 0x0A), a.response_data[1]);
}

test "ADB: Mouse deltas cleared after read" {
    var a = Adb.init();

    a.setMouseState(20, 30, true);

    // Read mouse
    _ = a.step(false, false, 0);
    _ = a.step(true, false, 0x3C);
    _ = a.step(false, false, 0);

    try testing.expectEqual(@as(i8, 0), a.mouse_dx);
    try testing.expectEqual(@as(i8, 0), a.mouse_dy);
}

test "ADB: Talk to nonexistent device yields no response" {
    var a = Adb.init();

    // Talk R0 to addr 5 (no device):
    // byte = (5 << 4) | (3 << 2) | 0 = 0x5C
    _ = a.step(false, false, 0);
    _ = a.step(true, false, 0x5C);
    _ = a.step(false, false, 0);

    try testing.expectEqual(@as(u8, 0), a.response_len);
}

test "ADB: Reset clears key queue" {
    var a = Adb.init();

    a.enqueueKey(0x01);
    a.enqueueKey(0x02);
    a.reset();

    try testing.expectEqual(a.key_queue_head, a.key_queue_tail);
    try testing.expect(!a.hasSrq());
}
