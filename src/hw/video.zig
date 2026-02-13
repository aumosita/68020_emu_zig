const std = @import("std");

/// Macintosh Video Controller (DAFB / V8 / Eagle style)
/// Handles framebuffer and palette (VDAC).
pub const Video = struct {
    palette: [256]u32, // ARGB8888
    palette_index: u8 = 0,
    palette_state: u8 = 0, // 0 = index, 1 = red, 2 = green, 3 = blue
    temp_color: u32 = 0,
    
    // Framebuffer properties
    vram: []u8,
    width: u32 = 512,
    height: u32 = 384,
    depth_bits: u8 = 8,

    pub fn init(allocator: std.mem.Allocator, vram_size: u32) !Video {
        const vram = try allocator.alloc(u8, vram_size);
        @memset(vram, 0);
        
        return Video{
            .palette = [_]u32{0} ** 256,
            .vram = vram,
        };
    }

    pub fn deinit(self: *Video, allocator: std.mem.Allocator) void {
        allocator.free(self.vram);
    }

    /// Read VDAC / Palette registers
    pub fn readVdac(self: *Video, addr: u32) u8 {
        _ = self; _ = addr;
        return 0; // Usually write-only for palette
    }

    /// Write VDAC / Palette registers
    pub fn writeVdac(self: *Video, addr: u32, value: u8) void {
        const offset = addr & 0xF;
        if (offset == 0x0) {
            self.palette_index = value;
            self.palette_state = 1;
        } else if (offset == 0x4) {
            switch (self.palette_state) {
                1 => { // Red
                    self.temp_color = (@as(u32, value) << 16);
                    self.palette_state = 2;
                },
                2 => { // Green
                    self.temp_color |= (@as(u32, value) << 8);
                    self.palette_state = 3;
                },
                3 => { // Blue
                    self.temp_color |= @as(u32, value);
                    self.palette[self.palette_index] = self.temp_color | 0xFF000000;
                    self.palette_index +%= 1;
                    self.palette_state = 1;
                },
                else => { self.palette_state = 1; }
            }
        }
    }
};
