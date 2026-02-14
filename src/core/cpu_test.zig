const std = @import("std");
const cpu = @import("cpu.zig");
const memory = @import("memory.zig");
const decoder = @import("decoder.zig");
const M68k = cpu.M68k;

const CoprocTestContext = struct {
    called: bool = false,
    emulate_unavailable: bool = false,
    emulate_fault: bool = false,
    fault_addr: u32 = 0,
};

const BusHookMode = enum {
    pass_through,
    retry_once_program_fetch,
    halt_program_fetch,
    bus_error_on_data_write,
    capture_program_fetch,
};

const BusHookTestContext = struct {
    mode: BusHookMode = .pass_through,
    retried_once: bool = false,
    saw_data_write: bool = false,
    saw_program_fetch: bool = false,
    last_addr: u32 = 0,
    last_access: memory.BusAccess = .{},
    error_target_addr: ?u32 = null, // Only trigger bus_error for this specific address
};

const BkptTestContext = struct {
    called: bool = false,
    last_vector: u3 = 0,
};

fn coprocTestHandler(ctx: ?*anyopaque, m68k: *M68k, opcode: u16, _: u32) M68k.CoprocessorResult {
    if (ctx == null) return .{ .unavailable = {} };
    const typed: *CoprocTestContext = @ptrCast(@alignCast(ctx.?));
    typed.called = true;
    if (typed.emulate_unavailable) return .{ .unavailable = {} };
    if (typed.emulate_fault) return .{ .fault = typed.fault_addr };

    // Minimal software-FPU demonstration: F-line opcode writes 1.0f to D0.
    if ((opcode & 0xF000) == 0xF000) {
        m68k.d[0] = 0x3F800000;
        return .{ .handled = 12 };
    }
    return .{ .unavailable = {} };
}

fn busHookTestHandler(ctx: ?*anyopaque, logical_addr: u32, access: memory.BusAccess) memory.BusSignal {
    if (ctx == null) return .ok;
    const typed: *BusHookTestContext = @ptrCast(@alignCast(ctx.?));

    if (access.space == .Data and access.is_write) {
        typed.saw_data_write = true;
        typed.last_addr = logical_addr;
        typed.last_access = access;
    }
    if (access.space == .Program and !access.is_write) {
        typed.saw_program_fetch = true;
        typed.last_addr = logical_addr;
        typed.last_access = access;
    }

    return switch (typed.mode) {
        .pass_through => .ok,
        .retry_once_program_fetch => blk: {
            if (access.space == .Program and !access.is_write and !typed.retried_once) {
                typed.retried_once = true;
                break :blk .retry;
            }
            break :blk .ok;
        },
        .halt_program_fetch => if (access.space == .Program and !access.is_write) .halt else .ok,
        .bus_error_on_data_write => if (access.space == .Data and access.is_write and
            (typed.error_target_addr == null or typed.error_target_addr.? == logical_addr)) .bus_error else .ok,
        .capture_program_fetch => .ok,
    };
}

fn dataAccessAddTranslator(_: ?*anyopaque, logical_addr: u32, access: memory.BusAccess) !u32 {
    if (access.space == .Data) return logical_addr + 0x1000;
    return logical_addr;
}

fn bkptTestHandler(ctx: ?*anyopaque, m68k: *M68k, vector: u3, _: u32) M68k.BkptResult {
    if (ctx == null) return .{ .illegal = {} };
    const typed: *BkptTestContext = @ptrCast(@alignCast(ctx.?));
    typed.called = true;
    typed.last_vector = vector;
    m68k.d[1] = 0xB16B00B5;
    return .{ .handled = 14 };
}

test "M68k initialization" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();
    try std.testing.expectEqual(@as(u32, 0), m68k.pc);
    try std.testing.expectEqual(@as(u16, 0x2700), m68k.sr);
}

test "M68k stack register fallback loads active A7 when target bank is zero" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    m68k.setSR(0x0000); // start in user mode
    m68k.setStackPointer(.User, 0x4100);
    m68k.setStackRegister(.Interrupt, 0);
    m68k.setStackRegister(.Master, 0);

    // User -> ISP should fallback to previous A7 because ISP is zero.
    m68k.setSR(M68k.FLAG_S);
    try std.testing.expectEqual(@as(u32, 0x4100), m68k.a[7]);
    try std.testing.expectEqual(@as(u32, 0x4100), m68k.getStackRegister(.Interrupt));

    // Change ISP active A7, then switch to MSP with zero MSP; fallback should use previous A7.
    m68k.a[7] = 0x40F0;
    m68k.setSR(M68k.FLAG_S | M68k.FLAG_M);
    try std.testing.expectEqual(@as(u32, 0x40F0), m68k.a[7]);
    try std.testing.expectEqual(@as(u32, 0x40F0), m68k.getStackRegister(.Master));
    try std.testing.expectEqual(@as(u32, 0x40F0), m68k.getStackRegister(.Interrupt));
}

test "M68k reset initializes ISP/MSP from reset vector stack pointer" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    try m68k.memory.write32(0x0000, 0xCAFEB000); // initial SP
    try m68k.memory.write32(0x0004, 0x00ABCDEF); // initial PC

    m68k.reset();

    try std.testing.expectEqual(@as(u32, 0xCAFEB000), m68k.a[7]);
    try std.testing.expectEqual(@as(u32, 0xCAFEB000), m68k.getStackRegister(.Interrupt));
    try std.testing.expectEqual(@as(u32, 0xCAFEB000), m68k.getStackRegister(.Master));
    try std.testing.expectEqual(@as(u32, 0), m68k.getStackRegister(.User));
    try std.testing.expectEqual(@as(u32, 0x00ABCDEF), m68k.pc);
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
    const cycles = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0x12345678), m68k.vbr);
    try std.testing.expectEqual(@as(u32, 12), cycles);
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

test "M68k instruction cache exposes hit and miss statistics" {
    const allocator = std.testing.allocator;
    var m68k = M68k.initWithConfig(allocator, .{ .size = 64 * 1024 * 1024 });
    defer m68k.deinit();

    try m68k.memory.write16(0x01000000, 0x4E71); // NOP

    // Cache disabled: stats remain unchanged.
    m68k.pc = 0x01000000;
    _ = try m68k.step();
    const s0 = m68k.getICacheStats();
    try std.testing.expectEqual(@as(u64, 0), s0.hits);
    try std.testing.expectEqual(@as(u64, 0), s0.misses);

    // Enable cache and force miss/hit/miss sequence.
    m68k.setCacr(0x1);
    m68k.pc = 0x01000000;
    _ = try m68k.step(); // miss
    m68k.pc = 0x01000000;
    _ = try m68k.step(); // hit
    m68k.setCacr(0x9); // invalidate request
    m68k.pc = 0x01000000;
    _ = try m68k.step(); // miss

    const s1 = m68k.getICacheStats();
    try std.testing.expectEqual(@as(u64, 1), s1.hits);
    try std.testing.expectEqual(@as(u64, 2), s1.misses);

    m68k.clearICacheStats();
    const s2 = m68k.getICacheStats();
    try std.testing.expectEqual(@as(u64, 0), s2.hits);
    try std.testing.expectEqual(@as(u64, 0), s2.misses);
}

test "M68k instruction cache miss penalty is configurable" {
    const allocator = std.testing.allocator;
    var m68k = M68k.initWithConfig(allocator, .{ .size = 64 * 1024 * 1024 });
    defer m68k.deinit();

    try m68k.memory.write16(0x01200000, 0x4E71); // NOP
    m68k.setCacr(0x1);
    m68k.setICacheFetchMissPenalty(5);
    try std.testing.expectEqual(@as(u32, 5), m68k.getICacheFetchMissPenalty());

    m68k.pc = 0x01200000;
    const c0 = try m68k.step();
    try std.testing.expectEqual(@as(u32, 9), c0); // base 4 + miss 5

    m68k.pc = 0x01200000;
    const c1 = try m68k.step();
    try std.testing.expectEqual(@as(u32, 4), c1); // hit
}

test "M68k pipeline mode flag supports off approx detailed states" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    try std.testing.expectEqual(M68k.PipelineMode.off, m68k.getPipelineMode());
    m68k.setPipelineMode(.approx);
    try std.testing.expectEqual(M68k.PipelineMode.approx, m68k.getPipelineMode());
    m68k.setPipelineMode(.detailed);
    try std.testing.expectEqual(M68k.PipelineMode.detailed, m68k.getPipelineMode());
}

test "M68k pipeline approx mode adds branch flush penalty on taken branch" {
    const allocator = std.testing.allocator;

    var m68k_off = M68k.init(allocator);
    defer m68k_off.deinit();
    try m68k_off.memory.write16(0x1000, 0x6002); // BRA +2
    try m68k_off.memory.write16(0x1002, 0x4E71); // skipped NOP
    m68k_off.pc = 0x1000;
    const off_cycles = try m68k_off.step();
    try std.testing.expectEqual(@as(u32, 10), off_cycles);

    var m68k_approx = M68k.init(allocator);
    defer m68k_approx.deinit();
    m68k_approx.setPipelineMode(.approx);
    try m68k_approx.memory.write16(0x1000, 0x6002); // BRA +2
    try m68k_approx.memory.write16(0x1002, 0x4E71);
    m68k_approx.pc = 0x1000;
    const approx_cycles = try m68k_approx.step();
    try std.testing.expectEqual(@as(u32, 12), approx_cycles);
}

test "M68k pipeline approx mode applies EA-write overlap discount on memory destination write" {
    const allocator = std.testing.allocator;

    var m68k_off = M68k.init(allocator);
    defer m68k_off.deinit();
    m68k_off.d[0] = 0x12345678;
    m68k_off.a[0] = 0x2000;
    try m68k_off.memory.write16(0x1100, 0x2080); // MOVE.L D0,(A0)
    m68k_off.pc = 0x1100;
    const off_cycles = try m68k_off.step();
    // MOVE.L D0,(A0): 4 (base) + 0 (src reg) + 4 (dst indirect) = 8
    try std.testing.expectEqual(@as(u32, 8), off_cycles);

    var m68k_approx = M68k.init(allocator);
    defer m68k_approx.deinit();
    m68k_approx.setPipelineMode(.approx);
    m68k_approx.d[0] = 0x12345678;
    m68k_approx.a[0] = 0x2000;
    try m68k_approx.memory.write16(0x1100, 0x2080); // MOVE.L D0,(A0)
    m68k_approx.pc = 0x1100;
    const approx_cycles = try m68k_approx.step();
    // approx mode: 8 (base) - 1 (overlap) = 7
    try std.testing.expectEqual(@as(u32, 7), approx_cycles);
}

test "M68k ADDQ long data-register fast path preserves flags and cycles" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    // ADDQ.L #8,D0 (imm field 0 means 8)
    try m68k.memory.write16(0x1200, 0x5080);
    m68k.d[0] = 0x7FFFFFFF;
    m68k.pc = 0x1200;

    const cycles = try m68k.step();
    try std.testing.expectEqual(@as(u32, 4), cycles);
    try std.testing.expectEqual(@as(u32, 0x80000007), m68k.d[0]);
    try std.testing.expect(m68k.getFlag(M68k.FLAG_V));
    try std.testing.expect(!m68k.getFlag(M68k.FLAG_Z));
    try std.testing.expect(m68k.getFlag(M68k.FLAG_N));
}

test "M68k SUBQ long data-register fast path preserves flags and cycles" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    // SUBQ.L #1,D1
    try m68k.memory.write16(0x1220, 0x5381);
    m68k.d[1] = 0x00000000;
    m68k.pc = 0x1220;

    const cycles = try m68k.step();
    try std.testing.expectEqual(@as(u32, 4), cycles);
    try std.testing.expectEqual(@as(u32, 0xFFFFFFFF), m68k.d[1]);
    try std.testing.expect(m68k.getFlag(M68k.FLAG_C));
    try std.testing.expect(m68k.getFlag(M68k.FLAG_X));
    try std.testing.expect(m68k.getFlag(M68k.FLAG_N));
}

test "M68k instruction cache fill is longword aligned" {
    const allocator = std.testing.allocator;
    var m68k = M68k.initWithConfig(allocator, .{ .size = 64 * 1024 * 1024 });
    defer m68k.deinit();

    try m68k.memory.write32(0x00300000, 0x4E714E71); // NOP, NOP
    m68k.setCacr(0x1); // enable I-cache

    // Miss at upper word of longword line.
    m68k.pc = 0x00300000;
    const c0 = try m68k.step();
    try std.testing.expectEqual(@as(u32, 6), c0);

    // Lower word of the same longword must hit without extra miss penalty.
    m68k.pc = 0x00300002;
    const c1 = try m68k.step();
    try std.testing.expectEqual(@as(u32, 4), c1);
}

test "M68k instruction cache capacity tracks 256B line window" {
    const allocator = std.testing.allocator;
    var m68k = M68k.initWithConfig(allocator, .{ .size = 64 * 1024 * 1024 });
    defer m68k.deinit();

    try m68k.memory.write16(0x00400000, 0x4E71); // NOP
    try m68k.memory.write16(0x00400080, 0x4E71); // NOP (128B apart)
    m68k.setCacr(0x1); // enable I-cache

    m68k.pc = 0x00400000;
    const c0 = try m68k.step();
    try std.testing.expectEqual(@as(u32, 6), c0); // miss

    m68k.pc = 0x00400080;
    const c1 = try m68k.step();
    try std.testing.expectEqual(@as(u32, 6), c1); // another miss on different line

    // 68020 256B I-cache window: address +0x80 maps to a different line, so base line stays resident.
    m68k.pc = 0x00400000;
    const c2 = try m68k.step();
    try std.testing.expectEqual(@as(u32, 4), c2); // hit
}

test "M68k split bus cycle penalty is opt-in and adds fetch overhead on narrow port" {
    const allocator = std.testing.allocator;
    const width8_region = [_]memory.PortRegion{
        .{ .start = 0x0000, .end_exclusive = 0x0100, .width = .Width8 },
    };

    // Disabled path: legacy cycle model unchanged.
    var m68k_no_penalty = M68k.initWithConfig(allocator, .{
        .size = 0x1000,
        .default_port_width = .Width32,
        .port_regions = &width8_region,
    });
    defer m68k_no_penalty.deinit();
    try m68k_no_penalty.memory.write16(0x0040, 0x4E71); // NOP
    m68k_no_penalty.pc = 0x0040;
    const c0 = try m68k_no_penalty.step();
    try std.testing.expectEqual(@as(u32, 4), c0);

    // Enabled path: 16-bit fetch over 8-bit port adds +1 split penalty.
    var m68k_penalty = M68k.initWithConfig(allocator, .{
        .size = 0x1000,
        .default_port_width = .Width32,
        .port_regions = &width8_region,
    });
    defer m68k_penalty.deinit();
    m68k_penalty.setSplitBusCyclePenaltyEnabled(true);
    try m68k_penalty.memory.write16(0x0040, 0x4E71); // NOP
    m68k_penalty.pc = 0x0040;
    const c1 = try m68k_penalty.step();
    try std.testing.expectEqual(@as(u32, 5), c1);
}

test "M68k split bus cycle penalty adds data-path overhead independent of semantics" {
    const allocator = std.testing.allocator;
    const width8_region = [_]memory.PortRegion{
        .{ .start = 0x0000, .end_exclusive = 0x1000, .width = .Width8 },
    };
    var m68k = M68k.initWithConfig(allocator, .{
        .size = 0x2000,
        .default_port_width = .Width32,
        .port_regions = &width8_region,
    });
    defer m68k.deinit();

    m68k.setSplitBusCyclePenaltyEnabled(true);
    m68k.d[0] = 0xAABBCCDD;
    m68k.a[0] = 0x0200;
    try m68k.memory.write16(0x0100, 0x2080); // MOVE.L D0,(A0)
    m68k.pc = 0x0100;

    // MOVE.L D0,(A0): base 8 cycles (4+0+4) + fetch split(1) + data write split(3) = 12
    const cycles = try m68k.step();
    try std.testing.expectEqual(@as(u32, 12), cycles);
    try std.testing.expectEqual(@as(u32, 0xAABBCCDD), try m68k.memory.read32(0x0200));
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
    const cycles = try m68k.step();
    try std.testing.expectEqual(@as(u16, 0x0015), m68k.sr);
    try std.testing.expectEqual(@as(u32, 0x4000), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x2008), m68k.a[7]);
    try std.testing.expectEqual(@as(u32, 20), cycles);
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
    const cycles = try m68k.step();
    const sp = 0x3000 - 8;
    try std.testing.expectEqual(@as(u16, 0x0000), try m68k.memory.read16(sp));
    try std.testing.expectEqual(@as(u32, 0x1002), try m68k.memory.read32(sp + 2));
    try std.testing.expectEqual(@as(u32, 0x5000), m68k.pc);
    try std.testing.expectEqual(@as(u32, 34), cycles);
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
    try std.testing.expectEqual(@as(u32, m68k.memory.size - 1), try m68k.memory.read32(0x63F0)); // fault address
    try std.testing.expectEqual(@as(u16, 0xD000), try m68k.memory.read16(0x63F4)); // FC=supervisor program read
}

test "M68k decode extension fetch bus error preserves faulting address in format A frame" {
    const allocator = std.testing.allocator;
    var m68k = M68k.initWithConfig(allocator, .{ .size = 0x1000 });
    defer m68k.deinit();

    try m68k.memory.write32(m68k.getExceptionVector(2), 0x0F00);
    try m68k.memory.write16(0x0FFE, 0x3028); // MOVE.W (d16,A0),D0 — decode reads extension word at 0x1000
    m68k.pc = 0x0FFE;
    m68k.a[7] = 0x0700;
    m68k.setSR(0x2000);

    const cycles = try m68k.step();

    try std.testing.expectEqual(@as(u32, 0x0F00), m68k.pc);
    try std.testing.expectEqual(@as(u32, 52), cycles);
    try std.testing.expectEqual(@as(u32, 0x06E8), m68k.a[7]); // format A frame size
    try std.testing.expectEqual(@as(u16, 0xA008), try m68k.memory.read16(0x06EE)); // vector 2
    try std.testing.expectEqual(@as(u32, 0x1000), try m68k.memory.read32(0x06F0)); // precise decode fault address
}

test "M68k ABCD - Add BCD" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();
    m68k.d[0] = 0x25;
    m68k.d[1] = 0x17;
    try m68k.memory.write16(0x1000, 0xC101);
    m68k.pc = 0x1000;
    const cycles = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0x42), m68k.d[0] & 0xFF);
    try std.testing.expectEqual(@as(u32, 6), cycles);
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
    const cycles = try m68k.step();
    try std.testing.expectEqual(@as(u8, 0x12), try m68k.memory.read8(0x2000));
    try std.testing.expectEqual(@as(u8, 0x34), try m68k.memory.read8(0x2002));
    try std.testing.expectEqual(@as(u32, 16), cycles);
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
    const cycles = try m68k.step();
    try std.testing.expectEqual(@as(u32, 888), try m68k.memory.read32(0x2000));
    try std.testing.expectEqual(@as(u32, 999), try m68k.memory.read32(0x3000));
    try std.testing.expectEqual(@as(u32, 20), cycles);
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
    const long_cycles = try m68k.step();

    // Check: Z flag should be set (equal), both pointers incremented by 4
    try std.testing.expect((m68k.sr & M68k.FLAG_Z) != 0);
    try std.testing.expectEqual(@as(u32, 0x1004), m68k.a[0]);
    try std.testing.expectEqual(@as(u32, 0x2004), m68k.a[1]);
    try std.testing.expectEqual(@as(u32, 12), long_cycles);

    // Test CMPM.W with different values
    m68k.a[2] = 0x3000;
    m68k.a[3] = 0x4000;
    try m68k.memory.write16(0x3000, 0x1234);
    try m68k.memory.write16(0x4000, 0x5678);

    // CMPM.W (A3)+,(A2)+ - opcode: 0xB54B (size=01, Ax=2, Ay=3)
    try m68k.memory.write16(0x102, 0xB54B);
    m68k.pc = 0x102;
    const word_cycles = try m68k.step();

    // Check: Z flag should be clear (not equal), N flag set (negative result)
    try std.testing.expect((m68k.sr & M68k.FLAG_Z) == 0);
    try std.testing.expect((m68k.sr & M68k.FLAG_N) != 0);
    try std.testing.expectEqual(@as(u32, 0x3002), m68k.a[2]);
    try std.testing.expectEqual(@as(u32, 0x4002), m68k.a[3]);
    try std.testing.expectEqual(@as(u32, 12), word_cycles);
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
    const cycles_1 = try m68k.step();

    try std.testing.expectEqual(@as(u8, 0x77), @as(u8, @truncate(m68k.d[0])));
    try std.testing.expect((m68k.sr & M68k.FLAG_C) == 0); // No carry
    try std.testing.expectEqual(@as(u32, 6), cycles_1);

    // Test with carry: 0x99 + 0x01 = 0x00 with carry
    m68k.d[2] = 0x99;
    m68k.d[3] = 0x01;
    m68k.sr &= ~M68k.FLAG_X;

    // ABCD D3,D2 - opcode: 0xC503
    try m68k.memory.write16(0x102, 0xC503);
    m68k.pc = 0x102;
    const cycles_2 = try m68k.step();

    try std.testing.expectEqual(@as(u8, 0x00), @as(u8, @truncate(m68k.d[2])));
    try std.testing.expect((m68k.sr & M68k.FLAG_C) != 0); // Carry set
    try std.testing.expect((m68k.sr & M68k.FLAG_X) != 0); // Extend set
    try std.testing.expectEqual(@as(u32, 6), cycles_2);
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
    const cycles = try m68k.step();

    try std.testing.expectEqual(@as(u8, 0x29), @as(u8, @truncate(m68k.d[0])));
    try std.testing.expect((m68k.sr & M68k.FLAG_C) == 0); // No borrow
    try std.testing.expectEqual(@as(u32, 6), cycles);
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
    const cycles = try m68k.step();

    try std.testing.expectEqual(@as(u8, 0x52), @as(u8, @truncate(m68k.d[0])));
    try std.testing.expect((m68k.sr & M68k.FLAG_C) != 0); // Borrow set
    try std.testing.expectEqual(@as(u32, 6), cycles);
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
    const movec_sfc_cycles = try m68k.step();

    try std.testing.expectEqual(@as(u3, 5), m68k.sfc);
    try std.testing.expectEqual(@as(u32, 12), movec_sfc_cycles);

    // Test MOVEC D1,DFC - Move to DFC (Destination Function Code)
    m68k.d[1] = 3;
    // MOVEC D1,DFC - opcode: 0x4E7B 0x1001 (D1=0x1000, DFC=1)
    try m68k.memory.write16(0x104, 0x4E7B);
    try m68k.memory.write16(0x106, 0x1001);
    m68k.pc = 0x104;
    const movec_dfc_cycles = try m68k.step();

    try std.testing.expectEqual(@as(u3, 3), m68k.dfc);
    try std.testing.expectEqual(@as(u32, 12), movec_dfc_cycles);

    // Test MOVEC A0,USP - Move to USP (User Stack Pointer)
    m68k.a[0] = 0x12345678;
    // MOVEC A0,USP - opcode: 0x4E7B 0x8800 (A0=0x8000, USP=0x800)
    try m68k.memory.write16(0x108, 0x4E7B);
    try m68k.memory.write16(0x10A, 0x8800);
    m68k.pc = 0x108;
    const movec_usp_cycles = try m68k.step();

    try std.testing.expectEqual(@as(u32, 0x12345678), m68k.usp);
    try std.testing.expectEqual(@as(u32, 12), movec_usp_cycles);

    // Test MOVEC VBR,D2 - Move from VBR
    m68k.vbr = 0xABCDEF00;
    // MOVEC VBR,D2 - opcode: 0x4E7A 0x2801 (D2=0x2000, VBR=0x801)
    try m68k.memory.write16(0x10C, 0x4E7A);
    try m68k.memory.write16(0x10E, 0x2801);
    m68k.pc = 0x10C;
    const movec_vbr_cycles = try m68k.step();

    try std.testing.expectEqual(@as(u32, 0xABCDEF00), m68k.d[2]);
    try std.testing.expectEqual(@as(u32, 12), movec_vbr_cycles);

    // Test MOVEC CACR,D3 - Move from CACR (Cache Control Register)
    m68k.cacr = 0x00000101;
    // MOVEC CACR,D3 - opcode: 0x4E7A 0x3002 (D3=0x3000, CACR=2)
    try m68k.memory.write16(0x110, 0x4E7A);
    try m68k.memory.write16(0x112, 0x3002);
    m68k.pc = 0x110;
    const movec_cacr_cycles = try m68k.step();

    try std.testing.expectEqual(@as(u32, 0x00000101), m68k.d[3]);
    try std.testing.expectEqual(@as(u32, 14), movec_cacr_cycles);
}

test "M68k MOVEC stack registers do not force active A7 sync" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    m68k.setSR(0x0000); // establish user mode first
    m68k.setStackRegister(.User, 0x1000);
    m68k.setStackRegister(.Interrupt, 0x2000);
    m68k.setStackRegister(.Master, 0x3000);
    m68k.a[7] = 0x1000;
    m68k.setSR(M68k.FLAG_S); // interrupt stack active

    m68k.a[0] = 0xAAAA0000;
    // MOVEC A0,ISP (0x804)
    try m68k.memory.write16(0x200, 0x4E7B);
    try m68k.memory.write16(0x202, 0x8804);
    m68k.pc = 0x200;
    const movec_isp_write_cycles = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0xAAAA0000), m68k.getStackRegister(.Interrupt));
    try std.testing.expectEqual(@as(u32, 0x2000), m68k.a[7]); // unchanged active A7
    try std.testing.expectEqual(@as(u32, 12), movec_isp_write_cycles);

    // MOVEC ISP,D1 reads the raw ISP register value.
    try m68k.memory.write16(0x204, 0x4E7A);
    try m68k.memory.write16(0x206, 0x1804);
    m68k.pc = 0x204;
    const movec_isp_read_cycles = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0xAAAA0000), m68k.d[1]);
    try std.testing.expectEqual(@as(u32, 12), movec_isp_read_cycles);

    m68k.setSR(M68k.FLAG_S | M68k.FLAG_M); // master stack active
    m68k.a[2] = 0xBBBB0000;
    // MOVEC A2,MSP (0x803)
    try m68k.memory.write16(0x208, 0x4E7B);
    try m68k.memory.write16(0x20A, 0xA803);
    m68k.pc = 0x208;
    const movec_msp_write_cycles = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0xBBBB0000), m68k.getStackRegister(.Master));
    try std.testing.expectEqual(@as(u32, 0x3000), m68k.a[7]); // unchanged active A7
    try std.testing.expectEqual(@as(u32, 12), movec_msp_write_cycles);

    // MOVEC MSP,D2
    try m68k.memory.write16(0x20C, 0x4E7A);
    try m68k.memory.write16(0x20E, 0x2803);
    m68k.pc = 0x20C;
    const movec_msp_read_cycles = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0xBBBB0000), m68k.d[2]);
    try std.testing.expectEqual(@as(u32, 12), movec_msp_read_cycles);

    m68k.a[3] = 0xCCCC0000;
    // MOVEC A3,USP (0x800)
    try m68k.memory.write16(0x210, 0x4E7B);
    try m68k.memory.write16(0x212, 0xB800);
    m68k.pc = 0x210;
    const movec_usp_write_cycles = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0xCCCC0000), m68k.getStackRegister(.User));
    try std.testing.expectEqual(@as(u32, 0x3000), m68k.a[7]); // still master A7
    try std.testing.expectEqual(@as(u32, 12), movec_usp_write_cycles);
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
    const user_priv_cycles = try m68k.step();

    try std.testing.expectEqual(@as(u32, 0xD200), m68k.pc);
    try std.testing.expectEqual(@as(u3, 0), m68k.sfc);
    try std.testing.expectEqual(@as(u32, 34), user_priv_cycles);
}

test "M68k MOVEC invalid control register encodings route to vector 4" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    try m68k.memory.write32(m68k.getExceptionVector(4), 0xD280);

    // MOVEC D0,<invalid control reg 0x805>
    try m68k.memory.write16(0xD240, 0x4E7B);
    try m68k.memory.write16(0xD242, 0x0805);
    m68k.pc = 0xD240;
    m68k.a[7] = 0x4840;
    m68k.setSR(0x2000);
    const invalid_to_ctrl_cycles = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0xD280), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x4838), m68k.a[7]);
    try std.testing.expectEqual(@as(u16, 4 * 4), try m68k.memory.read16(0x483E));
    try std.testing.expectEqual(@as(u32, 0xD240), try m68k.memory.read32(0x483A));
    try std.testing.expectEqual(@as(u32, 34), invalid_to_ctrl_cycles);

    // MOVEC <invalid control reg 0x805>,D1
    try m68k.memory.write16(0xD250, 0x4E7A);
    try m68k.memory.write16(0xD252, 0x1805);
    m68k.pc = 0xD250;
    m68k.a[7] = 0x4860;
    m68k.setSR(0x2000);
    const invalid_from_ctrl_cycles = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0xD280), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x4858), m68k.a[7]);
    try std.testing.expectEqual(@as(u16, 4 * 4), try m68k.memory.read16(0x485E));
    try std.testing.expectEqual(@as(u32, 0xD250), try m68k.memory.read32(0x485A));
    try std.testing.expectEqual(@as(u32, 34), invalid_from_ctrl_cycles);
}

test "M68k MOVE USP transfers and user restore consistency" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    m68k.setSR(0x2000); // supervisor
    m68k.setStackRegister(.User, 0x11110000);
    m68k.a[2] = 0x22220000;
    const active_sp_before = m68k.a[7];

    // MOVE A2,USP
    try m68k.memory.write16(0xE000, 0x4E62);
    // MOVE USP,A3
    try m68k.memory.write16(0xE002, 0x4E6B);
    m68k.pc = 0xE000;

    const move_to_usp_cycles = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0x22220000), m68k.getStackRegister(.User));
    try std.testing.expectEqual(active_sp_before, m68k.a[7]); // active ISP unchanged
    try std.testing.expectEqual(@as(u32, 4), move_to_usp_cycles);

    const move_from_usp_cycles = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0x22220000), m68k.a[3]);
    try std.testing.expectEqual(@as(u32, 4), move_from_usp_cycles);

    // Switching back to user mode should load the updated USP into A7.
    m68k.setSR(0x0000);
    try std.testing.expectEqual(@as(u32, 0x22220000), m68k.a[7]);
}

test "M68k MOVE USP privilege violation in user mode" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    try m68k.memory.write32(m68k.getExceptionVector(8), 0xE100);
    try m68k.memory.write16(0xE000, 0x4E62); // MOVE A2,USP

    m68k.pc = 0xE000;
    m68k.a[2] = 0x12345678;
    m68k.setSR(0x0000); // user mode
    m68k.setStackPointer(.User, 0x2000);
    const user_mode_cycles = try m68k.step();

    try std.testing.expectEqual(@as(u32, 0xE100), m68k.pc);
    try std.testing.expectEqual(@as(u32, 34), user_mode_cycles);
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
    const format0_cycles = try m68k.step();

    try std.testing.expectEqual(@as(u16, 0x2700), m68k.sr);
    try std.testing.expectEqual(@as(u32, 0x1000), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x2008), m68k.a[7]); // SP += 8 (format 0)
    try std.testing.expectEqual(@as(u32, 20), format0_cycles);

    // Test Format 2 (6-word format, 12 bytes)
    m68k.a[7] = 0x3000;
    try m68k.memory.write16(0x3000, 0x2000); // SR
    try m68k.memory.write32(0x3002, 0x2000); // PC
    try m68k.memory.write16(0x3006, 0x201C); // Format 2, Vector 7 (TRAPV)

    m68k.pc = 0x100;
    const format2_cycles = try m68k.step();

    try std.testing.expectEqual(@as(u16, 0x2000), m68k.sr);
    try std.testing.expectEqual(@as(u32, 0x2000), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x300C), m68k.a[7]); // SP += 12 (format 2)
    try std.testing.expectEqual(@as(u32, 20), format2_cycles);

    // Test Format 9 (coprocessor mid-instruction, 20 bytes)
    m68k.a[7] = 0x4000;
    try m68k.memory.write16(0x4000, 0x2100); // SR
    try m68k.memory.write32(0x4002, 0x3000); // PC
    try m68k.memory.write16(0x4006, 0x902C); // Format 9, Vector 11

    m68k.pc = 0x100;
    const format9_cycles = try m68k.step();

    try std.testing.expectEqual(@as(u16, 0x2100), m68k.sr);
    try std.testing.expectEqual(@as(u32, 0x3000), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x4014), m68k.a[7]); // SP += 20 (format 9)
    try std.testing.expectEqual(@as(u32, 20), format9_cycles);

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

    // Test Format B (long bus cycle fault, 84 bytes)
    m68k.a[7] = 0x6000;
    try m68k.memory.write16(0x6000, 0x2700); // SR
    try m68k.memory.write32(0x6002, 0x4800); // PC
    try m68k.memory.write16(0x6006, 0xB008); // Format B, Vector 2

    m68k.pc = 0x100;
    _ = try m68k.step();

    try std.testing.expectEqual(@as(u16, 0x2700), m68k.sr);
    try std.testing.expectEqual(@as(u32, 0x4800), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x6054), m68k.a[7]); // SP += 84 (format B)
}

test "M68k RTE privilege violation in user mode" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    try m68k.memory.write32(m68k.getExceptionVector(8), 0x5A00);
    try m68k.memory.write16(0x1100, 0x4E73); // RTE
    m68k.pc = 0x1100;
    m68k.a[7] = 0x3400;
    m68k.setSR(0x0000); // user mode

    const cycles = try m68k.step();

    try std.testing.expectEqual(@as(u32, 0x5A00), m68k.pc);
    try std.testing.expectEqual(@as(u32, 34), cycles);
    try std.testing.expectEqual(@as(u32, 0x33F8), m68k.a[7]);
    try std.testing.expectEqual(@as(u16, 0x0000), try m68k.memory.read16(0x33F8));
    try std.testing.expectEqual(@as(u32, 0x1100), try m68k.memory.read32(0x33FA));
    try std.testing.expectEqual(@as(u16, 8 * 4), try m68k.memory.read16(0x33FE));
}

test "M68k nested TRAP exceptions unwind correctly with RTE" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    // Main code: TRAP #0
    try m68k.memory.write16(0x1200, 0x4E40);
    // Vector 32 handler: TRAP #1, then RTE
    try m68k.memory.write32(m68k.getExceptionVector(32), 0x4000);
    try m68k.memory.write16(0x4000, 0x4E41);
    try m68k.memory.write16(0x4002, 0x4E73);
    // Vector 33 handler: RTE
    try m68k.memory.write32(m68k.getExceptionVector(33), 0x5000);
    try m68k.memory.write16(0x5000, 0x4E73);

    m68k.pc = 0x1200;
    m68k.a[7] = 0x3800;
    m68k.setSR(0x0000); // user mode

    _ = try m68k.step(); // TRAP #0 -> handler 0x4000
    try std.testing.expectEqual(@as(u32, 0x4000), m68k.pc);

    _ = try m68k.step(); // TRAP #1 inside handler -> handler 0x5000
    try std.testing.expectEqual(@as(u32, 0x5000), m68k.pc);

    _ = try m68k.step(); // RTE from nested trap -> back to 0x4002
    try std.testing.expectEqual(@as(u32, 0x4002), m68k.pc);

    _ = try m68k.step(); // outer RTE -> back to user code after TRAP #0
    try std.testing.expectEqual(@as(u32, 0x1202), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x3800), m68k.a[7]);
    try std.testing.expectEqual(@as(u16, 0x0000), m68k.sr);
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

test "M68k setSR stack transition matrix preserves banked pointers" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    m68k.setSR(0x0000); // establish user mode first
    m68k.setStackPointer(.User, 0x1110);
    m68k.setStackRegister(.Interrupt, 0x2220);
    m68k.setStackRegister(.Master, 0x3330);

    try std.testing.expectEqual(@as(u32, 0x1110), m68k.a[7]);

    m68k.a[7] = 0x1111; // User -> User
    m68k.setSR(0x0000);
    try std.testing.expectEqual(@as(u32, 0x1111), m68k.getStackRegister(.User));
    try std.testing.expectEqual(@as(u32, 0x1111), m68k.a[7]);

    m68k.a[7] = 0x1112; // User -> ISP
    m68k.setSR(M68k.FLAG_S);
    try std.testing.expectEqual(@as(u32, 0x1112), m68k.getStackRegister(.User));
    try std.testing.expectEqual(@as(u32, 0x2220), m68k.a[7]);

    m68k.a[7] = 0x2221; // ISP -> ISP
    m68k.setSR(M68k.FLAG_S);
    try std.testing.expectEqual(@as(u32, 0x2221), m68k.getStackRegister(.Interrupt));
    try std.testing.expectEqual(@as(u32, 0x2221), m68k.a[7]);

    m68k.a[7] = 0x2222; // ISP -> MSP
    m68k.setSR(M68k.FLAG_S | M68k.FLAG_M);
    try std.testing.expectEqual(@as(u32, 0x2222), m68k.getStackRegister(.Interrupt));
    try std.testing.expectEqual(@as(u32, 0x3330), m68k.a[7]);

    m68k.a[7] = 0x3331; // MSP -> MSP
    m68k.setSR(M68k.FLAG_S | M68k.FLAG_M);
    try std.testing.expectEqual(@as(u32, 0x3331), m68k.getStackRegister(.Master));
    try std.testing.expectEqual(@as(u32, 0x3331), m68k.a[7]);

    m68k.a[7] = 0x3332; // MSP -> User
    m68k.setSR(0x0000);
    try std.testing.expectEqual(@as(u32, 0x3332), m68k.getStackRegister(.Master));
    try std.testing.expectEqual(@as(u32, 0x1112), m68k.a[7]);

    m68k.a[7] = 0x1113; // User -> MSP
    m68k.setSR(M68k.FLAG_S | M68k.FLAG_M);
    try std.testing.expectEqual(@as(u32, 0x1113), m68k.getStackRegister(.User));
    try std.testing.expectEqual(@as(u32, 0x3332), m68k.a[7]);

    m68k.a[7] = 0x3333; // MSP -> ISP
    m68k.setSR(M68k.FLAG_S);
    try std.testing.expectEqual(@as(u32, 0x3333), m68k.getStackRegister(.Master));
    try std.testing.expectEqual(@as(u32, 0x2222), m68k.a[7]);

    m68k.a[7] = 0x2223; // ISP -> User
    m68k.setSR(0x0000);
    try std.testing.expectEqual(@as(u32, 0x2223), m68k.getStackRegister(.Interrupt));
    try std.testing.expectEqual(@as(u32, 0x1113), m68k.a[7]);

    // M bit is ignored when S=0, so user stack stays active.
    m68k.a[7] = 0x1114;
    m68k.setSR(M68k.FLAG_M);
    try std.testing.expect((m68k.sr & M68k.FLAG_S) == 0);
    try std.testing.expectEqual(@as(u32, 0x1114), m68k.getStackRegister(.User));
    try std.testing.expectEqual(@as(u32, 0x1114), m68k.a[7]);
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

test "M68k IRQ from user mode uses ISP and RTE restores USP" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    m68k.setSR(0x0000); // user mode
    m68k.setStackPointer(.User, 0x1100);
    m68k.setStackRegister(.Interrupt, 0x2100);
    m68k.setStackRegister(.Master, 0x3100);
    try std.testing.expectEqual(@as(u32, 0x1100), m68k.a[7]);

    // Level 3 autovector handler: RTE
    try m68k.memory.write32(m68k.getExceptionVector(27), 0x4600);
    try m68k.memory.write16(0x4600, 0x4E73); // RTE
    try m68k.memory.write16(0x0100, 0x4E71); // main NOP
    m68k.pc = 0x0100;

    m68k.setInterruptLevel(3);
    _ = try m68k.step(); // IRQ entry

    try std.testing.expectEqual(@as(u32, 0x4600), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x20F8), m68k.a[7]); // ISP frame pushed
    try std.testing.expectEqual(@as(u32, 0x1100), m68k.getStackRegister(.User)); // USP preserved
    try std.testing.expect((m68k.sr & M68k.FLAG_S) != 0);
    try std.testing.expect((m68k.sr & M68k.FLAG_M) == 0);

    _ = try m68k.step(); // RTE

    try std.testing.expectEqual(@as(u32, 0x0100), m68k.pc);
    try std.testing.expect((m68k.sr & M68k.FLAG_S) == 0); // back to user
    try std.testing.expectEqual(@as(u32, 0x1100), m68k.a[7]); // USP restored
    try std.testing.expectEqual(@as(u32, 0x2100), m68k.getStackRegister(.Interrupt)); // ISP frame consumed
}

test "M68k nested IRQ frames stay on ISP and unwind with RTE" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    m68k.setStackRegister(.Interrupt, 0x3200);
    m68k.a[7] = 0x3200;
    m68k.setSR(0x2000); // supervisor, interrupt stack active

    // Level 2 and level 5 handlers both RTE.
    try m68k.memory.write32(m68k.getExceptionVector(26), 0x4A00);
    try m68k.memory.write32(m68k.getExceptionVector(29), 0x4B00);
    try m68k.memory.write16(0x4A00, 0x4E73); // RTE
    try m68k.memory.write16(0x4B00, 0x4E73); // RTE
    try m68k.memory.write16(0x1400, 0x4E71); // main NOP
    m68k.pc = 0x1400;

    m68k.setInterruptLevel(2);
    _ = try m68k.step(); // enter level 2
    try std.testing.expectEqual(@as(u32, 0x4A00), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x31F8), m68k.a[7]);
    try std.testing.expectEqual(@as(u3, 2), @as(u3, @truncate((m68k.sr >> 8) & 7)));

    m68k.setInterruptLevel(5);
    _ = try m68k.step(); // preempt to level 5 before executing level2 RTE
    try std.testing.expectEqual(@as(u32, 0x4B00), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x31F0), m68k.a[7]);
    try std.testing.expectEqual(@as(u3, 5), @as(u3, @truncate((m68k.sr >> 8) & 7)));

    _ = try m68k.step(); // RTE from level 5 -> back to level 2 handler
    try std.testing.expectEqual(@as(u32, 0x4A00), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x31F8), m68k.a[7]);
    try std.testing.expectEqual(@as(u3, 2), @as(u3, @truncate((m68k.sr >> 8) & 7)));

    _ = try m68k.step(); // RTE from level 2 -> back to main
    try std.testing.expectEqual(@as(u32, 0x1400), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x3200), m68k.a[7]);
    try std.testing.expectEqual(@as(u16, 0x2000), m68k.sr);
    try std.testing.expectEqual(@as(u32, 0x3200), m68k.getStackRegister(.Interrupt));
}

test "M68k IRQ from master mode switches to ISP and RTE restores MSP" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    m68k.setSR(M68k.FLAG_S | M68k.FLAG_M); // master mode active
    m68k.setStackPointer(.User, 0x1000);
    m68k.setStackRegister(.Interrupt, 0x2000);
    m68k.setStackPointer(.Master, 0x3000);

    // Level 3 autovector handler: RTE
    try m68k.memory.write32(m68k.getExceptionVector(27), 0x4700);
    try m68k.memory.write16(0x4700, 0x4E73); // RTE
    try m68k.memory.write16(0x0100, 0x4E71); // main NOP
    m68k.pc = 0x0100;

    m68k.setInterruptLevel(3);
    _ = try m68k.step(); // IRQ entry

    try std.testing.expectEqual(@as(u32, 0x4700), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x1FF8), m68k.a[7]); // switched to ISP
    try std.testing.expectEqual(@as(u32, 0x3000), m68k.getStackRegister(.Master)); // MSP preserved
    try std.testing.expect((m68k.sr & M68k.FLAG_S) != 0);
    try std.testing.expect((m68k.sr & M68k.FLAG_M) == 0);

    _ = try m68k.step(); // RTE

    try std.testing.expectEqual(@as(u32, 0x0100), m68k.pc);
    try std.testing.expect((m68k.sr & M68k.FLAG_S) != 0);
    try std.testing.expect((m68k.sr & M68k.FLAG_M) != 0); // back to master
    try std.testing.expectEqual(@as(u32, 0x3000), m68k.a[7]); // MSP restored
    try std.testing.expectEqual(@as(u32, 0x2000), m68k.getStackRegister(.Interrupt)); // ISP frame consumed
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

test "M68k PMMU compat mode handles coprocessor-id0 F-line without vector 11" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    m68k.setPmmuCompatEnabled(true);
    try m68k.memory.write16(0x1540, 0xF000); // coprocessor-id 0
    try m68k.memory.write16(0x1542, 0x0000); // minimal extension word
    m68k.pc = 0x1540;
    m68k.a[7] = 0x3710;
    m68k.setSR(0x0000); // user mode

    const cycles = try m68k.step();
    try std.testing.expectEqual(@as(u32, 20), cycles);
    try std.testing.expectEqual(@as(u32, 0x1544), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x3710), m68k.a[7]); // no exception frame
    try std.testing.expectEqual(@as(u32, 0), m68k.pmmu_mmusr);
}

test "M68k PMMU compat mode does not intercept non-PMMU coprocessor-id opcodes" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    m68k.setPmmuCompatEnabled(true);
    try m68k.memory.write32(m68k.getExceptionVector(11), 0x5A40);
    try m68k.memory.write16(0x1550, 0xF200); // coprocessor-id 1 (non-PMMU)
    m68k.pc = 0x1550;
    m68k.a[7] = 0x3720;
    m68k.setSR(0x0000);

    const cycles = try m68k.step();
    try std.testing.expectEqual(@as(u32, 34), cycles);
    try std.testing.expectEqual(@as(u32, 0x5A40), m68k.pc);
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

    const cycles = try m68k.step();
    try std.testing.expect(ctx.called);
    try std.testing.expectEqual(@as(u32, 34), cycles);
    try std.testing.expectEqual(@as(u32, 0x5A80), m68k.pc);
}

test "M68k coprocessor handler fault routes to vector 2 format A bus error frame" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    var ctx = CoprocTestContext{ .emulate_fault = true, .fault_addr = 0x00A01234 };
    m68k.setCoprocessorHandler(coprocTestHandler, &ctx);
    try m68k.memory.write32(m68k.getExceptionVector(2), 0x5AC0);
    try m68k.memory.write16(0x1530, 0xF240);

    m68k.pc = 0x1530;
    m68k.a[7] = 0x3720;
    m68k.setSR(0x0000); // user mode

    const cycles = try m68k.step();
    try std.testing.expect(ctx.called);
    try std.testing.expectEqual(@as(u32, 50), cycles);
    try std.testing.expectEqual(@as(u32, 0x5AC0), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x3708), m68k.a[7]);
    try std.testing.expectEqual(@as(u16, 0xA008), try m68k.memory.read16(0x370E)); // vector 2 in format A
    try std.testing.expectEqual(@as(u32, 0x00A01234), try m68k.memory.read32(0x3710)); // precise fault address
    try std.testing.expectEqual(@as(u16, 0x5000), try m68k.memory.read16(0x3714)); // program read FC captured in frame
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

    const cycles = try m68k.step();

    try std.testing.expectEqual(@as(u32, 0x5B00), m68k.pc);
    try std.testing.expectEqual(@as(u32, 34), cycles);
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

    const cycles = try m68k.step();

    try std.testing.expectEqual(@as(u32, 0x5B80), m68k.pc);
    try std.testing.expectEqual(@as(u32, 34), cycles);
    try std.testing.expectEqual(@as(u32, 0x3878), m68k.a[7]);
    try std.testing.expectEqual(@as(u16, 10 * 4), try m68k.memory.read16(0x387E));
    try std.testing.expectEqual(@as(u32, 0x1680), try m68k.memory.read32(0x387A));
}

test "M68k line-A/F boundary opcodes preserve faulting PC and vectors" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    try m68k.memory.write32(m68k.getExceptionVector(10), 0x5BA0);
    try m68k.memory.write32(m68k.getExceptionVector(11), 0x5BE0);

    // Highest line-A opcode
    try m68k.memory.write16(0x1690, 0xAFFF);
    m68k.pc = 0x1690;
    m68k.a[7] = 0x3890;
    m68k.setSR(0x0000);
    _ = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0x5BA0), m68k.pc);
    try std.testing.expectEqual(@as(u16, 10 * 4), try m68k.memory.read16(0x388E));
    try std.testing.expectEqual(@as(u32, 0x1690), try m68k.memory.read32(0x388A));

    // Highest line-F opcode
    try m68k.memory.write16(0x1698, 0xFFFF);
    m68k.pc = 0x1698;
    m68k.a[7] = 0x38B0;
    m68k.setSR(0x0000);
    _ = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0x5BE0), m68k.pc);
    try std.testing.expectEqual(@as(u16, 11 * 4), try m68k.memory.read16(0x38AE));
    try std.testing.expectEqual(@as(u32, 0x1698), try m68k.memory.read32(0x38AA));
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

    const cycles = try m68k.step();

    try std.testing.expectEqual(@as(u32, 0x5BC0), m68k.pc);
    try std.testing.expectEqual(@as(u32, 10), cycles);
    try std.testing.expectEqual(@as(u32, 0x38B8), m68k.a[7]);
    try std.testing.expectEqual(@as(u16, 0x2000), try m68k.memory.read16(0x38B8)); // stacked SR
    try std.testing.expectEqual(@as(u32, 0x16C0), try m68k.memory.read32(0x38BA)); // offending PC
    try std.testing.expectEqual(@as(u16, 4 * 4), try m68k.memory.read16(0x38BE)); // vector word
}

test "M68k BKPT handler can consume breakpoint without exception" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    var ctx = BkptTestContext{};
    m68k.setBkptHandler(bkptTestHandler, &ctx);
    try m68k.memory.write16(0x16E0, 0x484F); // BKPT #7
    m68k.pc = 0x16E0;
    m68k.a[7] = 0x38E0;
    m68k.setSR(0x2000);

    const cycles = try m68k.step();

    try std.testing.expect(ctx.called);
    try std.testing.expectEqual(@as(u3, 7), ctx.last_vector);
    try std.testing.expectEqual(@as(u32, 14), cycles);
    try std.testing.expectEqual(@as(u32, 0x16E2), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0xB16B00B5), m68k.d[1]);
    try std.testing.expectEqual(@as(u32, 0x38E0), m68k.a[7]); // no exception frame pushed
}

test "M68k odd instruction fetch raises address error vector 3" {
    const allocator = std.testing.allocator;
    var m68k = M68k.initWithConfig(allocator, .{ .enforce_alignment = true });
    defer m68k.deinit();

    try m68k.memory.write32(m68k.getExceptionVector(3), 0x5BE0);
    m68k.pc = 0x1801;
    m68k.a[7] = 0x3A80;
    m68k.setSR(0x2000);

    const cycles = try m68k.step();

    try std.testing.expectEqual(@as(u32, 0x5BE0), m68k.pc);
    try std.testing.expectEqual(@as(u32, 50), cycles);
    try std.testing.expectEqual(@as(u32, 0x3A68), m68k.a[7]); // format A (24-byte)
    try std.testing.expectEqual(@as(u16, 0xA00C), try m68k.memory.read16(0x3A6E)); // vector 3
    try std.testing.expectEqual(@as(u32, 0x1801), try m68k.memory.read32(0x3A6A)); // return PC
    try std.testing.expectEqual(@as(u32, 0x1801), try m68k.memory.read32(0x3A70)); // fault address
    try std.testing.expectEqual(@as(u16, 0xD000), try m68k.memory.read16(0x3A74)); // FC=supervisor program read
}

test "M68k misaligned data word access raises address error vector 3" {
    const allocator = std.testing.allocator;
    var m68k = M68k.initWithConfig(allocator, .{ .enforce_alignment = true });
    defer m68k.deinit();

    try m68k.memory.write32(m68k.getExceptionVector(3), 0x5C20);
    try m68k.memory.write16(0x1820, 0x3080); // MOVE.W D0,(A0)
    m68k.a[0] = 0x2001; // odd address
    m68k.pc = 0x1820;
    m68k.a[7] = 0x3AC0;
    m68k.setSR(0x2000);

    const cycles = try m68k.step();

    try std.testing.expectEqual(@as(u32, 0x5C20), m68k.pc);
    try std.testing.expectEqual(@as(u32, 54), cycles);
    try std.testing.expectEqual(@as(u32, 0x3AA8), m68k.a[7]); // format A (24-byte)
    try std.testing.expectEqual(@as(u16, 0xA00C), try m68k.memory.read16(0x3AAE)); // vector 3
    try std.testing.expectEqual(@as(u32, 0x1820), try m68k.memory.read32(0x3AAA)); // return PC
    try std.testing.expectEqual(@as(u32, 0x2001), try m68k.memory.read32(0x3AB0)); // precise misaligned data address
    try std.testing.expectEqual(@as(u16, 0x0800), try m68k.memory.read16(0x3AB4)); // FC from DFC(default 0), data write
}

test "M68k out-of-range data word write raises bus error vector 2 with execute-data cycles" {
    const allocator = std.testing.allocator;
    var m68k = M68k.initWithConfig(allocator, .{ .size = 0x1000 });
    defer m68k.deinit();

    try m68k.memory.write32(m68k.getExceptionVector(2), 0x0800);
    try m68k.memory.write16(0x0180, 0x3080); // MOVE.W D0,(A0)
    m68k.d[0] = 0x1234;
    m68k.a[0] = 0x1000; // out of range for 16-bit write in 0x0000..0x0FFF
    m68k.pc = 0x0180;
    m68k.a[7] = 0x0F00;
    m68k.setSR(0x2000);

    const cycles = try m68k.step();

    try std.testing.expectEqual(@as(u32, 0x0800), m68k.pc);
    try std.testing.expectEqual(@as(u32, 54), cycles);
    try std.testing.expectEqual(@as(u32, 0x0EE8), m68k.a[7]); // format A (24-byte)
    try std.testing.expectEqual(@as(u16, 0xA008), try m68k.memory.read16(0x0EEE)); // vector 2
    try std.testing.expectEqual(@as(u32, 0x1000), try m68k.memory.read32(0x0EF0)); // fault address
    try std.testing.expectEqual(@as(u16, 0x0800), try m68k.memory.read16(0x0EF4)); // FC from DFC(default 0), data write
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

    const cycles = try m68k.step();

    try std.testing.expectEqual(@as(u32, 0x5C00), m68k.pc);
    try std.testing.expectEqual(@as(u32, 34), cycles);
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

    const cycles = try m68k.step();

    try std.testing.expectEqual(@as(u32, 0x5D00), m68k.pc);
    try std.testing.expectEqual(@as(u32, 34), cycles);
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
    const complex_read_cycles = try m68k.executor.execute(&m68k, &read_inst);
    try std.testing.expectEqual(@as(u32, 0xDEADBEEF), m68k.d[0]);
    // ComplexEA with index: 4 (base) + 10 (src EA) + 0 (dst reg) = 14
    try std.testing.expectEqual(@as(u32, 14), complex_read_cycles);

    m68k.d[2] = 0xAABBCCDD;
    var write_inst = decoder.Instruction.init();
    write_inst.mnemonic = .MOVE;
    write_inst.size = 2;
    write_inst.data_size = .Long;
    write_inst.src = .{ .DataReg = 2 };
    write_inst.dst = read_inst.src;

    const complex_write_cycles = try m68k.executor.execute(&m68k, &write_inst);
    try std.testing.expectEqual(@as(u32, 0xAABBCCDD), try m68k.memory.read32(0x1014));
    // ComplexEA with index: 4 (base) + 0 (src reg) + 10 (dst EA) = 14
    try std.testing.expectEqual(@as(u32, 14), complex_write_cycles);
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
    const pack_reg_cycles = try m68k.executor.execute(&m68k, &pack_reg);
    try std.testing.expectEqual(@as(u8, 0x45), @as(u8, @truncate(m68k.d[0])));
    try std.testing.expectEqual(@as(u32, 5), pack_reg_cycles);

    // UNPK D1,D0,#0 : 0x45 -> 0x0405
    var unpk_reg = decoder.Instruction.init();
    unpk_reg.mnemonic = .UNPK;
    unpk_reg.size = 4;
    unpk_reg.src = .{ .DataReg = 1 };
    unpk_reg.dst = .{ .DataReg = 0 };
    unpk_reg.extension_word = 0x0000;
    m68k.d[1] = 0x00000045;
    m68k.pc = 0x104;
    const unpk_reg_cycles = try m68k.executor.execute(&m68k, &unpk_reg);
    try std.testing.expectEqual(@as(u16, 0x0405), @as(u16, @truncate(m68k.d[0])));
    try std.testing.expectEqual(@as(u32, 5), unpk_reg_cycles);

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
    const pack_mem_cycles = try m68k.executor.execute(&m68k, &pack_mem);
    try std.testing.expectEqual(@as(u32, 0x2000), m68k.a[1]);
    try std.testing.expectEqual(@as(u32, 0x3000), m68k.a[0]);
    try std.testing.expectEqual(@as(u8, 0x45), try m68k.memory.read8(0x3000));
    try std.testing.expectEqual(@as(u32, 6), pack_mem_cycles);

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
    const unpk_mem_cycles = try m68k.executor.execute(&m68k, &unpk_mem);
    try std.testing.expectEqual(@as(u32, 0x4000), m68k.a[1]);
    try std.testing.expectEqual(@as(u32, 0x5000), m68k.a[0]);
    try std.testing.expectEqual(@as(u16, 0x0405), try m68k.memory.read16(0x5000));
    try std.testing.expectEqual(@as(u32, 6), unpk_mem_cycles);
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
    const cmp2_cycles = try m68k.executor.execute(&m68k, &cmp2);
    try std.testing.expect((m68k.sr & M68k.FLAG_Z) != 0);
    try std.testing.expectEqual(@as(u32, 12), cmp2_cycles);

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
    const chk2_cycles = try m68k.executor.execute(&m68k, &chk2);

    try std.testing.expectEqual(@as(u32, 0x7000), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x2FF8), m68k.a[7]);
    try std.testing.expectEqual(@as(u32, 44), chk2_cycles);
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
    const lsl_cycles = try m68k.executor.execute(&m68k, &lsl);
    try std.testing.expectEqual(@as(u8, 0x00), @as(u8, @truncate(m68k.d[0])));
    try std.testing.expect((m68k.sr & M68k.FLAG_C) != 0);
    try std.testing.expect((m68k.sr & M68k.FLAG_X) != 0);
    try std.testing.expectEqual(@as(u32, 8), lsl_cycles);

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
    const roxl_cycles = try m68k.executor.execute(&m68k, &roxl);
    try std.testing.expectEqual(@as(u8, 0x01), @as(u8, @truncate(m68k.d[0])));
    try std.testing.expect((m68k.sr & M68k.FLAG_C) != 0);
    try std.testing.expect((m68k.sr & M68k.FLAG_X) != 0);
    try std.testing.expectEqual(@as(u32, 8), roxl_cycles);

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
    const roxr_cycles = try m68k.executor.execute(&m68k, &roxr);
    try std.testing.expectEqual(@as(u8, 0x80), @as(u8, @truncate(m68k.d[0])));
    try std.testing.expect((m68k.sr & M68k.FLAG_C) != 0);
    try std.testing.expect((m68k.sr & M68k.FLAG_X) != 0);
    try std.testing.expectEqual(@as(u32, 8), roxr_cycles);
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

    const cycles = try m68k.executor.execute(&m68k, &movea);

    try std.testing.expectEqual(@as(u32, 0xFFFF8000), m68k.a[0]);
    try std.testing.expectEqual(@as(u32, 0x604), m68k.pc);
    try std.testing.expectEqual(@as(u16, 0x001F), m68k.sr & 0x001F);
    try std.testing.expectEqual(@as(u32, 4), cycles);
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
    const no_trap_cycles = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0x702), m68k.pc);
    try std.testing.expectEqual(@as(u32, 4), no_trap_cycles);

    // V=1: trap to vector 7
    m68k.pc = 0x700;
    m68k.a[7] = 0x4100;
    m68k.setSR(0x2000);
    m68k.setFlag(M68k.FLAG_V, true);
    const trap_cycles = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0x7200), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x40F8), m68k.a[7]);
    try std.testing.expectEqual(@as(u32, 0x702), try m68k.memory.read32(0x40FA)); // return PC
    try std.testing.expectEqual(@as(u16, 7 * 4), try m68k.memory.read16(0x40FE));
    try std.testing.expectEqual(@as(u32, 34), trap_cycles);
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

    const stop_enter_cycles = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0x804), m68k.pc);
    try std.testing.expect(m68k.stopped);
    try std.testing.expectEqual(@as(u32, 4), stop_enter_cycles);

    const stop_wait_cycles = try m68k.step(); // still stopped, no IRQ
    try std.testing.expectEqual(@as(u32, 0x804), m68k.pc);
    try std.testing.expect(m68k.stopped);
    try std.testing.expectEqual(@as(u32, 4), stop_wait_cycles);

    m68k.setInterruptLevel(2);
    const irq_entry_cycles = try m68k.step(); // IRQ must wake STOP
    try std.testing.expectEqual(@as(u32, 0x9000), m68k.pc);
    try std.testing.expect(!m68k.stopped);
    try std.testing.expectEqual(@as(u32, 44), irq_entry_cycles);
}

test "M68k bus retry on instruction fetch stalls one step then executes normally" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    var ctx = BusHookTestContext{ .mode = .retry_once_program_fetch };
    m68k.memory.setBusHook(busHookTestHandler, &ctx);

    try m68k.memory.write16(0x8800, 0x4E71); // NOP
    m68k.pc = 0x8800;

    const retry_cycles = try m68k.step();
    try std.testing.expectEqual(@as(u32, 4), retry_cycles);
    try std.testing.expectEqual(@as(u32, 0x8800), m68k.pc);
    try std.testing.expect(ctx.retried_once);
    try std.testing.expect(!m68k.stopped);

    const exec_cycles = try m68k.step();
    try std.testing.expectEqual(@as(u32, 4), exec_cycles);
    try std.testing.expectEqual(@as(u32, 0x8802), m68k.pc);
}

test "M68k bus halt on instruction fetch stops CPU and IRQ resumes execution path" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    var ctx = BusHookTestContext{ .mode = .halt_program_fetch };
    m68k.memory.setBusHook(busHookTestHandler, &ctx);

    try m68k.memory.write16(0x8900, 0x4E71); // NOP (never fetched while halted)
    try m68k.memory.write32(m68k.getExceptionVector(26), 0x8A00); // level-2 autovector handler

    m68k.pc = 0x8900;
    m68k.a[7] = 0x6000;
    m68k.setSR(0x2000);

    const halt_cycles = try m68k.step();
    try std.testing.expectEqual(@as(u32, 4), halt_cycles);
    try std.testing.expect(m68k.stopped);
    try std.testing.expectEqual(@as(u32, 0x8900), m68k.pc);

    m68k.setInterruptLevel(2);
    const irq_cycles = try m68k.step();
    try std.testing.expectEqual(@as(u32, 44), irq_cycles);
    try std.testing.expect(!m68k.stopped);
    try std.testing.expectEqual(@as(u32, 0x8A00), m68k.pc);
}

test "M68k bus hook observes program fetch FC for user and supervisor modes" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    var ctx = BusHookTestContext{ .mode = .capture_program_fetch };
    m68k.memory.setBusHook(busHookTestHandler, &ctx);

    try m68k.memory.write16(0x8B00, 0x4E71); // NOP
    try m68k.memory.write16(0x8B02, 0x4E71); // NOP

    // User mode fetch FC must be 0b010.
    m68k.pc = 0x8B00;
    m68k.setSR(0x0000);
    try std.testing.expectEqual(@as(u32, 4), try m68k.step());
    try std.testing.expect(ctx.saw_program_fetch);
    try std.testing.expectEqual(@as(u3, 0b010), ctx.last_access.function_code);
    try std.testing.expectEqual(memory.AccessSpace.Program, ctx.last_access.space);
    try std.testing.expect(!ctx.last_access.is_write);

    // Supervisor mode fetch FC must be 0b110.
    ctx.saw_program_fetch = false;
    m68k.pc = 0x8B02;
    m68k.setSR(0x2000);
    try std.testing.expectEqual(@as(u32, 4), try m68k.step());
    try std.testing.expect(ctx.saw_program_fetch);
    try std.testing.expectEqual(@as(u3, 0b110), ctx.last_access.function_code);
    try std.testing.expectEqual(memory.AccessSpace.Program, ctx.last_access.space);
    try std.testing.expect(!ctx.last_access.is_write);
}

test "M68k bus hook data-write error enters vector 2 with DFC in format A access word" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    var ctx = BusHookTestContext{ .mode = .bus_error_on_data_write, .error_target_addr = 0x2400 };
    m68k.memory.setBusHook(busHookTestHandler, &ctx);

    try m68k.memory.write32(m68k.getExceptionVector(2), 0x9400);
    try m68k.memory.write16(0x8C00, 0x3080); // MOVE.W D0,(A0)

    m68k.pc = 0x8C00;
    m68k.a[0] = 0x2400;
    m68k.a[7] = 0x5200;
    m68k.setSR(0x2000);
    m68k.d[0] = 0x00001234;
    m68k.dfc = 0b101;

    const cycles = try m68k.step();
    try std.testing.expectEqual(@as(u32, 54), cycles);
    try std.testing.expectEqual(@as(u32, 0x9400), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x51E8), m68k.a[7]);
    try std.testing.expectEqual(@as(u16, 0xA008), try m68k.memory.read16(0x51EE)); // vector 2 format A
    try std.testing.expectEqual(@as(u32, 0x2400), try m68k.memory.read32(0x51F0)); // precise fault address
    try std.testing.expectEqual(@as(u16, 0xA800), try m68k.memory.read16(0x51F4)); // FC=5, data write
    try std.testing.expect(ctx.saw_data_write);
    try std.testing.expectEqual(@as(u3, 0b101), ctx.last_access.function_code);
    try std.testing.expectEqual(memory.AccessSpace.Data, ctx.last_access.space);
    try std.testing.expect(ctx.last_access.is_write);
}

test "M68k data access translator remaps execute write while preserving logical bus address observation" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    var ctx = BusHookTestContext{ .mode = .pass_through };
    m68k.memory.setBusHook(busHookTestHandler, &ctx);
    m68k.memory.setAddressTranslator(dataAccessAddTranslator, null);

    // Write instruction directly to data[] to bypass address translator
    // (instruction setup is not a data-space access)
    std.mem.writeInt(u16, m68k.memory.data[0x8D00..0x8D02], 0x3080, .big); // MOVE.W D0,(A0)
    m68k.pc = 0x8D00;
    m68k.a[0] = 0x0300; // logical data address, translated to 0x1300
    m68k.d[0] = 0x00001234;
    m68k.setSR(0x2000);
    m68k.dfc = 0b011;

    // MOVE.W D0,(A0): 4 (base) + 0 (src reg) + 4 (dst indirect) = 8
    try std.testing.expectEqual(@as(u32, 8), try m68k.step());
    // Verify physical memory directly (bypassing address translator)
    const b0: u16 = m68k.memory.data[0x1300];
    const b1: u16 = m68k.memory.data[0x1301];
    try std.testing.expectEqual(@as(u16, 0x1234), (b0 << 8) | b1); // translated target
    const c0: u16 = m68k.memory.data[0x0300];
    const c1: u16 = m68k.memory.data[0x0301];
    try std.testing.expectEqual(@as(u16, 0x0000), (c0 << 8) | c1); // logical location unchanged
    try std.testing.expect(ctx.saw_data_write);
    try std.testing.expectEqual(@as(u32, 0x0300), ctx.last_addr); // hook sees logical address
    try std.testing.expectEqual(@as(u3, 0b011), ctx.last_access.function_code);
    try std.testing.expectEqual(memory.AccessSpace.Data, ctx.last_access.space);
    try std.testing.expect(ctx.last_access.is_write);
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
    const stop_cycles = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0xA000), m68k.pc);
    try std.testing.expectEqual(@as(u32, 34), stop_cycles);
    try std.testing.expectEqual(@as(u16, 8 * 4), try m68k.memory.read16(0x42FE));
    try std.testing.expectEqual(@as(u32, 0xA100), try m68k.memory.read32(0x42FA));

    // RESET in user mode => privilege violation
    try m68k.memory.write16(0xA200, 0x4E70);
    m68k.pc = 0xA200;
    m68k.a[7] = 0x4400;
    m68k.setSR(0x0000);
    const reset_cycles = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0xA000), m68k.pc);
    try std.testing.expectEqual(@as(u32, 34), reset_cycles);
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
    const cycles = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0xB002), m68k.pc);
    try std.testing.expectEqual(@as(u32, 132), cycles);
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
    const false_cycles = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0xC102), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x4500), m68k.a[7]);
    try std.testing.expectEqual(@as(u32, 3), false_cycles);

    // 0x50FC = TRAPT (no extension), return PC must be +2.
    try m68k.memory.write16(0xC200, 0x50FC);
    m68k.pc = 0xC200;
    m68k.a[7] = 0x4600;
    m68k.setSR(0x2000);
    const trap_short_cycles = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0xC000), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x45F8), m68k.a[7]);
    try std.testing.expectEqual(@as(u32, 0xC202), try m68k.memory.read32(0x45FA));
    try std.testing.expectEqual(@as(u32, 33), trap_short_cycles);

    // 0x50FA = TRAPT.W #imm16, return PC must be +4.
    try m68k.memory.write16(0xC300, 0x50FA);
    try m68k.memory.write16(0xC302, 0x1234);
    m68k.pc = 0xC300;
    m68k.a[7] = 0x4700;
    m68k.setSR(0x2000);
    const trap_word_cycles = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0xC000), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x46F8), m68k.a[7]);
    try std.testing.expectEqual(@as(u32, 0xC304), try m68k.memory.read32(0x46FA));
    try std.testing.expectEqual(@as(u32, 33), trap_word_cycles);

    // 0x50FB = TRAPT.L #imm32, return PC must be +6.
    try m68k.memory.write16(0xC400, 0x50FB);
    try m68k.memory.write32(0xC402, 0x89ABCDEF);
    m68k.pc = 0xC400;
    m68k.a[7] = 0x4800;
    m68k.setSR(0x2000);
    const trap_long_cycles = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0xC000), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x47F8), m68k.a[7]);
    try std.testing.expectEqual(@as(u32, 0xC406), try m68k.memory.read32(0x47FA));
    try std.testing.expectEqual(@as(u32, 33), trap_long_cycles);
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
    const cycles = try m68k.step();

    try std.testing.expectEqual(@as(u32, 0xD100), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x48F8), m68k.a[7]);
    try std.testing.expectEqual(@as(u16, 4 * 4), try m68k.memory.read16(0x48FE));
    try std.testing.expectEqual(@as(u32, 0xD000), try m68k.memory.read32(0x48FA));
    try std.testing.expectEqual(@as(u32, 34), cycles);
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
    const mode3_cycles = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0xD300), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x4A78), m68k.a[7]);
    try std.testing.expectEqual(@as(u32, 0xD200), try m68k.memory.read32(0x4A7A));
    try std.testing.expectEqual(@as(u16, 4 * 4), try m68k.memory.read16(0x4A7E));
    try std.testing.expectEqual(@as(u32, 34), mode3_cycles);

    // mode=7, reg>3 is illegal for CALLM.
    try m68k.memory.write16(0xD210, 0x06FC);
    m68k.pc = 0xD210;
    m68k.a[7] = 0x4B00;
    m68k.setSR(0x2000);
    const mode7_cycles = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0xD300), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x4AF8), m68k.a[7]);
    try std.testing.expectEqual(@as(u32, 0xD210), try m68k.memory.read32(0x4AFA));
    try std.testing.expectEqual(@as(u16, 4 * 4), try m68k.memory.read16(0x4AFE));
    try std.testing.expectEqual(@as(u32, 34), mode7_cycles);
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
    const ori_ccr_cycles = try m68k.step();
    try std.testing.expectEqual(@as(u16, 0x11), m68k.sr & 0x1F);
    try std.testing.expectEqual(@as(u32, 20), ori_ccr_cycles);

    // ANDI to CCR
    try m68k.memory.write16(0xE010, 0x023C);
    try m68k.memory.write16(0xE012, 0x0001); // keep only C
    m68k.pc = 0xE010;
    const andi_ccr_cycles = try m68k.step();
    try std.testing.expectEqual(@as(u16, 0x01), m68k.sr & 0x1F);
    try std.testing.expectEqual(@as(u32, 20), andi_ccr_cycles);

    // EORI to CCR
    try m68k.memory.write16(0xE020, 0x0A3C);
    try m68k.memory.write16(0xE022, 0x0003); // toggle C,V
    m68k.pc = 0xE020;
    const eori_ccr_cycles = try m68k.step();
    try std.testing.expectEqual(@as(u16, 0x02), m68k.sr & 0x1F);
    try std.testing.expectEqual(@as(u32, 20), eori_ccr_cycles);

    // ORI to SR in supervisor mode
    try m68k.memory.write16(0xE030, 0x007C);
    try m68k.memory.write16(0xE032, 0x0700); // set IPL=7
    m68k.pc = 0xE030;
    m68k.sr = 0x2002;
    const ori_sr_cycles = try m68k.step();
    try std.testing.expectEqual(@as(u16, 0x2702), m68k.sr);
    try std.testing.expectEqual(@as(u32, 20), ori_sr_cycles);

    // ANDI to SR in user mode => privilege violation
    try m68k.memory.write16(0xE040, 0x027C);
    try m68k.memory.write16(0xE042, 0xF8FF);
    try m68k.memory.write32(m68k.getExceptionVector(8), 0xE100);
    m68k.pc = 0xE040;
    m68k.a[7] = 0x4A00;
    m68k.sr = 0x0000;
    const andi_sr_user_cycles = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0xE100), m68k.pc);
    try std.testing.expectEqual(@as(u32, 34), andi_sr_user_cycles);

    // EORI to SR in supervisor mode
    try m68k.memory.write16(0xE050, 0x0A7C);
    try m68k.memory.write16(0xE052, 0x0007);
    m68k.pc = 0xE050;
    m68k.sr = 0x2000;
    const eori_sr_cycles = try m68k.step();
    try std.testing.expectEqual(@as(u16, 0x2007), m68k.sr);
    try std.testing.expectEqual(@as(u32, 20), eori_sr_cycles);
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
    const callm_cycles = try m68k.step();

    try std.testing.expectEqual(@as(u32, 0xE542), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x4FF4), m68k.a[7]);
    try std.testing.expectEqual(@as(u32, 0x12345678), m68k.d[3]);
    try std.testing.expectEqual(@as(u16, 0x0015), try m68k.memory.read16(0x4FF4));
    try std.testing.expectEqual(@as(u32, 0xE308), try m68k.memory.read32(0x4FF6));
    try std.testing.expectEqual(@as(u32, 0xAABBCCDD), try m68k.memory.read32(0x4FFA));
    try std.testing.expectEqual(@as(u16, 0x0004), try m68k.memory.read16(0x4FFE));
    try std.testing.expectEqual(@as(u32, 40), callm_cycles);

    m68k.setSR((m68k.sr & 0xFF00) | 0x00);
    m68k.d[3] = 0;
    const rtm_cycles = try m68k.step();

    try std.testing.expectEqual(@as(u32, 0xE308), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x5004), m68k.a[7]);
    try std.testing.expectEqual(@as(u32, 0xAABBCCDD), m68k.d[3]);
    try std.testing.expectEqual(@as(u16, 0x0015), m68k.sr & 0x00FF);
    try std.testing.expectEqual(@as(u32, 24), rtm_cycles);
}

test "M68k TAS works for data register and memory operands" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    // TAS D0
    try m68k.memory.write16(0xE560, 0x4AC0);
    m68k.pc = 0xE560;
    m68k.d[0] = 0x00000001;
    const tas_reg_cycles = try m68k.step();
    try std.testing.expectEqual(@as(u8, 0x81), @as(u8, @truncate(m68k.d[0])));
    try std.testing.expect((m68k.sr & M68k.FLAG_Z) == 0);
    try std.testing.expect((m68k.sr & M68k.FLAG_N) == 0);
    try std.testing.expectEqual(@as(u32, 4), tas_reg_cycles);

    // TAS (A0)
    try m68k.memory.write16(0xE570, 0x4AD0);
    try m68k.memory.write8(0x2200, 0x00);
    m68k.pc = 0xE570;
    m68k.a[0] = 0x2200;
    const tas_mem_cycles = try m68k.step();
    try std.testing.expectEqual(@as(u8, 0x80), try m68k.memory.read8(0x2200));
    try std.testing.expect((m68k.sr & M68k.FLAG_Z) != 0);
    try std.testing.expectEqual(@as(u32, 14), tas_mem_cycles);
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

test "M68k MOVEM cycle model covers register count direction size and addressing mode" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    // 1) reg->mem, long, predecrement, 2 regs: 8 + (8*2) + 2 = 26
    try m68k.memory.write16(0xEA00, 0x48E0); // MOVEM.L <mask>,-(A0)
    try m68k.memory.write16(0xEA02, 0x0003); // D0-D1
    m68k.pc = 0xEA00;
    m68k.a[0] = 0x6008;
    m68k.d[0] = 0x11111111;
    m68k.d[1] = 0x22222222;
    try std.testing.expectEqual(@as(u32, 26), try m68k.step());

    // 2) reg->mem, long, predecrement, 3 regs: 8 + (8*3) + 2 = 34
    try m68k.memory.write16(0xEA10, 0x48E0);
    try m68k.memory.write16(0xEA12, 0x0007); // D0-D2
    m68k.pc = 0xEA10;
    m68k.a[0] = 0x610C;
    try std.testing.expectEqual(@as(u32, 34), try m68k.step());

    // 3) reg->mem, word, (A1), 2 regs: 8 + (4*2) + 0 = 16
    try m68k.memory.write16(0xEA20, 0x4891); // MOVEM.W <mask>,(A1)
    try m68k.memory.write16(0xEA22, 0x0003); // D0-D1
    m68k.pc = 0xEA20;
    m68k.a[1] = 0x6200;
    try std.testing.expectEqual(@as(u32, 16), try m68k.step());

    // 4) mem->reg, word, postincrement, 2 regs: 8 + (5*2) + 2 = 20
    try m68k.memory.write16(0xEA30, 0x4C99); // MOVEM.W (A1)+,<mask>
    try m68k.memory.write16(0xEA32, 0x000C); // D2-D3
    try m68k.memory.write16(0x6300, 0xFFFE);
    try m68k.memory.write16(0x6302, 0x0001);
    m68k.pc = 0xEA30;
    m68k.a[1] = 0x6300;
    try std.testing.expectEqual(@as(u32, 20), try m68k.step());

    // 5) mem->reg, long, postincrement, 2 regs: 8 + (9*2) + 2 = 28
    try m68k.memory.write16(0xEA40, 0x4CD9); // MOVEM.L (A1)+,<mask>
    try m68k.memory.write16(0xEA42, 0x0030); // D4-D5
    try m68k.memory.write32(0x6400, 0xAAAABBBB);
    try m68k.memory.write32(0x6404, 0xCCCCDDDD);
    m68k.pc = 0xEA40;
    m68k.a[1] = 0x6400;
    try std.testing.expectEqual(@as(u32, 28), try m68k.step());

    // 6) reg->mem, long, d16(A2), 1 reg: 8 + (8*1) + 2 = 18
    try m68k.memory.write16(0xEA50, 0x48EA); // MOVEM.L <mask>,(d16,A2)
    try m68k.memory.write16(0xEA52, 0x0001); // D0
    try m68k.memory.write16(0xEA54, 0x0010);
    m68k.pc = 0xEA50;
    m68k.a[2] = 0x6500;
    m68k.d[0] = 0xDEADBEEF;
    try std.testing.expectEqual(@as(u32, 18), try m68k.step());
}

test "M68k branch cycle model reflects displacement-size and condition outcome" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    var bra = decoder.Instruction.init();
    bra.mnemonic = .BRA;

    bra.size = 2;
    bra.src = .{ .Immediate8 = 2 };
    m68k.pc = 0x100;
    try std.testing.expectEqual(@as(u32, 10), try m68k.executor.execute(&m68k, &bra));
    try std.testing.expectEqual(@as(u32, 0x104), m68k.pc);

    bra.size = 4;
    bra.src = .{ .Immediate16 = 2 };
    m68k.pc = 0x200;
    try std.testing.expectEqual(@as(u32, 12), try m68k.executor.execute(&m68k, &bra));
    try std.testing.expectEqual(@as(u32, 0x204), m68k.pc);

    bra.size = 6;
    bra.src = .{ .Immediate32 = 2 };
    m68k.pc = 0x300;
    try std.testing.expectEqual(@as(u32, 14), try m68k.executor.execute(&m68k, &bra));
    try std.testing.expectEqual(@as(u32, 0x304), m68k.pc);

    var bvs = decoder.Instruction.init();
    bvs.mnemonic = .Bcc;
    bvs.opcode = 0x6900; // condition 9 (VS)

    m68k.setFlag(M68k.FLAG_V, false);
    bvs.size = 2;
    bvs.src = .{ .Immediate8 = 2 };
    m68k.pc = 0x400;
    try std.testing.expectEqual(@as(u32, 8), try m68k.executor.execute(&m68k, &bvs));
    try std.testing.expectEqual(@as(u32, 0x402), m68k.pc);

    bvs.size = 4;
    bvs.src = .{ .Immediate16 = 2 };
    m68k.pc = 0x500;
    try std.testing.expectEqual(@as(u32, 10), try m68k.executor.execute(&m68k, &bvs));
    try std.testing.expectEqual(@as(u32, 0x504), m68k.pc);

    bvs.size = 6;
    bvs.src = .{ .Immediate32 = 2 };
    m68k.pc = 0x600;
    try std.testing.expectEqual(@as(u32, 12), try m68k.executor.execute(&m68k, &bvs));
    try std.testing.expectEqual(@as(u32, 0x606), m68k.pc);

    m68k.setFlag(M68k.FLAG_V, true);
    bvs.size = 4;
    bvs.src = .{ .Immediate16 = 2 };
    m68k.pc = 0x700;
    try std.testing.expectEqual(@as(u32, 12), try m68k.executor.execute(&m68k, &bvs));
    try std.testing.expectEqual(@as(u32, 0x704), m68k.pc);
}

test "M68k bitfield cycle model differentiates register and memory operands" {
    const allocator = std.testing.allocator;
    var m68k = M68k.init(allocator);
    defer m68k.deinit();

    var bftst = decoder.Instruction.init();
    bftst.mnemonic = .BFTST;
    bftst.size = 4;
    bftst.src = .{ .Immediate16 = 0x0001 }; // offset=0, width=1
    bftst.dst = .{ .DataReg = 0 };
    m68k.d[0] = 1;
    m68k.pc = 0x800;
    try std.testing.expectEqual(@as(u32, 6), try m68k.executor.execute(&m68k, &bftst));

    bftst.dst = .{ .Address = 0x9000 };
    try m68k.memory.write32(0x9000, 1);
    m68k.pc = 0x810;
    try std.testing.expectEqual(@as(u32, 10), try m68k.executor.execute(&m68k, &bftst));

    var bfset = decoder.Instruction.init();
    bfset.mnemonic = .BFSET;
    bfset.size = 4;
    bfset.src = .{ .Immediate16 = 0x0001 };
    bfset.dst = .{ .DataReg = 1 };
    m68k.d[1] = 0;
    m68k.pc = 0x820;
    try std.testing.expectEqual(@as(u32, 10), try m68k.executor.execute(&m68k, &bfset));
    try std.testing.expectEqual(@as(u32, 1), m68k.d[1] & 1);

    bfset.dst = .{ .Address = 0x9010 };
    try m68k.memory.write32(0x9010, 0);
    m68k.pc = 0x830;
    try std.testing.expectEqual(@as(u32, 14), try m68k.executor.execute(&m68k, &bfset));
    try std.testing.expectEqual(@as(u32, 1), try m68k.memory.read32(0x9010));

    var bfffo = decoder.Instruction.init();
    bfffo.mnemonic = .BFFFO;
    bfffo.size = 4;
    bfffo.src = .{ .Immediate16 = 0x3001 }; // D3 destination, offset=0, width=1
    bfffo.dst = .{ .DataReg = 2 };
    m68k.d[2] = 1;
    m68k.pc = 0x840;
    try std.testing.expectEqual(@as(u32, 10), try m68k.executor.execute(&m68k, &bfffo));
    try std.testing.expectEqual(@as(u32, 0), m68k.d[3]);

    bfffo.dst = .{ .Address = 0x9020 };
    try m68k.memory.write32(0x9020, 1);
    m68k.pc = 0x850;
    try std.testing.expectEqual(@as(u32, 14), try m68k.executor.execute(&m68k, &bfffo));
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
    const tst_cycles = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0xE804), m68k.pc);
    try std.testing.expectEqual(@as(u32, 12), tst_cycles);

    // PEA (16,A1)
    try m68k.memory.write16(0xE810, 0x4869);
    try m68k.memory.write16(0xE812, 0x0010);
    m68k.a[1] = 0x2500;
    m68k.a[7] = 0x6000;
    m68k.pc = 0xE810;
    const pea_cycles = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0xE814), m68k.pc);
    try std.testing.expectEqual(@as(u32, 0x5FFC), m68k.a[7]);
    try std.testing.expectEqual(@as(u32, 0x2510), try m68k.memory.read32(0x5FFC));
    try std.testing.expectEqual(@as(u32, 12), pea_cycles);

    // ST (16,A2) : Scc with true condition to memory.
    try m68k.memory.write16(0xE820, 0x50EA);
    try m68k.memory.write16(0xE822, 0x0010);
    m68k.a[2] = 0x2600;
    m68k.pc = 0xE820;
    const scc_cycles = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0xE824), m68k.pc);
    try std.testing.expectEqual(@as(u8, 0xFF), try m68k.memory.read8(0x2610));
    try std.testing.expectEqual(@as(u32, 12), scc_cycles);

    // MULU.W (16,A3),D0
    try m68k.memory.write16(0xE830, 0xC0EB);
    try m68k.memory.write16(0xE832, 0x0010);
    m68k.a[3] = 0x2700;
    try m68k.memory.write16(0x2710, 3);
    m68k.d[0] = 2;
    m68k.pc = 0xE830;
    const mulu_w_cycles = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0xE834), m68k.pc);
    try std.testing.expectEqual(@as(u32, 6), m68k.d[0]);
    try std.testing.expectEqual(@as(u32, 38), mulu_w_cycles);
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

    const mem_shift_cycles = try m68k.step();

    try std.testing.expectEqual(@as(u32, 0xE904), m68k.pc);
    try std.testing.expectEqual(@as(u16, 0x0002), try m68k.memory.read16(0x2810));
    try std.testing.expectEqual(@as(u32, 8), mem_shift_cycles);
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
    const mulu_l_cycles = try m68k.step();
    try std.testing.expectEqual(@as(u32, 15), m68k.d[1]);
    try std.testing.expectEqual(@as(u32, 0), m68k.d[2]);
    try std.testing.expect(!m68k.getFlag(M68k.FLAG_V));
    try std.testing.expect(!m68k.getFlag(M68k.FLAG_C));
    try std.testing.expectEqual(@as(u32, 40), mulu_l_cycles);

    // MULS.L #4,D3:D4 with overflow in 32-bit signed result.
    try m68k.memory.write16(0xE610, 0x4C3C);
    try m68k.memory.write16(0xE612, 0x4C03);
    try m68k.memory.write32(0xE614, 0x00000004);
    m68k.pc = 0xE610;
    m68k.d[3] = 0x40000000;
    m68k.d[4] = 0;
    const muls_l_cycles = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0), m68k.d[3]);
    try std.testing.expectEqual(@as(u32, 1), m68k.d[4]);
    try std.testing.expect(m68k.getFlag(M68k.FLAG_V));
    try std.testing.expectEqual(@as(u32, 40), muls_l_cycles);

    // DIVU.L #2,D1:D2 : dividend = D2:D1 = 0x00000001_00000000
    try m68k.memory.write16(0xE620, 0x4C3C);
    try m68k.memory.write16(0xE622, 0x2001);
    try m68k.memory.write32(0xE624, 0x00000002);
    m68k.pc = 0xE620;
    m68k.d[1] = 0x00000000;
    m68k.d[2] = 0x00000001;
    const divu_l_cycles = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0x80000000), m68k.d[1]);
    try std.testing.expectEqual(@as(u32, 0), m68k.d[2]);
    try std.testing.expect(!m68k.getFlag(M68k.FLAG_V));
    try std.testing.expectEqual(@as(u32, 76), divu_l_cycles);

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
    const divs_l_divzero_cycles = try m68k.step();
    try std.testing.expectEqual(@as(u32, 0xE700), m68k.pc);
    try std.testing.expectEqual(@as(u32, 70), divs_l_divzero_cycles);
}
