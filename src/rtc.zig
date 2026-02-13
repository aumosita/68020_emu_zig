const std = @import("std");

/// Macintosh Real Time Clock (RTC) and PRAM (Parameter RAM)
/// Based on the custom chip used in early Macs.
pub const Rtc = struct {
    pram: [256]u8,
    seconds: u32,      // Seconds since Jan 1, 1904
    
    // Serial state machine
    state: State = .idle,
    command: u8 = 0,
    bit_count: u3,
    data_byte: u8 = 0,
    
    // Pin states (latched)
    last_clock: bool = false,
    enabled: bool = false,

    const State = enum {
        idle,
        command_in,
        data_in,
        data_out,
    };

    pub fn init() Rtc {
        var self = Rtc{
            .pram = [_]u8{0} ** 256,
            .seconds = 0xCF123456, // Dummy time
            .bit_count = 0,
        };
        // Set some sensible PRAM defaults if needed
        self.pram[0] = 0x41; // Just a placeholder
        return self;
    }

    /// Step the RTC state machine based on pin changes from VIA
    /// data_in_out is a pointer to the data line (bidirectional)
    pub fn step(self: *Rtc, clk: bool, data_in: bool, enable: bool) bool {
        // Enable is active low in some models, but we'll treat 'true' as "device selected" 
        // depending on how VIA handles it. In Mac LC, RTC Enable is usually active low.
        // We'll assume the caller passes the logical "selected" state.

        if (!enable) {
            self.state = .idle;
            self.enabled = false;
            return false;
        }

        if (!self.enabled and enable) {
            // Transaction starts
            self.state = .command_in;
            self.bit_count = 0;
            self.command = 0;
            self.enabled = true;
        }

        var bit_to_output: bool = false;

        // Rising edge of clock: latch data in (from CPU to RTC)
        if (!self.last_clock and clk) {
            switch (self.state) {
                .command_in => {
                    self.command = (self.command << 1) | @as(u8, if (data_in) 1 else 0);
                    self.bit_count +%= 1;
                    if (self.bit_count == 0) {
                        self.processCommand();
                    }
                },
                .data_in => {
                    self.data_byte = (self.data_byte << 1) | @as(u8, if (data_in) 1 else 0);
                    self.bit_count +%= 1;
                    if (self.bit_count == 0) {
                        self.writeData();
                        self.state = .idle; // Usually 1 byte per select
                    }
                },
                else => {},
            }
        }

        // Falling edge of clock: shift data out (from RTC to CPU)
        if (self.last_clock and !clk) {
            if (self.state == .data_out) {
                bit_to_output = (self.data_byte & 0x80) != 0;
                self.data_byte <<= 1;
                self.bit_count +%= 1;
                if (self.bit_count == 0) {
                    self.state = .idle;
                }
            }
        }

        self.last_clock = clk;
        return bit_to_output;
    }

    fn processCommand(self: *Rtc) void {
        const cmd = self.command;
        
        // Mac RTC Command: 1cccccca
        // Bit 7: Must be 1
        // Bit 0: 0 = Write, 1 = Read
        // Bits 1-6: Address/Command
        
        const is_read = (cmd & 0x01) != 0;
        
        if (!is_read) {
            self.state = .data_in;
        } else {
            self.state = .data_out;
            self.data_byte = self.readData(cmd);
        }
        self.bit_count = 0;
    }

    fn readData(self: *Rtc, cmd: u8) u8 {
        // Bits 5-2 determine the register
        const reg = (cmd >> 2) & 0x1F;
        
        if (reg <= 0x03) { // Seconds
            return @truncate(self.seconds >> @intCast((reg) * 8));
        }
        if (reg >= 0x10) { // PRAM
            const addr = (reg - 0x10) << 2 | ((cmd >> 1) & 0x03);
            return self.pram[addr];
        }
        return 0;
    }

    fn writeData(self: *Rtc) void {
        // TBD: Logic for writing to seconds or PRAM
        _ = self;
    }
};
