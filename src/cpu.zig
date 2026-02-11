const std = @import("std");
const memory = @import("memory.zig");
const decoder = @import("decoder.zig");
const executor = @import("executor.zig");

pub const M68k = struct {
    const ICacheLines = 64;
    const ICacheLine = struct { valid: bool, tag: u32, word: u16 };
    pub const CoprocessorResult = union(enum) {
        handled: u32,
        unavailable: void,
        fault: u32, // fault address
    };
    pub const CoprocessorHandler = *const fn (ctx: ?*anyopaque, m68k: *M68k, opcode: u16, pc: u32) CoprocessorResult;

    d: [8]u32,
    a: [8]u32,
    pc: u32,
    sr: u16,
    vbr: u32,
    cacr: u32,
    caar: u32,
    usp: u32,
    isp: u32,
    msp: u32,
    sfc: u3,
    dfc: u3,
    pending_irq_level: u3,
    pending_irq_vector: ?u8,
    stopped: bool,
    coprocessor_handler: ?CoprocessorHandler,
    coprocessor_ctx: ?*anyopaque,
    icache: [ICacheLines]ICacheLine,
    memory: memory.Memory,
    decoder: decoder.Decoder,
    executor: executor.Executor,
    cycles: u64,
    allocator: std.mem.Allocator,
    
    pub fn init(allocator: std.mem.Allocator) M68k {
        return initWithConfig(allocator, .{});
    }
    
    pub fn initWithConfig(allocator: std.mem.Allocator, config: memory.MemoryConfig) M68k {
        return M68k{
            .d = [_]u32{0} ** 8,
            .a = [_]u32{0} ** 8,
            .pc = 0,
            .sr = 0x2700,
            .vbr = 0,
            .cacr = 0,
            .caar = 0,
            .usp = 0,
            .isp = 0,
            .msp = 0,
            .sfc = 0,
            .dfc = 0,
            .pending_irq_level = 0,
            .pending_irq_vector = null,
            .stopped = false,
            .coprocessor_handler = null,
            .coprocessor_ctx = null,
            .icache = [_]ICacheLine{.{ .valid = false, .tag = 0, .word = 0 }} ** ICacheLines,
            .memory = memory.Memory.initWithConfig(allocator, config),
            .decoder = decoder.Decoder.init(),
            .executor = executor.Executor.init(),
            .cycles = 0,
            .allocator = allocator,
        };
    }
    
    pub fn deinit(self: *M68k) void {
        self.memory.deinit();
    }
    
    pub fn reset(self: *M68k) void {
        for (&self.d) |*reg| reg.* = 0;
        for (&self.a) |*reg| reg.* = 0;
        self.a[7] = self.memory.read32(self.getExceptionVector(0)) catch 0;
        self.pc = self.memory.read32(self.getExceptionVector(1)) catch 0;
        self.sr = 0x2700;
        self.isp = self.a[7];
        self.msp = self.a[7];
        self.usp = 0;
        self.pending_irq_level = 0;
        self.pending_irq_vector = null;
        self.stopped = false;
        self.cacr = 0;
        self.caar = 0;
        self.invalidateICache();
        self.cycles = 0;
    }
    
    pub fn getExceptionVector(self: *const M68k, vector_number: u8) u32 {
        return self.vbr + (@as(u32, vector_number) * 4);
    }
    
    pub fn readWord(self: *const M68k, addr: u32) u16 {
        return self.memory.read16(addr) catch 0;
    }
    
    pub fn step(self: *M68k) !u32 {
        if (try self.handlePendingInterrupt()) {
            self.cycles += 44;
            return 44;
        }
        if (self.stopped) {
            self.cycles += 4;
            return 4;
        }
        const fetch = self.fetchInstructionWord(self.pc) catch |err| switch (err) {
            error.BusRetry => {
                self.cycles += 4;
                return 4;
            },
            error.BusHalt => {
                self.stopped = true;
                self.cycles += 4;
                return 4;
            },
            error.BusError => {
                try self.enterBusErrorFrameA(self.pc, self.pc, .{
                    .function_code = self.getProgramFunctionCode(),
                    .space = .Program,
                    .is_write = false,
                });
                self.cycles += 50;
                return 50;
            },
            else => return err,
        };
        const opcode = fetch.opcode;
        M68k.current_instance = self;
        M68k.decode_fault_addr = null;
        defer M68k.current_instance = null;
        const instruction = self.decoder.decode(opcode, self.pc, &M68k.globalReadWord) catch |err| switch (err) {
            error.IllegalInstruction => {
                try self.enterException(4, self.pc, 0, null);
                self.cycles += 34 + fetch.penalty_cycles;
                return 34 + fetch.penalty_cycles;
            },
            else => return err,
        };
        if (M68k.decode_fault_addr) |fault_addr| {
            try self.enterBusErrorFrameA(self.pc, fault_addr, .{
                .function_code = self.getProgramFunctionCode(),
                .space = .Program,
                .is_write = false,
            });
            self.cycles += 50 + fetch.penalty_cycles;
            return 50 + fetch.penalty_cycles;
        }
        const cycles_used = self.executor.execute(self, &instruction) catch |err| switch (err) {
            error.InvalidAddress, error.AddressError => {
                try self.enterBusErrorFrameA(self.pc, self.pc, .{
                    .function_code = self.dfc,
                    .space = .Data,
                    .is_write = false,
                });
                self.cycles += 50 + fetch.penalty_cycles;
                return 50 + fetch.penalty_cycles;
            },
            error.InvalidOperand, error.InvalidExtensionWord, error.InvalidControlRegister, error.Err => {
                try self.enterException(4, self.pc, 0, null);
                self.cycles += 34 + fetch.penalty_cycles;
                return 34 + fetch.penalty_cycles;
            },
            else => return err,
        };
        self.cycles += cycles_used + fetch.penalty_cycles;
        return cycles_used + fetch.penalty_cycles;
    }
    
    threadlocal var current_instance: ?*const M68k = null;
    threadlocal var decode_fault_addr: ?u32 = null;
    
    fn globalReadWord(addr: u32) u16 {
        if (M68k.current_instance) |inst| {
            const access = memory.BusAccess{
                .function_code = inst.getProgramFunctionCode(),
                .space = .Program,
                .is_write = false,
            };
            return inst.memory.read16Bus(addr, access) catch {
                M68k.decode_fault_addr = addr;
                return 0;
            };
        }
        return 0;
    }
    
    pub fn execute(self: *M68k, target_cycles: u32) !u32 {
        var executed: u32 = 0;
        while (executed < target_cycles) {
            const cycles_used = try self.step();
            executed += cycles_used;
        }
        return executed;
    }
    
    pub inline fn getFlag(self: *const M68k, comptime flag: u16) bool {
        return (self.sr & flag) != 0;
    }
    
    pub inline fn setFlag(self: *M68k, comptime flag: u16, value: bool) void {
        var sr_new = self.sr;
        if (value) {
            sr_new |= flag;
        } else {
            sr_new &= ~flag;
        }

        if (flag == FLAG_S or flag == FLAG_M) {
            self.setSR(sr_new);
            return;
        }
        self.sr = sr_new;
    }
    
    pub inline fn setFlags(self: *M68k, result: u32, size: decoder.DataSize) void {
        const mask: u32 = switch (size) {
            .Byte => 0xFF,
            .Word => 0xFFFF,
            .Long => 0xFFFFFFFF,
        };
        const masked = result & mask;
        self.setFlag(FLAG_Z, masked == 0);
        const sign_bit: u32 = switch (size) {
            .Byte => 0x80,
            .Word => 0x8000,
            .Long => 0x80000000,
        };
        self.setFlag(FLAG_N, (masked & sign_bit) != 0);
        self.setFlag(FLAG_V, false);
        self.setFlag(FLAG_C, false);
    }
    
    pub const FLAG_C: u16 = 1 << 0;
    pub const FLAG_V: u16 = 1 << 1;
    pub const FLAG_Z: u16 = 1 << 2;
    pub const FLAG_N: u16 = 1 << 3;
    pub const FLAG_X: u16 = 1 << 4;
    pub const FLAG_M: u16 = 1 << 12;
    pub const FLAG_S: u16 = 1 << 13;
    pub const StackKind = enum { User, Interrupt, Master };

    pub fn setSR(self: *M68k, new_sr: u16) void {
        const prev_sp = self.a[7];
        self.saveActiveStackPointer();
        self.sr = new_sr;
        self.loadActiveStackPointer(prev_sp);
    }

    pub fn setInterruptLevel(self: *M68k, level: u3) void {
        self.setInterruptRequest(level, null);
    }

    pub fn setCoprocessorHandler(self: *M68k, handler: ?CoprocessorHandler, ctx: ?*anyopaque) void {
        self.coprocessor_handler = handler;
        self.coprocessor_ctx = ctx;
    }

    pub fn setCacr(self: *M68k, value: u32) void {
        if ((value & 0x8) != 0) {
            self.invalidateICache();
        }
        self.cacr = value & ~@as(u32, 0x8);
    }

    fn isICacheEnabled(self: *const M68k) bool {
        return (self.cacr & 0x1) != 0;
    }

    fn invalidateICache(self: *M68k) void {
        for (&self.icache) |*line| {
            line.* = .{ .valid = false, .tag = 0, .word = 0 };
        }
    }

    pub fn getProgramFunctionCode(self: *const M68k) u3 {
        return if ((self.sr & FLAG_S) != 0) 0b110 else 0b010;
    }

    fn fetchInstructionWord(self: *M68k, addr: u32) !struct { opcode: u16, penalty_cycles: u32 } {
        const access = memory.BusAccess{
            .function_code = self.getProgramFunctionCode(),
            .space = .Program,
            .is_write = false,
        };
        if (!self.isICacheEnabled()) {
            return .{ .opcode = try self.memory.read16Bus(addr, access), .penalty_cycles = 0 };
        }
        const word_addr = addr >> 1;
        const index: usize = @intCast(word_addr & (ICacheLines - 1));
        const tag = word_addr >> std.math.log2_int(u32, ICacheLines);
        const line = self.icache[index];
        if (line.valid and line.tag == tag) {
            return .{ .opcode = line.word, .penalty_cycles = 0 };
        }
        const fetched = try self.memory.read16Bus(addr, access);
        self.icache[index] = .{ .valid = true, .tag = tag, .word = fetched };
        return .{ .opcode = fetched, .penalty_cycles = 2 };
    }

    fn enterBusErrorFrameA(self: *M68k, return_pc: u32, fault_addr: u32, access: memory.BusAccess) !void {
        const old_sr = self.sr;
        var sr_new = self.sr | FLAG_S;
        sr_new &= ~FLAG_M;
        self.setSR(sr_new);

        self.a[7] -= 24;
        try self.memory.write16(self.a[7], old_sr);
        try self.memory.write32(self.a[7] + 2, return_pc);
        try self.memory.write16(self.a[7] + 6, (@as(u16, 0xA) << 12) | (@as(u16, 2) * 4));
        try self.memory.write32(self.a[7] + 8, fault_addr);
        const access_word: u16 = (@as(u16, access.function_code) << 13) |
            (if (access.space == .Program) @as(u16, 1) << 12 else 0) |
            (if (access.is_write) @as(u16, 1) << 11 else 0);
        try self.memory.write16(self.a[7] + 12, access_word);
        try self.memory.write16(self.a[7] + 14, 0);
        try self.memory.write16(self.a[7] + 16, 0);
        try self.memory.write16(self.a[7] + 18, 0);
        try self.memory.write16(self.a[7] + 20, 0);
        try self.memory.write16(self.a[7] + 22, 0);

        self.pc = self.memory.read32(self.getExceptionVector(2)) catch 0;
    }

    pub fn raiseBusError(self: *M68k, fault_addr: u32, access: memory.BusAccess) !void {
        try self.enterBusErrorFrameA(self.pc, fault_addr, access);
    }

    pub fn setInterruptVector(self: *M68k, level: u3, vector: u8) void {
        self.setInterruptRequest(level, vector);
    }

    pub fn setSpuriousInterrupt(self: *M68k, level: u3) void {
        self.setInterruptRequest(level, 24);
    }

    pub fn getStackPointer(self: *const M68k, kind: StackKind) u32 {
        const active = activeStackKind(self.sr);
        if (active == kind) return self.a[7];
        return switch (kind) {
            .User => self.usp,
            .Interrupt => self.isp,
            .Master => self.msp,
        };
    }

    pub fn setStackPointer(self: *M68k, kind: StackKind, value: u32) void {
        switch (kind) {
            .User => self.usp = value,
            .Interrupt => self.isp = value,
            .Master => self.msp = value,
        }
        if (activeStackKind(self.sr) == kind) {
            self.a[7] = value;
        }
    }

    pub fn pushExceptionFrame(self: *M68k, status_word: u16, return_pc: u32, vector: u8, format: u4) !void {
        self.a[7] -= 8;
        try self.memory.write16(self.a[7], status_word);
        try self.memory.write32(self.a[7] + 2, return_pc);
        try self.memory.write16(self.a[7] + 6, (@as(u16, format) << 12) | (@as(u16, vector) * 4));
    }

    pub fn enterException(self: *M68k, vector: u8, return_pc: u32, format: u4, new_ipl: ?u3) !void {
        const old_sr = self.sr;
        var sr_new = self.sr | FLAG_S;
        sr_new &= ~FLAG_M; // Interrupt/exception entry uses ISP on 68020.
        if (new_ipl) |level| {
            sr_new = (sr_new & 0xF8FF) | (@as(u16, level) << 8);
        }
        self.setSR(sr_new);
        try self.pushExceptionFrame(old_sr, return_pc, vector, format);
        self.pc = try self.memory.read32(self.getExceptionVector(vector));
    }

    fn activeStackKind(sr: u16) StackKind {
        const supervisor = (sr & FLAG_S) != 0;
        if (!supervisor) return .User;
        if ((sr & FLAG_M) != 0) return .Master;
        return .Interrupt;
    }

    fn saveActiveStackPointer(self: *M68k) void {
        switch (activeStackKind(self.sr)) {
            .User => self.usp = self.a[7],
            .Interrupt => self.isp = self.a[7],
            .Master => self.msp = self.a[7],
        }
    }

    fn loadActiveStackPointer(self: *M68k, fallback_sp: u32) void {
        self.a[7] = switch (activeStackKind(self.sr)) {
            .User => blk: {
                if (self.usp == 0) self.usp = fallback_sp;
                break :blk self.usp;
            },
            .Interrupt => blk: {
                if (self.isp == 0) self.isp = fallback_sp;
                break :blk self.isp;
            },
            .Master => blk: {
                if (self.msp == 0) self.msp = fallback_sp;
                break :blk self.msp;
            },
        };
    }

    fn handlePendingInterrupt(self: *M68k) !bool {
        if (self.pending_irq_level == 0) return false;
        const current_mask: u3 = @truncate((self.sr >> 8) & 0x7);
        if (self.pending_irq_level != 7 and self.pending_irq_level <= current_mask) return false;

        const level = self.pending_irq_level;
        const vector_override = self.pending_irq_vector;
        self.pending_irq_level = 0;
        self.pending_irq_vector = null;
        const vector: u8 = vector_override orelse (24 + @as(u8, level)); // Autovector level 1..7
        try self.enterException(vector, self.pc, 0, level);
        self.stopped = false;
        return true;
    }

    fn setInterruptRequest(self: *M68k, level: u3, vector: ?u8) void {
        if (level == 0) {
            self.pending_irq_level = 0;
            self.pending_irq_vector = null;
            return;
        }

        if (level > self.pending_irq_level) {
            self.pending_irq_level = level;
            self.pending_irq_vector = vector;
            return;
        }

        if (level == self.pending_irq_level and vector != null and self.pending_irq_vector == null) {
            self.pending_irq_vector = vector;
        }
    }
};

const CoprocTestContext = struct {
    called: bool = false,
    emulate_unavailable: bool = false,
};

fn coprocTestHandler(ctx: ?*anyopaque, m68k: *M68k, opcode: u16, _: u32) M68k.CoprocessorResult {
    if (ctx == null) return .{ .unavailable = {} };
    const typed: *CoprocTestContext = @ptrCast(@alignCast(ctx.?));
    typed.called = true;
    if (typed.emulate_unavailable) return .{ .unavailable = {} };

    // Minimal software-FPU demonstration: F-line opcode writes 1.0f to D0.
    if ((opcode & 0xF000) == 0xF000) {
        m68k.d[0] = 0x3F800000;
        return .{ .handled = 12 };
    }
    return .{ .unavailable = {} };
}

test "M68k initialization" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();
    try std.testing.expectEqual(@as(u32, 0), m68k.pc);
    try std.testing.expectEqual(@as(u16, 0x2700), m68k.sr);
}

test "M68k MOVEC VBR" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();
    m68k.d[0] = 0x12345678;
    try m68k.memory.write16(0x1000, 0x4E7B);
    try m68k.memory.write16(0x1002, 0x0801);
    m68k.pc = 0x1000;
    _ = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0x12345678), m68k.vbr);
}

test "M68k instruction cache hit/miss and invalidate through CACR" {
    const allocator = std.testing.allocator;
    var m68k = M68k.initWithConfig(allocator, .{ .size = 64 * 1024 * 1024 });
    defer m68k.deinit();

    try m68k.memory.write16(0x01000000, 0x4E71); // NOP
    m68k.pc = 0x01000000;

    // I-cache off: no penalty.
    const c0 = try m68k.step();
    try std.testing.expectEqual(@as(u32, 4), c0);

    // Enable I-cache (bit0) through MOVEC D0,CACR.
    try m68k.memory.write16(0x1000, 0x4E7B);
    try m68k.memory.write16(0x1002, 0x0002);
    m68k.d[0] = 0x00000001;
    m68k.pc = 0x1000;
    _ = try m68k.step();

    // First fetch misses (+2), second fetch hits (+0).
    m68k.pc = 0x01000000;
    const c1 = try m68k.step();
    try std.testing.expectEqual(@as(u32, 6), c1);
    m68k.pc = 0x01000000;
    const c2 = try m68k.step();
    try std.testing.expectEqual(@as(u32, 4), c2);

    // Invalidate through CACR write with clear bit (bit3).
    m68k.d[0] = 0x00000009; // enable + invalidate request
    m68k.pc = 0x1000;
    _ = try m68k.step();

    // Must miss again after invalidation.
    m68k.pc = 0x01000000;
    const c3 = try m68k.step();
    try std.testing.expectEqual(@as(u32, 6), c3);
}

test "M68k RTE - Return from Exception" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();
    m68k.a[7] = 0x2000;
    try m68k.memory.write16(0x2000, 0x0015);
    try m68k.memory.write32(0x2002, 0x00004000);
    try m68k.memory.write16(0x2006, 0x0000);
    try m68k.memory.write16(0x1000, 0x4E73);
    m68k.pc = 0x1000;
    _ = try m68k.step();
    try std.testing.expectEqual(@as(u16, 0x0015), m68k.sr);
    try std.testing.expectEqual(@as(u32, 0x4000), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x2008), m68k.a[7]);
}

test "M68k TRAP - Software Interrupt" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();
    const vector_addr = m68k.getExceptionVector(32);
    try m68k.memory.write32(vector_addr, 0x00005000);
    m68k.a[7] = 0x3000;
    m68k.sr = 0x0000;
    try m68k.memory.write16(0x1000, 0x4E40);
    m68k.pc = 0x1000;
    _ = try m68k.step();
    const sp = 0x3000 - 8;
    try std.testing.expectEqual(@as(u16, 0x0000), try m68k.memory.read16(sp));
    try std.testing.expectEqual(@as(u32, 0x1002), try m68k.memory.read32(sp + 2));
    try std.testing.expectEqual(@as(u32, 0x5000), m68k.pc);
}

test "M68k bus error during instruction fetch creates format A frame" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    try m68k.memory.write32(m68k.getExceptionVector(2), 0x6200);
    m68k.pc = m68k.memory.size - 1; // read16 fetch will fault
    m68k.a[7] = 0x6400;
    m68k.setSR(0x2000);

    const cycles = try m68k.step();
    try std.testing.expectEqual(@as(u32, 50), cycles);
    try std.testing.expectEqual(@as(u32, 0x6200), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x63E8), m68k.a[7]); // 24-byte format A frame
    try std.testing.expectEqual(@as(u16, 0xA008), try m68k.memory.read16(0x63EE)); // format A, vector 2
}

test "M68k ABCD - Add BCD" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();
    m68k.d[0] = 0x25;
    m68k.d[1] = 0x17;
    try m68k.memory.write16(0x1000, 0xC101);
    m68k.pc = 0x1000;
    _ = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0x42), m68k.d[0] & 0xFF);
}

test "M68k MOVEP - Move Peripheral" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();
    m68k.d[0] = 0x12345678;
    m68k.a[0] = 0x2000;
    try m68k.memory.write16(0x1000, 0x01C8);
    try m68k.memory.write16(0x1002, 0x0000);
    m68k.pc = 0x1000;
    _ = try m68k.step();
    try std.testing.expectEqual(@as(u8, 0x12), try m68k.memory.read8(0x2000));
    try std.testing.expectEqual(@as(u8, 0x34), try m68k.memory.read8(0x2002));
}

test "M68k CAS2 - Dual Compare and Swap" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();
    try m68k.memory.write32(0x2000, 100);
    try m68k.memory.write32(0x3000, 200);
    m68k.d[0] = 100; // Dc1
    m68k.d[1] = 200; // Dc2
    m68k.d[2] = 888; // Du1
    m68k.d[3] = 999; // Du2
    m68k.a[0] = 0x2000;
    m68k.a[1] = 0x3000;
    try m68k.memory.write16(0x1000, 0x0EFC);
    try m68k.memory.write16(0x1002, 0x8200); // A0, Du2, Dc0
    try m68k.memory.write16(0x1004, 0x9301); // A1, Du3, Dc1
    m68k.pc = 0x1000;
    _ = try m68k.step();
    try std.testing.expectEqual(@as(u32, 888), try m68k.memory.read32(0x2000));
    try std.testing.expectEqual(@as(u32, 999), try m68k.memory.read32(0x3000));
}

test "M68k CMPM - Compare Memory with Post-Increment" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();
    
    // Test CMPM.L (Ay)+,(Ax)+
    // Setup: A0 points to value 0x12345678, A1 points to value 0x12345678 (equal)
    m68k.a[0] = 0x1000;
    m68k.a[1] = 0x2000;
    try m68k.memory.write32(0x1000, 0x12345678);
    try m68k.memory.write32(0x2000, 0x12345678);
    
    // CMPM.L (A1)+,(A0)+ - opcode: 0xB189 (size=10, Ax=0, Ay=1)
    try m68k.memory.write16(0x100, 0xB189);
    m68k.pc = 0x100;
    _ = try m68k.step();
    
    // Check: Z flag should be set (equal), both pointers incremented by 4
    try std.testing.expect((m68k.sr & M68k.FLAG_Z) != 0);
    try std.testing.expectEqual(@as(u32, 0x1004), m68k.a[0]);
    try std.testing.expectEqual(@as(u32, 0x2004), m68k.a[1]);
    
    // Test CMPM.W with different values
    m68k.a[2] = 0x3000;
    m68k.a[3] = 0x4000;
    try m68k.memory.write16(0x3000, 0x1234);
    try m68k.memory.write16(0x4000, 0x5678);
    
    // CMPM.W (A3)+,(A2)+ - opcode: 0xB54B (size=01, Ax=2, Ay=3)
    try m68k.memory.write16(0x102, 0xB54B);
    m68k.pc = 0x102;
    _ = try m68k.step();
    
    // Check: Z flag should be clear (not equal), N flag set (negative result)
    try std.testing.expect((m68k.sr & M68k.FLAG_Z) == 0);
    try std.testing.expect((m68k.sr & M68k.FLAG_N) != 0);
    try std.testing.expectEqual(@as(u32, 0x3002), m68k.a[2]);
    try std.testing.expectEqual(@as(u32, 0x4002), m68k.a[3]);
}

test "M68k ABCD - Add BCD with Extend" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();
    
    // Test ABCD D1,D0 - Add BCD digits
    // 0x29 + 0x48 = 0x77 in BCD
    m68k.d[0] = 0x29;
    m68k.d[1] = 0x48;
    m68k.sr &= ~M68k.FLAG_X; // Clear X flag
    
    // ABCD D1,D0 - opcode: 0xC101 (Dx=0, Dy=1, mode=register)
    try m68k.memory.write16(0x100, 0xC101);
    m68k.pc = 0x100;
    _ = try m68k.step();
    
    try std.testing.expectEqual(@as(u8, 0x77), @as(u8, @truncate(m68k.d[0])));
    try std.testing.expect((m68k.sr & M68k.FLAG_C) == 0); // No carry
    
    // Test with carry: 0x99 + 0x01 = 0x00 with carry
    m68k.d[2] = 0x99;
    m68k.d[3] = 0x01;
    m68k.sr &= ~M68k.FLAG_X;
    
    // ABCD D3,D2 - opcode: 0xC503
    try m68k.memory.write16(0x102, 0xC503);
    m68k.pc = 0x102;
    _ = try m68k.step();
    
    try std.testing.expectEqual(@as(u8, 0x00), @as(u8, @truncate(m68k.d[2])));
    try std.testing.expect((m68k.sr & M68k.FLAG_C) != 0); // Carry set
    try std.testing.expect((m68k.sr & M68k.FLAG_X) != 0); // Extend set
}

test "M68k SBCD - Subtract BCD with Extend" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();
    
    // Test SBCD D1,D0 - Subtract BCD
    // 0x77 - 0x48 = 0x29 in BCD
    m68k.d[0] = 0x77;
    m68k.d[1] = 0x48;
    m68k.sr &= ~M68k.FLAG_X;
    
    // SBCD D1,D0 - opcode: 0x8101
    try m68k.memory.write16(0x100, 0x8101);
    m68k.pc = 0x100;
    _ = try m68k.step();
    
    try std.testing.expectEqual(@as(u8, 0x29), @as(u8, @truncate(m68k.d[0])));
    try std.testing.expect((m68k.sr & M68k.FLAG_C) == 0); // No borrow
}

test "M68k NBCD - Negate BCD with Extend" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();
    
    // Test NBCD D0 - Negate BCD
    // 0x00 - 0x48 = 0x52 in BCD (with borrow)
    m68k.d[0] = 0x48;
    m68k.sr &= ~M68k.FLAG_X;
    
    // NBCD D0 - opcode: 0x4800
    try m68k.memory.write16(0x100, 0x4800);
    m68k.pc = 0x100;
    _ = try m68k.step();
    
    try std.testing.expectEqual(@as(u8, 0x52), @as(u8, @truncate(m68k.d[0])));
    try std.testing.expect((m68k.sr & M68k.FLAG_C) != 0); // Borrow set
}

test "M68k MOVEC - Control Register Access" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();
    
    // Test MOVEC D0,SFC - Move to SFC (Source Function Code)
    m68k.d[0] = 5;
    // MOVEC D0,SFC - opcode: 0x4E7B 0x0000 (D0=0x0000, SFC=0)
    try m68k.memory.write16(0x100, 0x4E7B);
    try m68k.memory.write16(0x102, 0x0000);
    m68k.pc = 0x100;
    _ = try m68k.step();
    
    try std.testing.expectEqual(@as(u3, 5), m68k.sfc);
    
    // Test MOVEC D1,DFC - Move to DFC (Destination Function Code)
    m68k.d[1] = 3;
    // MOVEC D1,DFC - opcode: 0x4E7B 0x1001 (D1=0x1000, DFC=1)
    try m68k.memory.write16(0x104, 0x4E7B);
    try m68k.memory.write16(0x106, 0x1001);
    m68k.pc = 0x104;
    _ = try m68k.step();
    
    try std.testing.expectEqual(@as(u3, 3), m68k.dfc);
    
    // Test MOVEC A0,USP - Move to USP (User Stack Pointer)
    m68k.a[0] = 0x12345678;
    // MOVEC A0,USP - opcode: 0x4E7B 0x8800 (A0=0x8000, USP=0x800)
    try m68k.memory.write16(0x108, 0x4E7B);
    try m68k.memory.write16(0x10A, 0x8800);
    m68k.pc = 0x108;
    _ = try m68k.step();
    
    try std.testing.expectEqual(@as(u32, 0x12345678), m68k.usp);
    
    // Test MOVEC VBR,D2 - Move from VBR
    m68k.vbr = 0xABCDEF00;
    // MOVEC VBR,D2 - opcode: 0x4E7A 0x2801 (D2=0x2000, VBR=0x801)
    try m68k.memory.write16(0x10C, 0x4E7A);
    try m68k.memory.write16(0x10E, 0x2801);
    m68k.pc = 0x10C;
    _ = try m68k.step();
    
    try std.testing.expectEqual(@as(u32, 0xABCDEF00), m68k.d[2]);
    
    // Test MOVEC CACR,D3 - Move from CACR (Cache Control Register)
    m68k.cacr = 0x00000101;
    // MOVEC CACR,D3 - opcode: 0x4E7A 0x3002 (D3=0x3000, CACR=2)
    try m68k.memory.write16(0x110, 0x4E7A);
    try m68k.memory.write16(0x112, 0x3002);
    m68k.pc = 0x110;
    _ = try m68k.step();
    
    try std.testing.expectEqual(@as(u32, 0x00000101), m68k.d[3]);
}

test "M68k MOVEC privilege violation in user mode" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    // MOVEC D0,SFC in user mode must trap to vector 8.
    try m68k.memory.write32(m68k.getExceptionVector(8), 0xD200);
    try m68k.memory.write16(0xD100, 0x4E7B);
    try m68k.memory.write16(0xD102, 0x0000);

    m68k.pc = 0xD100;
    m68k.a[7] = 0x4800;
    m68k.setSR(0x0000);
    m68k.d[0] = 7;
    _ = try m68k.step();

    try std.testing.expectEqual(@as(u32, 0xD200), m68k.pc);
    try std.testing.expectEqual(@as(u3, 0), m68k.sfc);
}

test "M68k MOVEP - Move Peripheral Data" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();
    
    // Test MOVEP.W (d16,Ay),Dx - Memory to Register (Word)
    try m68k.memory.write8(0x1000, 0x12);
    try m68k.memory.write8(0x1002, 0x34);
    m68k.a[0] = 0x1000;
    
    // MOVEP.W 0(A0),D0 - opcode: 0x0148 0x0000
    try m68k.memory.write16(0x100, 0x0148);
    try m68k.memory.write16(0x102, 0x0000);
    m68k.pc = 0x100;
    
    const cycles = try m68k.step();
    
    try std.testing.expectEqual(@as(u32, 16), cycles);
    try std.testing.expectEqual(@as(u32, 0x104), m68k.pc);
    try std.testing.expectEqual(@as(u16, 0x1234), @as(u16, @truncate(m68k.d[0])));
}

test "M68k BFCHG - Bit Field Change" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();
    
    // Test BFCHG D0{4:8} - Change bits 4-11 (8 bits starting at offset 4)
    m68k.d[0] = 0x00000F00; // Bits 8-11 set (0x0F00)
    
    // BFCHG D0{4:8} - opcode: 0xEAC0 ext: 0x0108 (offset=4, width=8)
    try m68k.memory.write16(0x100, 0xEAC0);
    try m68k.memory.write16(0x102, 0x0108); // offset=4 (bits 10-6), width=8 (bits 4-0)
    m68k.pc = 0x100;
    _ = try m68k.step();
    
    // Bits 4-11 flipped: bits 4-7 (0->1=0xF0), bits 8-11 (1->0=0x00)
    try std.testing.expectEqual(@as(u32, 0x000000F0), m68k.d[0]);
}

test "M68k BFSET - Bit Field Set" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();
    
    // Test BFSET D0{0:16} - Set bits 0-15
    m68k.d[0] = 0x00000000;
    
    // BFSET D0{0:16} - opcode: 0xEEC0 ext: 0x0010 (offset=0, width=16)
    try m68k.memory.write16(0x100, 0xEEC0);
    try m68k.memory.write16(0x102, 0x0010);
    m68k.pc = 0x100;
    _ = try m68k.step();
    
    try std.testing.expectEqual(@as(u32, 0x0000FFFF), m68k.d[0]);
}

test "M68k BFCLR - Bit Field Clear" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();
    
    // Test BFCLR D1{8:8} - Clear bits 8-15
    m68k.d[1] = 0xFFFFFFFF;
    
    // BFCLR D1{8:8} - opcode: 0xECC1 ext: 0x0208 (offset=8, width=8)
    try m68k.memory.write16(0x100, 0xECC1);
    try m68k.memory.write16(0x102, 0x0208);
    m68k.pc = 0x100;
    _ = try m68k.step();
    
    try std.testing.expectEqual(@as(u32, 0xFFFF00FF), m68k.d[1]);
}

test "M68k RTE - Return from Exception with 68020 Stack Frame" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();
    
    // Test Format 0 (short format, 8 bytes)
    m68k.a[7] = 0x2000;
    try m68k.memory.write16(0x2000, 0x2700); // SR (supervisor mode)
    try m68k.memory.write32(0x2002, 0x1000); // PC
    try m68k.memory.write16(0x2006, 0x0018); // Format 0, Vector 6 (CHK)
    
    // RTE - opcode: 0x4E73
    try m68k.memory.write16(0x100, 0x4E73);
    m68k.pc = 0x100;
    _ = try m68k.step();
    
    try std.testing.expectEqual(@as(u16, 0x2700), m68k.sr);
    try std.testing.expectEqual(@as(u32, 0x1000), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x2008), m68k.a[7]); // SP += 8 (format 0)
    
    // Test Format 2 (6-word format, 12 bytes)
    m68k.a[7] = 0x3000;
    try m68k.memory.write16(0x3000, 0x2000); // SR
    try m68k.memory.write32(0x3002, 0x2000); // PC
    try m68k.memory.write16(0x3006, 0x201C); // Format 2, Vector 7 (TRAPV)
    
    m68k.pc = 0x100;
    _ = try m68k.step();
    
    try std.testing.expectEqual(@as(u16, 0x2000), m68k.sr);
    try std.testing.expectEqual(@as(u32, 0x2000), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x300C), m68k.a[7]); // SP += 12 (format 2)

    // Test Format 9 (coprocessor mid-instruction, 20 bytes)
    m68k.a[7] = 0x4000;
    try m68k.memory.write16(0x4000, 0x2100); // SR
    try m68k.memory.write32(0x4002, 0x3000); // PC
    try m68k.memory.write16(0x4006, 0x902C); // Format 9, Vector 11

    m68k.pc = 0x100;
    _ = try m68k.step();

    try std.testing.expectEqual(@as(u16, 0x2100), m68k.sr);
    try std.testing.expectEqual(@as(u32, 0x3000), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x4014), m68k.a[7]); // SP += 20 (format 9)

    // Test Format A (short bus cycle fault, 24 bytes)
    m68k.a[7] = 0x5000;
    try m68k.memory.write16(0x5000, 0x2700); // SR
    try m68k.memory.write32(0x5002, 0x4000); // PC
    try m68k.memory.write16(0x5006, 0xA004); // Format A, Vector 1

    m68k.pc = 0x100;
    _ = try m68k.step();

    try std.testing.expectEqual(@as(u16, 0x2700), m68k.sr);
    try std.testing.expectEqual(@as(u32, 0x4000), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x5018), m68k.a[7]); // SP += 24 (format A)
}

test "M68k TRAP - Exception with Format/Vector Word" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();
    
    // Setup exception vector for TRAP #5 (vector 37 = 0x94)
    try m68k.memory.write32(37 * 4, 0x5000); // Exception handler at 0x5000
    
    m68k.a[7] = 0x2000; // Stack pointer
    m68k.sr = 0x2700;
    
    // TRAP #5 - opcode: 0x4E45
    try m68k.memory.write16(0x100, 0x4E45);
    m68k.pc = 0x100;
    _ = try m68k.step();
    
    // Check stack frame
    try std.testing.expectEqual(@as(u16, 0x2700), try m68k.memory.read16(0x1FF8)); // SR
    try std.testing.expectEqual(@as(u32, 0x0102), try m68k.memory.read32(0x1FFA)); // PC (after TRAP)
    const fv = try m68k.memory.read16(0x1FFE); // Format/Vector
    const format = fv >> 12;
    const vector = (fv & 0xFFF) / 4;
    try std.testing.expectEqual(@as(u4, 0), format); // Format 0
    try std.testing.expectEqual(@as(u8, 37), @as(u8, @truncate(vector))); // Vector 37 (TRAP #5)
    
    // Check PC jumped to exception handler
    try std.testing.expectEqual(@as(u32, 0x5000), m68k.pc);
    // Check supervisor mode
    try std.testing.expect((m68k.sr & 0x2000) != 0);
}

test "M68k stack pointer banking (USP/ISP/MSP)" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    m68k.setSR(0x0000); // user stack
    m68k.a[7] = 0x1111;

    m68k.setSR(M68k.FLAG_S); // interrupt stack
    m68k.a[7] = 0x2222;

    m68k.setSR(M68k.FLAG_S | M68k.FLAG_M); // master stack
    m68k.a[7] = 0x3333;

    m68k.setSR(0x0000);
    try std.testing.expectEqual(@as(u32, 0x1111), m68k.a[7]);

    m68k.setSR(M68k.FLAG_S);
    try std.testing.expectEqual(@as(u32, 0x2222), m68k.a[7]);

    m68k.setSR(M68k.FLAG_S | M68k.FLAG_M);
    try std.testing.expectEqual(@as(u32, 0x3333), m68k.a[7]);
}

test "M68k IRQ autovector handling" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    // IRQ level 3 autovector = vector 27
    try m68k.memory.write32(m68k.getExceptionVector(27), 0x4000);
    try m68k.memory.write16(0x1000, 0x4E71); // NOP

    m68k.pc = 0x1000;
    m68k.a[7] = 0x3000;
    m68k.setSR(0x2000); // supervisor, mask 0
    m68k.setInterruptLevel(3);

    _ = try m68k.step();

    try std.testing.expectEqual(@as(u32, 0x4000), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x2FF8), m68k.a[7]);
    try std.testing.expectEqual(@as(u16, 0x2000), try m68k.memory.read16(0x2FF8)); // stacked SR
    try std.testing.expectEqual(@as(u32, 0x1000), try m68k.memory.read32(0x2FFA)); // stacked PC
    try std.testing.expectEqual(@as(u16, 27 * 4), try m68k.memory.read16(0x2FFE)); // format/vector word
}

test "M68k IRQ vector override handling" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    // Use explicit vector 0x64 instead of autovector.
    try m68k.memory.write32(m68k.getExceptionVector(0x64), 0x4800);
    try m68k.memory.write16(0x1200, 0x4E71); // NOP

    m68k.pc = 0x1200;
    m68k.a[7] = 0x3400;
    m68k.setSR(0x2000); // supervisor, mask 0
    m68k.setInterruptVector(2, 0x64);

    _ = try m68k.step();

    try std.testing.expectEqual(@as(u32, 0x4800), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x33F8), m68k.a[7]);
    try std.testing.expectEqual(@as(u16, 0x64 * 4), try m68k.memory.read16(0x33FE)); // vector word
}

test "M68k spurious interrupt handling" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    // Vector 24 is spurious interrupt.
    try m68k.memory.write32(m68k.getExceptionVector(24), 0x4900);
    try m68k.memory.write16(0x1300, 0x4E71); // NOP

    m68k.pc = 0x1300;
    m68k.a[7] = 0x3500;
    m68k.setSR(0x2000); // supervisor, mask 0
    m68k.setSpuriousInterrupt(2);

    _ = try m68k.step();

    try std.testing.expectEqual(@as(u32, 0x4900), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x34F8), m68k.a[7]);
    try std.testing.expectEqual(@as(u16, 24 * 4), try m68k.memory.read16(0x34FE)); // spurious vector word
}

test "M68k nested IRQ preemption by higher level" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    // Level 2 autovector (26) handler and level 5 autovector (29) handler.
    try m68k.memory.write32(m68k.getExceptionVector(26), 0x4A00);
    try m68k.memory.write32(m68k.getExceptionVector(29), 0x4B00);
    try m68k.memory.write16(0x1400, 0x4E71); // main NOP
    try m68k.memory.write16(0x4A00, 0x4E71); // level2 handler NOP
    try m68k.memory.write16(0x4A02, 0x4E71); // level2 handler NOP

    m68k.pc = 0x1400;
    m68k.a[7] = 0x3600;
    m68k.setSR(0x2000); // supervisor, mask 0

    // Enter level 2 IRQ.
    m68k.setInterruptLevel(2);
    _ = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0x4A00), m68k.pc);
    try std.testing.expectEqual(@as(u3, 2), @as(u3, @truncate((m68k.sr >> 8) & 7)));

    // Lower level (1) must be masked while in level 2 handler.
    m68k.setInterruptLevel(1);
    _ = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0x4A02), m68k.pc); // handler NOP executed

    // Higher level (5) must preempt immediately.
    m68k.setInterruptLevel(5);
    _ = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0x4B00), m68k.pc);
    try std.testing.expectEqual(@as(u3, 5), @as(u3, @truncate((m68k.sr >> 8) & 7)));
}

test "M68k Line-F opcode enters coprocessor unavailable exception" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    // Line-1111 emulator vector (11)
    try m68k.memory.write32(m68k.getExceptionVector(11), 0x5A00);
    try m68k.memory.write16(0x1500, 0xF200); // representative coprocessor opcode (F-line)

    m68k.pc = 0x1500;
    m68k.a[7] = 0x3700;
    m68k.setSR(0x0000); // user mode

    _ = try m68k.step();

    try std.testing.expectEqual(@as(u32, 0x5A00), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x36F8), m68k.a[7]);
    try std.testing.expectEqual(@as(u16, 0x0000), try m68k.memory.read16(0x36F8)); // stacked SR
    try std.testing.expectEqual(@as(u32, 0x1500), try m68k.memory.read32(0x36FA)); // faulting PC
    try std.testing.expectEqual(@as(u16, 11 * 4), try m68k.memory.read16(0x36FE)); // vector word
    try std.testing.expect((m68k.sr & M68k.FLAG_S) != 0); // now supervisor
}

test "M68k coprocessor handler can emulate F-line without vector 11" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    var ctx = CoprocTestContext{};
    m68k.setCoprocessorHandler(coprocTestHandler, &ctx);
    try m68k.memory.write16(0x1510, 0xF200); // representative F-line opcode
    m68k.pc = 0x1510;
    m68k.setSR(0x2000);

    const cycles = try m68k.step();
    try std.testing.expectEqual(@as(u32, 12), cycles);
    try std.testing.expect(ctx.called);
    try std.testing.expectEqual(@as(u32, 0x1512), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x3F800000), m68k.d[0]); // 1.0f bit pattern
}

test "M68k coprocessor handler may defer to unavailable vector 11" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    var ctx = CoprocTestContext{ .emulate_unavailable = true };
    m68k.setCoprocessorHandler(coprocTestHandler, &ctx);
    try m68k.memory.write32(m68k.getExceptionVector(11), 0x5A80);
    try m68k.memory.write16(0x1520, 0xF280);
    m68k.pc = 0x1520;
    m68k.a[7] = 0x3700;
    m68k.setSR(0x0000);

    _ = try m68k.step();
    try std.testing.expect(ctx.called);
    try std.testing.expectEqual(@as(u32, 0x5A80), m68k.pc);
}

test "M68k UNKNOWN opcode enters illegal instruction exception" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    try m68k.memory.write32(m68k.getExceptionVector(4), 0x5B00); // illegal vector
    try m68k.memory.write16(0x1600, 0x4E7C); // unmatched group-4 opcode

    m68k.pc = 0x1600;
    m68k.a[7] = 0x3800;
    m68k.setSR(0x0000); // user mode

    _ = try m68k.step();

    try std.testing.expectEqual(@as(u32, 0x5B00), m68k.pc);
    try std.testing.expectEqual(@as(u16, 4 * 4), try m68k.memory.read16(0x37FE));
    try std.testing.expectEqual(@as(u32, 0x1600), try m68k.memory.read32(0x37FA));
}

test "M68k Line-A opcode enters line-1010 emulator exception" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    try m68k.memory.write32(m68k.getExceptionVector(10), 0x5B80); // line-1010 vector
    try m68k.memory.write16(0x1680, 0xA000); // representative line-A opcode

    m68k.pc = 0x1680;
    m68k.a[7] = 0x3880;
    m68k.setSR(0x0000); // user mode

    _ = try m68k.step();

    try std.testing.expectEqual(@as(u32, 0x5B80), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x3878), m68k.a[7]);
    try std.testing.expectEqual(@as(u16, 10 * 4), try m68k.memory.read16(0x387E));
    try std.testing.expectEqual(@as(u32, 0x1680), try m68k.memory.read32(0x387A));
}

test "M68k BKPT traps through illegal instruction vector when no debugger is attached" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    try m68k.memory.write32(m68k.getExceptionVector(4), 0x5BC0);
    try m68k.memory.write16(0x16C0, 0x484D); // BKPT #5

    m68k.pc = 0x16C0;
    m68k.a[7] = 0x38C0;
    m68k.setSR(0x2000); // supervisor mode

    _ = try m68k.step();

    try std.testing.expectEqual(@as(u32, 0x5BC0), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x38B8), m68k.a[7]);
    try std.testing.expectEqual(@as(u16, 0x2000), try m68k.memory.read16(0x38B8)); // stacked SR
    try std.testing.expectEqual(@as(u32, 0x16C2), try m68k.memory.read32(0x38BA)); // next PC
    try std.testing.expectEqual(@as(u16, 4 * 4), try m68k.memory.read16(0x38BE)); // vector word
}

test "M68k ILLEGAL opcode 0x4AFC enters illegal instruction exception" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    try m68k.memory.write32(m68k.getExceptionVector(4), 0x5C00); // illegal vector
    try m68k.memory.write16(0x1700, 0x4AFC); // ILLEGAL opcode

    m68k.pc = 0x1700;
    m68k.a[7] = 0x3900;
    m68k.setSR(0x0000); // user mode

    _ = try m68k.step();

    try std.testing.expectEqual(@as(u32, 0x5C00), m68k.pc);
    try std.testing.expectEqual(@as(u16, 4 * 4), try m68k.memory.read16(0x38FE));
    try std.testing.expectEqual(@as(u32, 0x1700), try m68k.memory.read32(0x38FA));
}

test "M68k unmatched group-4 opcode does not silently execute as NOP" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    try m68k.memory.write32(m68k.getExceptionVector(4), 0x5D00); // illegal vector
    try m68k.memory.write16(0x1710, 0x4E7C); // unmatched group-4 pattern

    m68k.pc = 0x1710;
    m68k.a[7] = 0x3A00;
    m68k.setSR(0x0000); // user mode

    _ = try m68k.step();

    try std.testing.expectEqual(@as(u32, 0x5D00), m68k.pc);
    try std.testing.expectEqual(@as(u16, 4 * 4), try m68k.memory.read16(0x39FE));
    try std.testing.expectEqual(@as(u32, 0x1710), try m68k.memory.read32(0x39FA));
}

test "M68k ComplexEA execute path - read and write" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    // EA = A0 + 8 + D1.L*4 = 0x1000 + 8 + 12 = 0x1014
    m68k.a[0] = 0x1000;
    m68k.d[1] = 3;
    try m68k.memory.write32(0x1014, 0xDEADBEEF);

    var read_inst = decoder.Instruction.init();
    read_inst.mnemonic = .MOVE;
    read_inst.size = 2;
    read_inst.data_size = .Long;
    read_inst.src = .{ .ComplexEA = .{
        .base_reg = 0,
        .is_pc_relative = false,
        .index_reg = decoder.IndexReg{ .reg = 1, .is_addr = false, .is_long = true, .scale = 4 },
        .base_disp = 8,
        .outer_disp = 0,
        .is_mem_indirect = false,
        .is_post_indexed = false,
    } };
    read_inst.dst = .{ .DataReg = 0 };

    m68k.pc = 0x200;
    _ = try m68k.executor.execute(&m68k, &read_inst);
    try std.testing.expectEqual(@as(u32, 0xDEADBEEF), m68k.d[0]);

    m68k.d[2] = 0xAABBCCDD;
    var write_inst = decoder.Instruction.init();
    write_inst.mnemonic = .MOVE;
    write_inst.size = 2;
    write_inst.data_size = .Long;
    write_inst.src = .{ .DataReg = 2 };
    write_inst.dst = read_inst.src;

    _ = try m68k.executor.execute(&m68k, &write_inst);
    try std.testing.expectEqual(@as(u32, 0xAABBCCDD), try m68k.memory.read32(0x1014));
}

test "M68k PACK/UNPK register and memory forms" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    // PACK D1,D0,#0 : 0x0405 -> 0x45
    var pack_reg = decoder.Instruction.init();
    pack_reg.mnemonic = .PACK;
    pack_reg.size = 4;
    pack_reg.src = .{ .DataReg = 1 };
    pack_reg.dst = .{ .DataReg = 0 };
    pack_reg.extension_word = 0x0000;
    m68k.d[1] = 0x00000405;
    m68k.pc = 0x100;
    _ = try m68k.executor.execute(&m68k, &pack_reg);
    try std.testing.expectEqual(@as(u8, 0x45), @as(u8, @truncate(m68k.d[0])));

    // UNPK D1,D0,#0 : 0x45 -> 0x0405
    var unpk_reg = decoder.Instruction.init();
    unpk_reg.mnemonic = .UNPK;
    unpk_reg.size = 4;
    unpk_reg.src = .{ .DataReg = 1 };
    unpk_reg.dst = .{ .DataReg = 0 };
    unpk_reg.extension_word = 0x0000;
    m68k.d[1] = 0x00000045;
    m68k.pc = 0x104;
    _ = try m68k.executor.execute(&m68k, &unpk_reg);
    try std.testing.expectEqual(@as(u16, 0x0405), @as(u16, @truncate(m68k.d[0])));

    // PACK -(A1),-(A0),#0 : [A1-2]=0x0405 -> [A0-1]=0x45
    var pack_mem = decoder.Instruction.init();
    pack_mem.mnemonic = .PACK;
    pack_mem.size = 4;
    pack_mem.src = .{ .AddrPreDec = 1 };
    pack_mem.dst = .{ .AddrPreDec = 0 };
    pack_mem.extension_word = 0x0000;
    m68k.a[1] = 0x2002;
    m68k.a[0] = 0x3001;
    try m68k.memory.write16(0x2000, 0x0405);
    m68k.pc = 0x108;
    _ = try m68k.executor.execute(&m68k, &pack_mem);
    try std.testing.expectEqual(@as(u32, 0x2000), m68k.a[1]);
    try std.testing.expectEqual(@as(u32, 0x3000), m68k.a[0]);
    try std.testing.expectEqual(@as(u8, 0x45), try m68k.memory.read8(0x3000));

    // UNPK -(A1),-(A0),#0 : [A1-1]=0x45 -> [A0-2]=0x0405
    var unpk_mem = decoder.Instruction.init();
    unpk_mem.mnemonic = .UNPK;
    unpk_mem.size = 4;
    unpk_mem.src = .{ .AddrPreDec = 1 };
    unpk_mem.dst = .{ .AddrPreDec = 0 };
    unpk_mem.extension_word = 0x0000;
    m68k.a[1] = 0x4001;
    m68k.a[0] = 0x5002;
    try m68k.memory.write8(0x4000, 0x45);
    m68k.pc = 0x10C;
    _ = try m68k.executor.execute(&m68k, &unpk_mem);
    try std.testing.expectEqual(@as(u32, 0x4000), m68k.a[1]);
    try std.testing.expectEqual(@as(u32, 0x5000), m68k.a[0]);
    try std.testing.expectEqual(@as(u16, 0x0405), try m68k.memory.read16(0x5000));
}

test "M68k CHK2/CMP2 execution semantics" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    try m68k.memory.write16(0x6000, 10); // lower bound
    try m68k.memory.write16(0x6002, 20); // upper bound

    // CMP2.W (0x6000),D0 with D0=15 => in range
    var cmp2 = decoder.Instruction.init();
    cmp2.mnemonic = .CMP2;
    cmp2.size = 4;
    cmp2.data_size = .Word;
    cmp2.src = .{ .Address = 0x6000 };
    cmp2.extension_word = 0x0000; // D0
    m68k.d[0] = 15;
    m68k.pc = 0x200;
    _ = try m68k.executor.execute(&m68k, &cmp2);
    try std.testing.expect((m68k.sr & M68k.FLAG_Z) != 0);

    // CHK2.W (0x6000),D0 with D0=25 => out of range, exception #6
    try m68k.memory.write32(m68k.getExceptionVector(6), 0x7000);
    m68k.a[7] = 0x3000;
    m68k.setSR(0x2000);
    m68k.d[0] = 25;

    var chk2 = decoder.Instruction.init();
    chk2.mnemonic = .CHK2;
    chk2.size = 4;
    chk2.data_size = .Word;
    chk2.src = .{ .Address = 0x6000 };
    chk2.extension_word = 0x0000; // D0
    m68k.pc = 0x220;
    _ = try m68k.executor.execute(&m68k, &chk2);

    try std.testing.expectEqual(@as(u32, 0x7000), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x2FF8), m68k.a[7]);
}

test "M68k exception from master stack uses ISP and RTE restores MSP" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    m68k.setStackPointer(.User, 0x1000);
    m68k.setStackPointer(.Interrupt, 0x2000);
    m68k.setStackPointer(.Master, 0x3000);
    m68k.setSR(M68k.FLAG_S | M68k.FLAG_M); // Master mode active

    // TRAP #0 handler at 0x4000, containing RTE.
    try m68k.memory.write32(m68k.getExceptionVector(32), 0x4000);
    try m68k.memory.write16(0x0100, 0x4E40); // TRAP #0
    try m68k.memory.write16(0x4000, 0x4E73); // RTE

    m68k.pc = 0x0100;
    _ = try m68k.step(); // Enter exception

    // Entry must switch to interrupt stack (ISP), not keep using MSP.
    try std.testing.expectEqual(@as(u32, 0x1FF8), m68k.a[7]);
    try std.testing.expectEqual(@as(u32, 0x3000), m68k.getStackPointer(.Master));
    try std.testing.expect((m68k.sr & M68k.FLAG_S) != 0);
    try std.testing.expect((m68k.sr & M68k.FLAG_M) == 0);
    try std.testing.expectEqual(@as(u16, M68k.FLAG_S | M68k.FLAG_M), try m68k.memory.read16(0x1FF8));

    _ = try m68k.step(); // RTE

    try std.testing.expectEqual(@as(u32, 0x0102), m68k.pc);
    try std.testing.expect((m68k.sr & M68k.FLAG_S) != 0);
    try std.testing.expect((m68k.sr & M68k.FLAG_M) != 0);
    try std.testing.expectEqual(@as(u32, 0x3000), m68k.a[7]); // Back to master stack
    try std.testing.expectEqual(@as(u32, 0x2000), m68k.getStackPointer(.Interrupt)); // ISP frame consumed
}

test "M68k arithmetic overflow flag updates and VS branch behavior" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    var addi = decoder.Instruction.init();
    addi.mnemonic = .ADDI;
    addi.size = 4;
    addi.data_size = .Byte;
    addi.src = .{ .Immediate8 = 1 };
    addi.dst = .{ .DataReg = 0 };

    // 0x7F + 1 => 0x80 (signed overflow, no carry)
    m68k.d[0] = 0x7F;
    m68k.pc = 0x100;
    _ = try m68k.executor.execute(&m68k, &addi);
    try std.testing.expectEqual(@as(u8, 0x80), @as(u8, @truncate(m68k.d[0])));
    try std.testing.expect((m68k.sr & M68k.FLAG_V) != 0);
    try std.testing.expect((m68k.sr & M68k.FLAG_C) == 0);

    // BVS should branch when V=1.
    var bvs = decoder.Instruction.init();
    bvs.mnemonic = .Bcc;
    bvs.opcode = 0x6900; // condition 9 (VS)
    bvs.size = 2;
    bvs.src = .{ .Immediate8 = 2 };
    m68k.pc = 0x200;
    _ = try m68k.executor.execute(&m68k, &bvs);
    try std.testing.expectEqual(@as(u32, 0x204), m68k.pc);

    // 0xFF + 1 => 0x00 (carry, no signed overflow)
    m68k.d[0] = 0xFF;
    m68k.pc = 0x300;
    _ = try m68k.executor.execute(&m68k, &addi);
    try std.testing.expectEqual(@as(u8, 0x00), @as(u8, @truncate(m68k.d[0])));
    try std.testing.expect((m68k.sr & M68k.FLAG_C) != 0);
    try std.testing.expect((m68k.sr & M68k.FLAG_V) == 0);

    var subi = decoder.Instruction.init();
    subi.mnemonic = .SUBI;
    subi.size = 4;
    subi.data_size = .Byte;
    subi.src = .{ .Immediate8 = 1 };
    subi.dst = .{ .DataReg = 0 };

    // 0x80 - 1 => 0x7F (signed overflow, no borrow)
    m68k.d[0] = 0x80;
    m68k.pc = 0x400;
    _ = try m68k.executor.execute(&m68k, &subi);
    try std.testing.expectEqual(@as(u8, 0x7F), @as(u8, @truncate(m68k.d[0])));
    try std.testing.expect((m68k.sr & M68k.FLAG_V) != 0);
    try std.testing.expect((m68k.sr & M68k.FLAG_C) == 0);
}

test "M68k shift and rotate preserve carry/extend semantics" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    var lsl = decoder.Instruction.init();
    lsl.mnemonic = .LSL;
    lsl.size = 2;
    lsl.data_size = .Byte;
    lsl.src = .{ .Immediate8 = 1 };
    lsl.dst = .{ .DataReg = 0 };

    // LSL.B #1,D0: 0x80 -> 0x00, carry/extend must become 1.
    m68k.d[0] = 0x80;
    m68k.pc = 0x500;
    _ = try m68k.executor.execute(&m68k, &lsl);
    try std.testing.expectEqual(@as(u8, 0x00), @as(u8, @truncate(m68k.d[0])));
    try std.testing.expect((m68k.sr & M68k.FLAG_C) != 0);
    try std.testing.expect((m68k.sr & M68k.FLAG_X) != 0);

    var roxl = decoder.Instruction.init();
    roxl.mnemonic = .ROXL;
    roxl.size = 2;
    roxl.data_size = .Byte;
    roxl.src = .{ .Immediate8 = 1 };
    roxl.dst = .{ .DataReg = 0 };

    // ROXL.B #1,D0 with X=1: 0x80 -> 0x01, carry/extend from old msb.
    m68k.setFlag(M68k.FLAG_X, true);
    m68k.d[0] = 0x80;
    m68k.pc = 0x510;
    _ = try m68k.executor.execute(&m68k, &roxl);
    try std.testing.expectEqual(@as(u8, 0x01), @as(u8, @truncate(m68k.d[0])));
    try std.testing.expect((m68k.sr & M68k.FLAG_C) != 0);
    try std.testing.expect((m68k.sr & M68k.FLAG_X) != 0);

    var roxr = decoder.Instruction.init();
    roxr.mnemonic = .ROXR;
    roxr.size = 2;
    roxr.data_size = .Byte;
    roxr.src = .{ .Immediate8 = 1 };
    roxr.dst = .{ .DataReg = 0 };

    // ROXR.B #1,D0 with X=1: 0x01 -> 0x80, carry/extend from old lsb.
    m68k.setFlag(M68k.FLAG_X, true);
    m68k.d[0] = 0x01;
    m68k.pc = 0x520;
    _ = try m68k.executor.execute(&m68k, &roxr);
    try std.testing.expectEqual(@as(u8, 0x80), @as(u8, @truncate(m68k.d[0])));
    try std.testing.expect((m68k.sr & M68k.FLAG_C) != 0);
    try std.testing.expect((m68k.sr & M68k.FLAG_X) != 0);
}

test "M68k MOVEA decode and execution does not alter condition codes" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    var movea = decoder.Instruction.init();
    movea.mnemonic = .MOVEA;
    movea.size = 4;
    movea.data_size = .Word;
    movea.src = .{ .Immediate16 = 0x8000 };
    movea.dst = .{ .AddrReg = 0 };

    m68k.pc = 0x600;
    m68k.setSR(0x001F); // X,N,Z,V,C all set

    _ = try m68k.executor.execute(&m68k, &movea);

    try std.testing.expectEqual(@as(u32, 0xFFFF8000), m68k.a[0]);
    try std.testing.expectEqual(@as(u32, 0x604), m68k.pc);
    try std.testing.expectEqual(@as(u16, 0x001F), m68k.sr & 0x001F);
}

test "M68k TRAPV traps only when V flag is set" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    try m68k.memory.write16(0x700, 0x4E76); // TRAPV
    try m68k.memory.write32(m68k.getExceptionVector(7), 0x7200);

    // V=0: no trap
    m68k.pc = 0x700;
    m68k.a[7] = 0x4000;
    m68k.setSR(0x2000);
    m68k.setFlag(M68k.FLAG_V, false);
    _ = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0x702), m68k.pc);

    // V=1: trap to vector 7
    m68k.pc = 0x700;
    m68k.a[7] = 0x4100;
    m68k.setSR(0x2000);
    m68k.setFlag(M68k.FLAG_V, true);
    _ = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0x7200), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x40F8), m68k.a[7]);
    try std.testing.expectEqual(@as(u32, 0x702), try m68k.memory.read32(0x40FA)); // return PC
    try std.testing.expectEqual(@as(u16, 7 * 4), try m68k.memory.read16(0x40FE));
}

test "M68k STOP halts until interrupt and resumes on IRQ" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    try m68k.memory.write16(0x800, 0x4E72); // STOP
    try m68k.memory.write16(0x802, 0x2000); // keep supervisor mode
    try m68k.memory.write16(0x804, 0x4E71); // NOP (must not execute while stopped)
    try m68k.memory.write32(m68k.getExceptionVector(26), 0x9000); // level-2 autovector handler

    m68k.pc = 0x800;
    m68k.a[7] = 0x4200;
    m68k.setSR(0x2000);

    _ = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0x804), m68k.pc);
    try std.testing.expect(m68k.stopped);

    _ = try m68k.step(); // still stopped, no IRQ
    try std.testing.expectEqual(@as(u32, 0x804), m68k.pc);
    try std.testing.expect(m68k.stopped);

    m68k.setInterruptLevel(2);
    _ = try m68k.step(); // IRQ must wake STOP
    try std.testing.expectEqual(@as(u32, 0x9000), m68k.pc);
    try std.testing.expect(!m68k.stopped);
}

test "M68k STOP and RESET privilege violation in user mode" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    try m68k.memory.write32(m68k.getExceptionVector(8), 0xA000); // privilege violation

    // STOP in user mode => privilege violation
    try m68k.memory.write16(0xA100, 0x4E72);
    try m68k.memory.write16(0xA102, 0x2000);
    m68k.pc = 0xA100;
    m68k.a[7] = 0x4300;
    m68k.setSR(0x0000);
    _ = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0xA000), m68k.pc);
    try std.testing.expectEqual(@as(u16, 8 * 4), try m68k.memory.read16(0x42FE));
    try std.testing.expectEqual(@as(u32, 0xA100), try m68k.memory.read32(0x42FA));

    // RESET in user mode => privilege violation
    try m68k.memory.write16(0xA200, 0x4E70);
    m68k.pc = 0xA200;
    m68k.a[7] = 0x4400;
    m68k.setSR(0x0000);
    _ = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0xA000), m68k.pc);
    try std.testing.expectEqual(@as(u16, 8 * 4), try m68k.memory.read16(0x43FE));
    try std.testing.expectEqual(@as(u32, 0xA200), try m68k.memory.read32(0x43FA));
}

test "M68k RESET in supervisor mode advances PC" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    try m68k.memory.write16(0xB000, 0x4E70); // RESET
    m68k.pc = 0xB000;
    m68k.setSR(0x2000);
    _ = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0xB002), m68k.pc);
}

test "M68k TRAPcc decode forms and return PC sizing" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    try m68k.memory.write32(m68k.getExceptionVector(7), 0xC000);

    // TRAPcc with false condition must not trap and should consume size.
    // 0x51FC = TRAPF (no extension)
    try m68k.memory.write16(0xC100, 0x51FC);
    m68k.pc = 0xC100;
    m68k.a[7] = 0x4500;
    m68k.setSR(0x2000);
    _ = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0xC102), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x4500), m68k.a[7]);

    // 0x50FC = TRAPT (no extension), return PC must be +2.
    try m68k.memory.write16(0xC200, 0x50FC);
    m68k.pc = 0xC200;
    m68k.a[7] = 0x4600;
    m68k.setSR(0x2000);
    _ = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0xC000), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x45F8), m68k.a[7]);
    try std.testing.expectEqual(@as(u32, 0xC202), try m68k.memory.read32(0x45FA));

    // 0x50FA = TRAPT.W #imm16, return PC must be +4.
    try m68k.memory.write16(0xC300, 0x50FA);
    try m68k.memory.write16(0xC302, 0x1234);
    m68k.pc = 0xC300;
    m68k.a[7] = 0x4700;
    m68k.setSR(0x2000);
    _ = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0xC000), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x46F8), m68k.a[7]);
    try std.testing.expectEqual(@as(u32, 0xC304), try m68k.memory.read32(0x46FA));

    // 0x50FB = TRAPT.L #imm32, return PC must be +6.
    try m68k.memory.write16(0xC400, 0x50FB);
    try m68k.memory.write32(0xC402, 0x89ABCDEF);
    m68k.pc = 0xC400;
    m68k.a[7] = 0x4800;
    m68k.setSR(0x2000);
    _ = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0xC000), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x47F8), m68k.a[7]);
    try std.testing.expectEqual(@as(u32, 0xC406), try m68k.memory.read32(0x47FA));
}

test "M68k decode IllegalInstruction error is routed to vector 4 exception" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    // ORI.B with invalid EA mode 7, reg 5 (illegal effective address).
    try m68k.memory.write16(0xD000, 0x003D);
    try m68k.memory.write32(m68k.getExceptionVector(4), 0xD100);

    m68k.pc = 0xD000;
    m68k.a[7] = 0x4900;
    m68k.setSR(0x0000);
    _ = try m68k.step();

    try std.testing.expectEqual(@as(u32, 0xD100), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x48F8), m68k.a[7]);
    try std.testing.expectEqual(@as(u16, 4 * 4), try m68k.memory.read16(0x48FE));
    try std.testing.expectEqual(@as(u32, 0xD000), try m68k.memory.read32(0x48FA));
}

test "M68k illegal CALLM encodings are routed to vector 4 exception" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    try m68k.memory.write32(m68k.getExceptionVector(4), 0xD300);

    // mode=3 is illegal for CALLM (opcode base 0x06C0).
    try m68k.memory.write16(0xD200, 0x06D8);
    m68k.pc = 0xD200;
    m68k.a[7] = 0x4A80;
    m68k.setSR(0x2000);
    _ = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0xD300), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x4A78), m68k.a[7]);
    try std.testing.expectEqual(@as(u32, 0xD200), try m68k.memory.read32(0x4A7A));
    try std.testing.expectEqual(@as(u16, 4 * 4), try m68k.memory.read16(0x4A7E));

    // mode=7, reg>3 is illegal for CALLM.
    try m68k.memory.write16(0xD210, 0x06FC);
    m68k.pc = 0xD210;
    m68k.a[7] = 0x4B00;
    m68k.setSR(0x2000);
    _ = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0xD300), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x4AF8), m68k.a[7]);
    try std.testing.expectEqual(@as(u32, 0xD210), try m68k.memory.read32(0x4AFA));
    try std.testing.expectEqual(@as(u16, 4 * 4), try m68k.memory.read16(0x4AFE));
}

test "M68k ORI/ANDI/EORI to CCR and SR semantics" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    // ORI to CCR
    try m68k.memory.write16(0xE000, 0x003C);
    try m68k.memory.write16(0xE002, 0x0011); // set X and C
    m68k.pc = 0xE000;
    m68k.sr = 0x2000;
    _ = try m68k.step();
    try std.testing.expectEqual(@as(u16, 0x11), m68k.sr & 0x1F);

    // ANDI to CCR
    try m68k.memory.write16(0xE010, 0x023C);
    try m68k.memory.write16(0xE012, 0x0001); // keep only C
    m68k.pc = 0xE010;
    _ = try m68k.step();
    try std.testing.expectEqual(@as(u16, 0x01), m68k.sr & 0x1F);

    // EORI to CCR
    try m68k.memory.write16(0xE020, 0x0A3C);
    try m68k.memory.write16(0xE022, 0x0003); // toggle C,V
    m68k.pc = 0xE020;
    _ = try m68k.step();
    try std.testing.expectEqual(@as(u16, 0x02), m68k.sr & 0x1F);

    // ORI to SR in supervisor mode
    try m68k.memory.write16(0xE030, 0x007C);
    try m68k.memory.write16(0xE032, 0x0700); // set IPL=7
    m68k.pc = 0xE030;
    m68k.sr = 0x2002;
    _ = try m68k.step();
    try std.testing.expectEqual(@as(u16, 0x2702), m68k.sr);

    // ANDI to SR in user mode => privilege violation
    try m68k.memory.write16(0xE040, 0x027C);
    try m68k.memory.write16(0xE042, 0xF8FF);
    try m68k.memory.write32(m68k.getExceptionVector(8), 0xE100);
    m68k.pc = 0xE040;
    m68k.a[7] = 0x4A00;
    m68k.sr = 0x0000;
    _ = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0xE100), m68k.pc);

    // EORI to SR in supervisor mode
    try m68k.memory.write16(0xE050, 0x0A7C);
    try m68k.memory.write16(0xE052, 0x0007);
    m68k.pc = 0xE050;
    m68k.sr = 0x2000;
    _ = try m68k.step();
    try std.testing.expectEqual(@as(u16, 0x2007), m68k.sr);
}

test "M68k CALLM and RTM execute module frame round-trip" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    // CALLM #4,($0000E500).l : 0x06F9 0x0004 0x0000 0xE500
    try m68k.memory.write16(0xE300, 0x06F9);
    try m68k.memory.write16(0xE302, 0x0004);
    try m68k.memory.write16(0xE304, 0x0000);
    try m68k.memory.write16(0xE306, 0xE500);

    // Module descriptor:
    // +4 entry pointer, +8 module data pointer.
    try m68k.memory.write32(0xE504, 0xE540);
    try m68k.memory.write32(0xE508, 0x12345678);

    // Entry word selects D3 as module data register, then RTM D3.
    try m68k.memory.write16(0xE540, 0x3000);
    try m68k.memory.write16(0xE542, 0x06C3);

    m68k.pc = 0xE300;
    m68k.a[7] = 0x5000;
    m68k.setSR(0x2015);
    m68k.d[3] = 0xAABBCCDD;
    _ = try m68k.step();

    try std.testing.expectEqual(@as(u32, 0xE542), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x4FF4), m68k.a[7]);
    try std.testing.expectEqual(@as(u32, 0x12345678), m68k.d[3]);
    try std.testing.expectEqual(@as(u16, 0x0015), try m68k.memory.read16(0x4FF4));
    try std.testing.expectEqual(@as(u32, 0xE308), try m68k.memory.read32(0x4FF6));
    try std.testing.expectEqual(@as(u32, 0xAABBCCDD), try m68k.memory.read32(0x4FFA));
    try std.testing.expectEqual(@as(u16, 0x0004), try m68k.memory.read16(0x4FFE));

    m68k.setSR((m68k.sr & 0xFF00) | 0x00);
    m68k.d[3] = 0;
    _ = try m68k.step();

    try std.testing.expectEqual(@as(u32, 0xE308), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x5004), m68k.a[7]);
    try std.testing.expectEqual(@as(u32, 0xAABBCCDD), m68k.d[3]);
    try std.testing.expectEqual(@as(u16, 0x0015), m68k.sr & 0x00FF);
}

test "M68k TAS works for data register and memory operands" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    // TAS D0
    try m68k.memory.write16(0xE560, 0x4AC0);
    m68k.pc = 0xE560;
    m68k.d[0] = 0x00000001;
    _ = try m68k.step();
    try std.testing.expectEqual(@as(u8, 0x81), @as(u8, @truncate(m68k.d[0])));
    try std.testing.expect((m68k.sr & M68k.FLAG_Z) == 0);
    try std.testing.expect((m68k.sr & M68k.FLAG_N) == 0);

    // TAS (A0)
    try m68k.memory.write16(0xE570, 0x4AD0);
    try m68k.memory.write8(0x2200, 0x00);
    m68k.pc = 0xE570;
    m68k.a[0] = 0x2200;
    _ = try m68k.step();
    try std.testing.expectEqual(@as(u8, 0x80), try m68k.memory.read8(0x2200));
    try std.testing.expect((m68k.sr & M68k.FLAG_Z) != 0);
}

test "M68k MOVEM updates addressing mode semantics correctly" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    // MOVEM.L D0-D1,-(A0): predecrement form uses reverse register traversal.
    try m68k.memory.write16(0xE580, 0x48E0);
    try m68k.memory.write16(0xE582, 0x0003);
    m68k.pc = 0xE580;
    m68k.a[0] = 0x3008;
    m68k.d[0] = 0x11111111;
    m68k.d[1] = 0x22222222;
    _ = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0x3000), m68k.a[0]);
    try std.testing.expectEqual(@as(u32, 0x11111111), try m68k.memory.read32(0x3000));
    try std.testing.expectEqual(@as(u32, 0x22222222), try m68k.memory.read32(0x3004));

    // MOVEM.W (A1)+,D2-D3: word loads are sign-extended and A1 must post-increment.
    try m68k.memory.write16(0xE590, 0x4C99);
    try m68k.memory.write16(0xE592, 0x000C);
    try m68k.memory.write16(0x3100, 0xFFFE);
    try m68k.memory.write16(0x3102, 0x0001);
    m68k.pc = 0xE590;
    m68k.a[1] = 0x3100;
    m68k.d[2] = 0;
    m68k.d[3] = 0;
    _ = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0x3104), m68k.a[1]);
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFE), m68k.d[2]);
    try std.testing.expectEqual(@as(u32, 0x00000001), m68k.d[3]);

    // MOVEM.L D0,(d16,A2): instruction length must include displacement extension.
    try m68k.memory.write16(0xE5A0, 0x48EA);
    try m68k.memory.write16(0xE5A2, 0x0001);
    try m68k.memory.write16(0xE5A4, 0x0010);
    m68k.pc = 0xE5A0;
    m68k.a[2] = 0x3200;
    m68k.d[0] = 0xDEADBEEF;
    _ = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0xE5A6), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0xDEADBEEF), try m68k.memory.read32(0x3210));
}

test "M68k extended-EA instructions advance PC by decoded size" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    // TST.B (16,A0)
    try m68k.memory.write16(0xE800, 0x4A28);
    try m68k.memory.write16(0xE802, 0x0010);
    m68k.a[0] = 0x2400;
    try m68k.memory.write8(0x2410, 0x12);
    m68k.pc = 0xE800;
    _ = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0xE804), m68k.pc);

    // PEA (16,A1)
    try m68k.memory.write16(0xE810, 0x4869);
    try m68k.memory.write16(0xE812, 0x0010);
    m68k.a[1] = 0x2500;
    m68k.a[7] = 0x6000;
    m68k.pc = 0xE810;
    _ = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0xE814), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x5FFC), m68k.a[7]);
    try std.testing.expectEqual(@as(u32, 0x2510), try m68k.memory.read32(0x5FFC));

    // ST (16,A2) : Scc with true condition to memory.
    try m68k.memory.write16(0xE820, 0x50EA);
    try m68k.memory.write16(0xE822, 0x0010);
    m68k.a[2] = 0x2600;
    m68k.pc = 0xE820;
    _ = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0xE824), m68k.pc);
    try std.testing.expectEqual(@as(u8, 0xFF), try m68k.memory.read8(0x2610));

    // MULU.W (16,A3),D0
    try m68k.memory.write16(0xE830, 0xC0EB);
    try m68k.memory.write16(0xE832, 0x0010);
    m68k.a[3] = 0x2700;
    try m68k.memory.write16(0x2710, 3);
    m68k.d[0] = 2;
    m68k.pc = 0xE830;
    _ = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0xE834), m68k.pc);
    try std.testing.expectEqual(@as(u32, 6), m68k.d[0]);
}

test "M68k memory shift with extension EA advances PC by instruction size" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    // ASL.W (16,A0): opcode 0xE1E8 with d16 extension.
    try m68k.memory.write16(0xE900, 0xE1E8);
    try m68k.memory.write16(0xE902, 0x0010);
    m68k.a[0] = 0x2800;
    try m68k.memory.write16(0x2810, 0x0001);
    m68k.pc = 0xE900;

    _ = try m68k.step();

    try std.testing.expectEqual(@as(u32, 0xE904), m68k.pc);
    try std.testing.expectEqual(@as(u16, 0x0002), try m68k.memory.read16(0x2810));
}

test "M68k MUL*_L and DIV*_L execution semantics" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    // MULU.L #5,D1:D2  (dl=D1, dh=D2)
    try m68k.memory.write16(0xE600, 0x4C3C);
    try m68k.memory.write16(0xE602, 0x2801);
    try m68k.memory.write32(0xE604, 0x00000005);
    m68k.pc = 0xE600;
    m68k.d[1] = 3;
    m68k.d[2] = 0xFFFFFFFF;
    _ = try m68k.step();
    try std.testing.expectEqual(@as(u32, 15), m68k.d[1]);
    try std.testing.expectEqual(@as(u32, 0), m68k.d[2]);
    try std.testing.expect(!m68k.getFlag(M68k.FLAG_V));
    try std.testing.expect(!m68k.getFlag(M68k.FLAG_C));

    // MULS.L #4,D3:D4 with overflow in 32-bit signed result.
    try m68k.memory.write16(0xE610, 0x4C3C);
    try m68k.memory.write16(0xE612, 0x4C03);
    try m68k.memory.write32(0xE614, 0x00000004);
    m68k.pc = 0xE610;
    m68k.d[3] = 0x40000000;
    m68k.d[4] = 0;
    _ = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0), m68k.d[3]);
    try std.testing.expectEqual(@as(u32, 1), m68k.d[4]);
    try std.testing.expect(m68k.getFlag(M68k.FLAG_V));

    // DIVU.L #2,D1:D2 : dividend = D2:D1 = 0x00000001_00000000
    try m68k.memory.write16(0xE620, 0x4C3C);
    try m68k.memory.write16(0xE622, 0x2001);
    try m68k.memory.write32(0xE624, 0x00000002);
    m68k.pc = 0xE620;
    m68k.d[1] = 0x00000000;
    m68k.d[2] = 0x00000001;
    _ = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0x80000000), m68k.d[1]);
    try std.testing.expectEqual(@as(u32, 0), m68k.d[2]);
    try std.testing.expect(!m68k.getFlag(M68k.FLAG_V));

    // DIVS.L divide by zero -> vector 5.
    try m68k.memory.write32(m68k.getExceptionVector(5), 0xE700);
    try m68k.memory.write16(0xE630, 0x4C3C);
    try m68k.memory.write16(0xE632, 0x2405);
    try m68k.memory.write32(0xE634, 0x00000000);
    m68k.pc = 0xE630;
    m68k.a[7] = 0x5200;
    m68k.setSR(0x2000);
    m68k.d[5] = 123;
    m68k.d[2] = 456;
    _ = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0xE700), m68k.pc);
}
