// EA (Effective Address) 사이클 테이블
// 68020 User's Manual (MC68020UM/AD) Section 9 기준

const decoder = @import("decoder.zig");

/// EA 모드별 기본 사이클 (68020 기준)
/// read: EA 값을 읽는 경우의 추가 사이클
/// write: EA에 값을 쓰는 경우의 추가 사이클
pub const EACycles = struct {
    read: u32,
    write: u32,
};

/// EA 모드에 따른 사이클 계산
pub fn getEACycles(op: decoder.Operand, data_size: decoder.DataSize, is_read: bool) u32 {
    const cycles = getEACyclesTable(op, data_size);
    return if (is_read) cycles.read else cycles.write;
}

fn getEACyclesTable(op: decoder.Operand, _: decoder.DataSize) EACycles {
    return switch (op) {
        // 레지스터 직접 모드 - 추가 사이클 없음
        .DataReg, .AddrReg => .{ .read = 0, .write = 0 },
        
        // 즉시값 - 명령어 fetch 시 이미 포함
        .Immediate8, .Immediate16, .Immediate32 => .{ .read = 0, .write = 0 },
        
        // (An) - 간접 주소
        .AddrIndirect => .{ .read = 4, .write = 4 },
        
        // (An)+ - 후치 증가
        .AddrPostInc => .{ .read = 4, .write = 4 },
        
        // -(An) - 전치 감소
        .AddrPreDec => .{ .read = 6, .write = 6 },
        
        // (d16,An) - 16비트 변위
        .AddrDisplace => .{ .read = 8, .write = 8 },
        
        // 복잡한 EA (d8,An,Xn), (bd,An,Xn) 등
        .ComplexEA => |cea| blk: {
            // 인덱스 레지스터 유무에 따라 다름
            const has_index = cea.index_reg != null;
            const is_mem_indirect = cea.is_mem_indirect;
            
            if (is_mem_indirect) {
                // 메모리 간접: 추가 메모리 접근 필요
                break :blk .{ .read = 14, .write = 14 };
            } else if (has_index) {
                // (d8,An,Xn) 형태
                break :blk .{ .read = 10, .write = 10 };
            } else {
                // (d16,An) 형태 (이미 AddrDisplace에서 처리되지만 대비)
                break :blk .{ .read = 8, .write = 8 };
            }
        },
        
        // 절대 주소 (xxx.W, xxx.L)
        .Address => .{ .read = 8, .write = 8 },
        
        // 비트필드 - 복잡한 계산 필요
        .BitField => .{ .read = 12, .write = 12 },
        
        // 기타
        .None => .{ .read = 0, .write = 0 },
    };
}

/// 데이터 크기에 따른 추가 사이클 (long word는 두 번의 메모리 접근 필요)
pub fn getDataSizePenalty(data_size: decoder.DataSize, is_memory: bool) u32 {
    if (!is_memory) return 0;
    
    return switch (data_size) {
        .Byte => 0,
        .Word => 0,
        .Long => 0, // 68020은 32비트 버스로 한 번에 처리 (68000과 차이점)
    };
}

/// MOVE 명령어 특수 케이스
/// 출처와 목적지 EA를 모두 고려
pub fn getMoveCycles(src: decoder.Operand, dst: decoder.Operand, data_size: decoder.DataSize) u32 {
    const base: u32 = 4; // MOVE 기본 사이클
    const src_cycles = getEACycles(src, data_size, true);
    const dst_cycles = getEACycles(dst, data_size, false);
    
    return base + src_cycles + dst_cycles;
}

/// 테스트용 - EA 모드 이름 반환
pub fn getEAModeName(op: decoder.Operand) []const u8 {
    return switch (op) {
        .DataReg => "Dn",
        .AddrReg => "An",
        .AddrIndirect => "(An)",
        .AddrPostInc => "(An)+",
        .AddrPreDec => "-(An)",
        .AddrDisplace => "(d16,An)",
        .ComplexEA => "(complex)",
        .Address => "xxx",
        .Immediate8, .Immediate16, .Immediate32 => "#imm",
        .BitField => "bitfield",
        .None => "none",
    };
}
