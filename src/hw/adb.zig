const std = @import("std");

/// Apple Desktop Bus (ADB) Controller
/// Implements the ADB protocol state machine for Macintosh LC.
///
/// The Mac LC uses VIA1 to communicate with ADB devices:
///   - PB4 (ST0), PB5 (ST1): State control lines
///   - Port A: Data transfer (8-bit bidirectional)
///   - CB1: ADB interrupt line
///
/// State line encoding:
///   ST1=0, ST0=0: Idle / Reset
///   ST1=0, ST0=1: Command byte transfer
///   ST1=1, ST0=0: Data transfer (even byte)
///   ST1=1, ST0=1: Data transfer (odd byte)
pub const Adb = struct {
    // ── ADB Command Encoding ──
    // Bits 7-4: Device Address (0-15)
    // Bits 3-2: Command (0=SendReset, 1=Flush, 2=Listen, 3=Talk)
    // Bits 1-0: Register number (0-3)
    pub const CMD_SEND_RESET: u2 = 0;
    pub const CMD_FLUSH: u2 = 1;
    pub const CMD_LISTEN: u2 = 2;
    pub const CMD_TALK: u2 = 3;

    // ── Default Device Addresses ──
    pub const ADDR_KEYBOARD: u4 = 2;
    pub const ADDR_MOUSE: u4 = 3;

    // ── ADB Controller State ──
    pub const State = enum {
        idle,
        command, // Receiving command byte
        talk_response, // Sending response data (Talk)
        listen_data, // Receiving data (Listen)
    };

    // ── ADB Virtual Device ──
    pub const DeviceType = enum {
        keyboard,
        mouse,
    };

    pub const AdbDevice = struct {
        address: u4,
        default_address: u4,
        handler_id: u8,
        device_type: DeviceType,
        registers: [4]u16 = .{ 0, 0, 0, 0 },
        has_data: bool = false, // SRQ pending
    };

    // ── State ──
    state: State = .idle,
    prev_st0: bool = false,
    prev_st1: bool = false,

    // Command parsing
    command_byte: u8 = 0,
    response_data: [8]u8 = .{0} ** 8,
    response_len: u8 = 0,
    response_idx: u8 = 0,
    listen_buf: [8]u8 = .{0} ** 8,
    listen_len: u8 = 0,

    // Service Request
    srq_pending: bool = false,

    // Virtual Devices
    devices: [2]AdbDevice = .{
        // Keyboard (Default addr 2, handler 2 = Extended keyboard)
        .{
            .address = ADDR_KEYBOARD,
            .default_address = ADDR_KEYBOARD,
            .handler_id = 2,
            .device_type = .keyboard,
            .registers = .{ 0xFFFF, 0, 0, 0x0202 }, // Reg3 = addr:handler
        },
        // Mouse (Default addr 3, handler 1 = Standard mouse)
        .{
            .address = ADDR_MOUSE,
            .default_address = ADDR_MOUSE,
            .handler_id = 1,
            .device_type = .mouse,
            .registers = .{ 0x8080, 0, 0, 0x0301 }, // Reg3 = addr:handler
        },
    },

    // ── Keyboard Input Queue ──
    key_queue: [16]u8 = .{0} ** 16,
    key_queue_head: u8 = 0,
    key_queue_tail: u8 = 0,

    // ── Mouse State ──
    mouse_dx: i8 = 0,
    mouse_dy: i8 = 0,
    mouse_button: bool = false, // true=released, false=pressed (active low)

    pub fn init() Adb {
        return .{};
    }

    pub fn reset(self: *Adb) void {
        self.state = .idle;
        self.command_byte = 0;
        self.response_len = 0;
        self.response_idx = 0;
        self.listen_len = 0;
        self.srq_pending = false;
        self.key_queue_head = 0;
        self.key_queue_tail = 0;
        self.mouse_dx = 0;
        self.mouse_dy = 0;
        self.mouse_button = false;

        // Reset device addresses to defaults
        for (&self.devices) |*dev| {
            dev.address = dev.default_address;
            dev.has_data = false;
        }
    }

    // ────────────────────────────────────────────
    //  VIA Interface (called when VIA Port B changes)
    // ────────────────────────────────────────────

    /// Process ADB state based on VIA signals.
    /// st0/st1: State control lines (VIA PB4/PB5)
    /// data_in: Data byte from VIA Port A
    /// Returns: Data byte to reflect back to VIA Port A
    pub fn step(self: *Adb, st0: bool, st1: bool, data_in: u8) u8 {
        // Detect state line transitions
        const old_state = self.encodeStateLine(self.prev_st1, self.prev_st0);
        const new_state = self.encodeStateLine(st1, st0);
        self.prev_st0 = st0;
        self.prev_st1 = st1;

        if (old_state == new_state) {
            // No transition — return current response byte
            return self.getCurrentResponseByte();
        }

        switch (new_state) {
            // 00: Idle / Reset
            0 => {
                if (self.state == .command) {
                    // Command fully received, process it
                    self.processCommand();
                } else if (self.state == .listen_data) {
                    self.processListenData();
                }
                // After command processing, return to idle
                if (old_state == 1) {
                    // Transition from Command → Idle: process and prepare response
                    self.state = if (self.response_len > 0) .talk_response else .idle;
                } else {
                    self.state = .idle;
                }
            },

            // 01: Command byte transfer
            1 => {
                self.state = .command;
                self.command_byte = data_in;
            },

            // 10: Even data byte
            2 => {
                switch (self.state) {
                    .talk_response => {
                        // Host reading, advance pointer
                    },
                    .idle, .command => {
                        self.state = .listen_data;
                        self.listen_len = 0;
                        if (self.listen_len < self.listen_buf.len) {
                            self.listen_buf[self.listen_len] = data_in;
                            self.listen_len += 1;
                        }
                    },
                    .listen_data => {
                        if (self.listen_len < self.listen_buf.len) {
                            self.listen_buf[self.listen_len] = data_in;
                            self.listen_len += 1;
                        }
                    },
                }
            },

            // 11: Odd data byte
            3 => {
                switch (self.state) {
                    .talk_response => {
                        self.response_idx +|= 1;
                    },
                    .listen_data => {
                        if (self.listen_len < self.listen_buf.len) {
                            self.listen_buf[self.listen_len] = data_in;
                            self.listen_len += 1;
                        }
                    },
                    else => {},
                }
            },
        }

        return self.getCurrentResponseByte();
    }

    // ────────────────────────────────────────────
    //  Command Processing
    // ────────────────────────────────────────────

    fn processCommand(self: *Adb) void {
        const addr: u4 = @truncate(self.command_byte >> 4);
        const cmd: u2 = @truncate((self.command_byte >> 2) & 0x03);

        // Reset response
        self.response_len = 0;
        self.response_idx = 0;

        switch (cmd) {
            CMD_SEND_RESET => {
                self.reset();
            },
            CMD_FLUSH => {
                // Flush device buffer
                if (self.findDevice(addr)) |dev| {
                    dev.has_data = false;
                }
            },
            CMD_TALK => {
                const reg: u2 = @truncate(self.command_byte & 0x03);
                self.handleTalk(addr, reg);
            },
            CMD_LISTEN => {
                // Listen: data will follow in subsequent transfers
                // The register is parsed from command_byte when data arrives
            },
        }

        self.updateSrq();
    }

    fn handleTalk(self: *Adb, addr: u4, reg: u2) void {
        const dev = self.findDevice(addr) orelse {
            // No device at this address — no response (SRQ timeout)
            self.response_len = 0;
            return;
        };

        switch (reg) {
            0 => {
                // Register 0: Device-specific data
                switch (dev.device_type) {
                    .keyboard => {
                        self.prepareKeyboardResponse();
                    },
                    .mouse => {
                        self.prepareMouseResponse();
                    },
                }
            },
            3 => {
                // Register 3: Device address and handler ID
                const reg3 = dev.registers[3];
                self.response_data[0] = @truncate(reg3 >> 8);
                self.response_data[1] = @truncate(reg3 & 0xFF);
                self.response_len = 2;
            },
            else => {
                // Other registers
                const val = dev.registers[reg];
                self.response_data[0] = @truncate(val >> 8);
                self.response_data[1] = @truncate(val & 0xFF);
                self.response_len = 2;
            },
        }
    }

    fn processListenData(self: *Adb) void {
        const addr: u4 = @truncate(self.command_byte >> 4);
        const reg: u2 = @truncate(self.command_byte & 0x03);

        if (self.findDevice(addr)) |dev| {
            if (self.listen_len >= 2) {
                const val: u16 = (@as(u16, self.listen_buf[0]) << 8) | self.listen_buf[1];
                dev.registers[reg] = val;

                // If writing to Register 3, update address
                if (reg == 3) {
                    dev.address = @truncate(self.listen_buf[0] & 0x0F);
                }
            }
        }
    }

    // ────────────────────────────────────────────
    //  Device-Specific Response Preparation
    // ────────────────────────────────────────────

    fn prepareKeyboardResponse(self: *Adb) void {
        if (self.key_queue_head == self.key_queue_tail) {
            // No keys pending — return 0xFF 0xFF (no key)
            self.response_data[0] = 0xFF;
            self.response_data[1] = 0xFF;
            self.response_len = 2;
            return;
        }

        // Return up to 2 key codes
        self.response_data[0] = self.dequeueKey() orelse 0xFF;
        self.response_data[1] = self.dequeueKey() orelse 0xFF;
        self.response_len = 2;
    }

    fn prepareMouseResponse(self: *Adb) void {
        // Pack mouse data: [button:1 | dy:7] [0 | dx:7]
        const button_bit: u8 = if (self.mouse_button) 0x80 else 0x00;
        const dy_7bit: u8 = @bitCast(@as(i8, @truncate(std.math.clamp(@as(i16, self.mouse_dy), -63, 63))));
        const dx_7bit: u8 = @bitCast(@as(i8, @truncate(std.math.clamp(@as(i16, self.mouse_dx), -63, 63))));

        self.response_data[0] = button_bit | (dy_7bit & 0x7F);
        self.response_data[1] = 0x00 | (dx_7bit & 0x7F);
        self.response_len = 2;

        // Clear deltas after reading
        self.mouse_dx = 0;
        self.mouse_dy = 0;
    }

    // ────────────────────────────────────────────
    //  Public Input API
    // ────────────────────────────────────────────

    /// Queue a key press/release event.
    /// key_code: ADB scan code (bit 7 = 1 for release)
    pub fn enqueueKey(self: *Adb, key_code: u8) void {
        const next = (self.key_queue_tail + 1) % @as(u8, @intCast(self.key_queue.len));
        if (next == self.key_queue_head) return; // Queue full
        self.key_queue[self.key_queue_tail] = key_code;
        self.key_queue_tail = next;

        // Set SRQ on keyboard device
        if (self.findDevice(ADDR_KEYBOARD)) |dev| {
            dev.has_data = true;
        }
        self.updateSrq();
    }

    /// Set mouse movement delta and button state.
    /// button: true=released (up), false=pressed (down). Active-low convention.
    pub fn setMouseState(self: *Adb, dx: i8, dy: i8, button: bool) void {
        self.mouse_dx +|= dx;
        self.mouse_dy +|= dy;
        self.mouse_button = button;

        if (dx != 0 or dy != 0) {
            if (self.findDevice(ADDR_MOUSE)) |dev| {
                dev.has_data = true;
            }
            self.updateSrq();
        }
    }

    // ────────────────────────────────────────────
    //  Helpers
    // ────────────────────────────────────────────

    fn encodeStateLine(_: *const Adb, st1: bool, st0: bool) u2 {
        return (@as(u2, @intFromBool(st1)) << 1) | @intFromBool(st0);
    }

    fn findDevice(self: *Adb, addr: u4) ?*AdbDevice {
        for (&self.devices) |*dev| {
            if (dev.address == addr) return dev;
        }
        return null;
    }

    fn dequeueKey(self: *Adb) ?u8 {
        if (self.key_queue_head == self.key_queue_tail) return null;
        const key = self.key_queue[self.key_queue_head];
        self.key_queue_head = (self.key_queue_head + 1) % @as(u8, @intCast(self.key_queue.len));
        return key;
    }

    fn getCurrentResponseByte(self: *Adb) u8 {
        if (self.state == .talk_response and self.response_idx < self.response_len) {
            return self.response_data[self.response_idx];
        }
        return 0;
    }

    fn updateSrq(self: *Adb) void {
        self.srq_pending = false;
        for (&self.devices) |*dev| {
            if (dev.has_data) {
                self.srq_pending = true;
                break;
            }
        }
    }

    /// Returns true if any device has a pending service request.
    pub fn hasSrq(self: *const Adb) bool {
        return self.srq_pending;
    }
};
