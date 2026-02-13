const std = @import("std");
const cpu = @import("cpu.zig");

const Mem8 = struct { addr: u32, value: u8 };
const Mem16 = struct { addr: u32, value: u16 };
const Mem32 = struct { addr: u32, value: u32 };
const RegExpect = struct { idx: u8, value: u32 };

const Setup = struct {
    pc: u32,
    sr: u16 = 0x2000,
    steps: u32 = 1,
    d: [8]u32 = [_]u32{0} ** 8,
    a: [8]u32 = [_]u32{0} ** 8,
    memory8: []const Mem8 = &[_]Mem8{},
    memory16: []const Mem16 = &[_]Mem16{},
    memory32: []const Mem32 = &[_]Mem32{},
};

const Expect = struct {
    pc: ?u32 = null,
    sr: ?u16 = null,
    step_cycles: ?u32 = null,
    total_cycles: ?u64 = null,
    d: []const RegExpect = &[_]RegExpect{},
    a: []const RegExpect = &[_]RegExpect{},
    memory8: []const Mem8 = &[_]Mem8{},
    memory16: []const Mem16 = &[_]Mem16{},
    memory32: []const Mem32 = &[_]Mem32{},
};

const VectorCase = struct {
    name: []const u8,
    setup: Setup,
    expect: Expect,
};

fn applySetup(m68k: *cpu.M68k, setup: Setup) !void {
    m68k.pc = setup.pc;
    m68k.setSR(setup.sr);
    m68k.d = setup.d;
    m68k.a = setup.a;
    for (setup.memory8) |w| try m68k.memory.write8(w.addr, w.value);
    for (setup.memory16) |w| try m68k.memory.write16(w.addr, w.value);
    for (setup.memory32) |w| try m68k.memory.write32(w.addr, w.value);
}

fn applyExpect(m68k: *cpu.M68k, expect: Expect, last_step_cycles: u32) !void {
    if (expect.pc) |pc_exp| try std.testing.expectEqual(pc_exp, m68k.pc);
    if (expect.sr) |sr_exp| try std.testing.expectEqual(sr_exp, m68k.sr);
    if (expect.step_cycles) |cyc_exp| try std.testing.expectEqual(cyc_exp, last_step_cycles);
    if (expect.total_cycles) |tot_exp| try std.testing.expectEqual(tot_exp, m68k.cycles);

    for (expect.d) |reg| {
        try std.testing.expect(reg.idx < 8);
        try std.testing.expectEqual(reg.value, m68k.d[reg.idx]);
    }
    for (expect.a) |reg| {
        try std.testing.expect(reg.idx < 8);
        try std.testing.expectEqual(reg.value, m68k.a[reg.idx]);
    }
    for (expect.memory8) |m| try std.testing.expectEqual(m.value, try m68k.memory.read8(m.addr));
    for (expect.memory16) |m| try std.testing.expectEqual(m.value, try m68k.memory.read16(m.addr));
    for (expect.memory32) |m| try std.testing.expectEqual(m.value, try m68k.memory.read32(m.addr));
}

fn runVectorCase(allocator: std.mem.Allocator, case: VectorCase) !void {
    var m68k = cpu.M68k.initWithConfig(allocator, .{ .size = 2 * 1024 * 1024 });
    defer m68k.deinit();

    try applySetup(&m68k, case.setup);
    var last_step_cycles: u32 = 0;
    var i: u32 = 0;
    while (i < case.setup.steps) : (i += 1) {
        last_step_cycles = try m68k.step();
    }
    try applyExpect(&m68k, case.expect, last_step_cycles);
}

pub fn runSubsetDirectory(allocator: std.mem.Allocator, dir_path: []const u8) !void {
    var dir = try std.fs.cwd().openDir(dir_path, .{ .iterate = true });
    defer dir.close();

    var names = std.ArrayList([]u8).init(allocator);
    defer {
        for (names.items) |n| allocator.free(n);
        names.deinit();
    }

    var it = dir.iterate();
    while (try it.next()) |entry| {
        if (entry.kind != .file) continue;
        if (!std.mem.endsWith(u8, entry.name, ".json")) continue;
        try names.append(try allocator.dupe(u8, entry.name));
    }
    std.mem.sort([]u8, names.items, {}, struct {
        fn lessThan(_: void, a: []u8, b: []u8) bool {
            return std.mem.lessThan(u8, a, b);
        }
    }.lessThan);

    for (names.items) |name| {
        const full_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dir_path, name });
        defer allocator.free(full_path);
        const data = try std.fs.cwd().readFileAlloc(allocator, full_path, 64 * 1024);
        defer allocator.free(data);

        const parsed = try std.json.parseFromSlice(VectorCase, allocator, data, .{
            .ignore_unknown_fields = true,
        });
        defer parsed.deinit();

        try runVectorCase(allocator, parsed.value);
    }
}

test "external validation vector subset runner" {
    try runSubsetDirectory(std.testing.allocator, "external_vectors/subset");
}

// TODO: timing 벡터 추가 예정
// test "external timing validation vectors" {
//     try runSubsetDirectory(std.testing.allocator, "external_vectors/timing");
// }

