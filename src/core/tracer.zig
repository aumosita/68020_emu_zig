const std = @import("std");
const M68k = @import("cpu.zig").M68k;

pub const Tracer = struct {
    file: std.fs.File,
    writer: std.io.BufferedWriter(4096, std.fs.File.Writer),
    enabled: bool = true,
    trace_instructions: bool = true,
    trace_mmio: bool = true,

    pub fn init(path: []const u8) !Tracer {
        const file = try std.fs.cwd().createFile(path, .{});
        return Tracer{
            .file = file,
            .writer = std.io.bufferedWriter(file.writer()),
        };
    }

    pub fn deinit(self: *Tracer) void {
        self.writer.flush() catch {};
        self.file.close();
    }

    pub fn traceInstruction(self: *Tracer, cpu: *const M68k, pc: u32, opcode: u16) void {
        if (!self.enabled or !self.trace_instructions) return;

        const w = self.writer.writer();
        w.print("[INST] PC={X:0>8} Op={X:0>4} SR={X:0>4} ", .{ pc, opcode, cpu.sr }) catch return;
        
        // Print Data Registers
        w.writeAll("D: ") catch return;
        for (cpu.d) |d| {
            w.print("{X:0>8} ", .{d}) catch return;
        }
        
        // Print Address Registers
        w.writeAll("A: ") catch return;
        for (cpu.a) |a| {
            w.print("{X:0>8} ", .{a}) catch return;
        }
        
        w.writeAll("\n") catch return;
    }

    pub fn traceMmio(self: *Tracer, is_write: bool, addr: u32, size: u8, val: u32) void {
        if (!self.enabled or !self.trace_mmio) return;

        const w = self.writer.writer();
        const type_str = if (is_write) "WR" else "RD";
        w.print("[MMIO] {s} Addr={X:0>8} Val={X:0>8} Size={}\n", .{ type_str, addr, val, size }) catch return;
    }

    pub fn traceException(self: *Tracer, vector: u8, pc: u32, format: u4) void {
        if (!self.enabled) return;

        const w = self.writer.writer();
        w.print("[EXCP] Vector={X:0>2} PC={X:0>8} Format={X}\n", .{ vector, pc, format }) catch return;
    }

    pub fn flush(self: *Tracer) void {
        self.writer.flush() catch {};
    }
};
