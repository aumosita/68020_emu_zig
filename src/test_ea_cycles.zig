const std = @import("std");
const ea_cycles = @import("ea_cycles.zig");
const decoder = @import("decoder.zig");

test "EA cycles: Dn (데이터 레지스터 직접)" {
    const op = decoder.Operand{ .DataReg = 0 };
    const cycles_read = ea_cycles.getEACycles(op, .Long, true);
    const cycles_write = ea_cycles.getEACycles(op, .Long, false);
    
    try std.testing.expectEqual(@as(u32, 0), cycles_read);
    try std.testing.expectEqual(@as(u32, 0), cycles_write);
}

test "EA cycles: An (주소 레지스터 직접)" {
    const op = decoder.Operand{ .AddrReg = 0 };
    const cycles_read = ea_cycles.getEACycles(op, .Long, true);
    const cycles_write = ea_cycles.getEACycles(op, .Long, false);
    
    try std.testing.expectEqual(@as(u32, 0), cycles_read);
    try std.testing.expectEqual(@as(u32, 0), cycles_write);
}

test "EA cycles: (An) - 간접 주소" {
    const op = decoder.Operand{ .AddrIndirect = 0 };
    const cycles_read = ea_cycles.getEACycles(op, .Long, true);
    const cycles_write = ea_cycles.getEACycles(op, .Long, false);
    
    try std.testing.expectEqual(@as(u32, 4), cycles_read);
    try std.testing.expectEqual(@as(u32, 4), cycles_write);
}

test "EA cycles: (An)+ - 후치 증가" {
    const op = decoder.Operand{ .AddrPostInc = 0 };
    const cycles_read = ea_cycles.getEACycles(op, .Long, true);
    const cycles_write = ea_cycles.getEACycles(op, .Long, false);
    
    try std.testing.expectEqual(@as(u32, 4), cycles_read);
    try std.testing.expectEqual(@as(u32, 4), cycles_write);
}

test "EA cycles: -(An) - 전치 감소" {
    const op = decoder.Operand{ .AddrPreDec = 0 };
    const cycles_read = ea_cycles.getEACycles(op, .Long, true);
    const cycles_write = ea_cycles.getEACycles(op, .Long, false);
    
    try std.testing.expectEqual(@as(u32, 6), cycles_read);
    try std.testing.expectEqual(@as(u32, 6), cycles_write);
}

test "EA cycles: (d16,An) - 16비트 변위" {
    const op = decoder.Operand{ .AddrDisplace = .{ .reg = 0, .displacement = 100 } };
    const cycles_read = ea_cycles.getEACycles(op, .Long, true);
    const cycles_write = ea_cycles.getEACycles(op, .Long, false);
    
    try std.testing.expectEqual(@as(u32, 8), cycles_read);
    try std.testing.expectEqual(@as(u32, 8), cycles_write);
}

test "EA cycles: (d8,An,Xn) - 인덱스 레지스터 포함" {
    const op = decoder.Operand{ 
        .ComplexEA = .{
            .base_reg = 0,
            .is_pc_relative = false,
            .index_reg = .{ .reg = 1, .is_addr = false, .is_long = true, .scale = 0 },
            .base_disp = 10,
            .outer_disp = 0,
            .is_mem_indirect = false,
            .is_post_indexed = false,
        }
    };
    const cycles_read = ea_cycles.getEACycles(op, .Long, true);
    const cycles_write = ea_cycles.getEACycles(op, .Long, false);
    
    try std.testing.expectEqual(@as(u32, 10), cycles_read);
    try std.testing.expectEqual(@as(u32, 10), cycles_write);
}

test "EA cycles: 메모리 간접 모드" {
    const op = decoder.Operand{ 
        .ComplexEA = .{
            .base_reg = 0,
            .is_pc_relative = false,
            .index_reg = null,
            .base_disp = 0,
            .outer_disp = 0,
            .is_mem_indirect = true,
            .is_post_indexed = false,
        }
    };
    const cycles_read = ea_cycles.getEACycles(op, .Long, true);
    const cycles_write = ea_cycles.getEACycles(op, .Long, false);
    
    try std.testing.expectEqual(@as(u32, 14), cycles_read);
    try std.testing.expectEqual(@as(u32, 14), cycles_write);
}

test "EA cycles: 즉시값" {
    const op = decoder.Operand{ .Immediate32 = 0x12345678 };
    const cycles_read = ea_cycles.getEACycles(op, .Long, true);
    
    try std.testing.expectEqual(@as(u32, 0), cycles_read);
}

test "EA cycles: 절대 주소" {
    const op = decoder.Operand{ .Address = 0x1000 };
    const cycles_read = ea_cycles.getEACycles(op, .Long, true);
    const cycles_write = ea_cycles.getEACycles(op, .Long, false);
    
    try std.testing.expectEqual(@as(u32, 8), cycles_read);
    try std.testing.expectEqual(@as(u32, 8), cycles_write);
}

test "MOVE cycles: Dn -> Dn (가장 빠른 경우)" {
    const src = decoder.Operand{ .DataReg = 0 };
    const dst = decoder.Operand{ .DataReg = 1 };
    const cycles = ea_cycles.getMoveCycles(src, dst, .Long);
    
    // 4 (기본) + 0 (src) + 0 (dst) = 4
    try std.testing.expectEqual(@as(u32, 4), cycles);
}

test "MOVE cycles: Dn -> (An)" {
    const src = decoder.Operand{ .DataReg = 0 };
    const dst = decoder.Operand{ .AddrIndirect = 0 };
    const cycles = ea_cycles.getMoveCycles(src, dst, .Long);
    
    // 4 (기본) + 0 (src) + 4 (dst) = 8
    try std.testing.expectEqual(@as(u32, 8), cycles);
}

test "MOVE cycles: (An) -> Dn" {
    const src = decoder.Operand{ .AddrIndirect = 0 };
    const dst = decoder.Operand{ .DataReg = 1 };
    const cycles = ea_cycles.getMoveCycles(src, dst, .Long);
    
    // 4 (기본) + 4 (src) + 0 (dst) = 8
    try std.testing.expectEqual(@as(u32, 8), cycles);
}

test "MOVE cycles: (An)+ -> -(An) (메모리 간 이동)" {
    const src = decoder.Operand{ .AddrPostInc = 0 };
    const dst = decoder.Operand{ .AddrPreDec = 1 };
    const cycles = ea_cycles.getMoveCycles(src, dst, .Long);
    
    // 4 (기본) + 4 (src) + 6 (dst) = 14
    try std.testing.expectEqual(@as(u32, 14), cycles);
}

test "MOVE cycles: (d16,An) -> (d16,An) (복잡한 EA)" {
    const src = decoder.Operand{ .AddrDisplace = .{ .reg = 0, .displacement = 10 } };
    const dst = decoder.Operand{ .AddrDisplace = .{ .reg = 1, .displacement = 20 } };
    const cycles = ea_cycles.getMoveCycles(src, dst, .Long);
    
    // 4 (기본) + 8 (src) + 8 (dst) = 20
    try std.testing.expectEqual(@as(u32, 20), cycles);
}

test "EA mode name lookup" {
    try std.testing.expectEqualStrings("Dn", ea_cycles.getEAModeName(.{ .DataReg = 0 }));
    try std.testing.expectEqualStrings("An", ea_cycles.getEAModeName(.{ .AddrReg = 0 }));
    try std.testing.expectEqualStrings("(An)", ea_cycles.getEAModeName(.{ .AddrIndirect = 0 }));
    try std.testing.expectEqualStrings("(An)+", ea_cycles.getEAModeName(.{ .AddrPostInc = 0 }));
    try std.testing.expectEqualStrings("-(An)", ea_cycles.getEAModeName(.{ .AddrPreDec = 0 }));
}
