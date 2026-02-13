// 버스 사이클 상태 머신 모듈
// 68020 버스 타이밍 (S0-S1-S2-SW-S3) 모델링

const std = @import("std");

/// 68020 버스 사이클 상태
/// 참고: MC68020 User's Manual Section 7 (Bus Operation)
pub const BusCycleState = enum(u8) {
    /// S0: 주소 준비 (Address setup)
    /// - 주소 버스에 주소 출력
    /// - 기능 코드(FC) 출력
    S0 = 0,
    
    /// S1: 주소 유효 (Address valid)
    /// - AS* (Address Strobe) assert
    /// - R/W 신호 출력
    S1 = 1,
    
    /// S2: 데이터 전송 시작 (Data transfer start)
    /// - DS* (Data Strobe) assert
    /// - Write: 데이터 버스에 데이터 출력
    S2 = 2,
    
    /// SW: Wait state (대기 상태)
    /// - 느린 주변장치 응답 대기
    /// - DSACK* 신호 대기
    /// - 필요한 만큼 반복 가능
    SW = 3,
    
    /// S3: 전송 완료 (Transfer complete)
    /// - Read: 데이터 버스에서 데이터 읽기
    /// - AS*, DS* negate
    S3 = 4,
};

/// 버스 트랜잭션 정보
pub const BusTransaction = struct {
    state: BusCycleState,
    address: u32,
    data: u32,
    is_write: bool,
    data_width: u8, // 1, 2, 4 bytes
    wait_states: u8,
    cycles_elapsed: u8,
};

/// 버스 사이클 설정
pub const BusCycleConfig = struct {
    /// 기본 wait states (모든 접근에 적용)
    default_wait_states: u8 = 0,
    
    /// 주소 범위별 wait states 설정
    region_wait_states: []const WaitStateRegion = &[_]WaitStateRegion{},
};

/// Wait state 영역 정의
pub const WaitStateRegion = struct {
    start: u32,
    end_exclusive: u32,
    wait_states: u8,
};

/// 버스 사이클 상태 머신
pub const BusCycleStateMachine = struct {
    config: BusCycleConfig,
    current_transaction: ?BusTransaction,
    total_wait_cycles: u32,
    last_transaction_cycles: u8, // 마지막 완료된 트랜잭션 사이클
    
    pub fn init(config: BusCycleConfig) BusCycleStateMachine {
        return .{
            .config = config,
            .current_transaction = null,
            .total_wait_cycles = 0,
            .last_transaction_cycles = 0,
        };
    }
    
    /// 새로운 버스 트랜잭션 시작
    pub fn startTransaction(
        self: *BusCycleStateMachine,
        address: u32,
        data: u32,
        is_write: bool,
        data_width: u8,
    ) void {
        const wait_states = self.getWaitStates(address);
        
        self.current_transaction = .{
            .state = .S0,
            .address = address,
            .data = data,
            .is_write = is_write,
            .data_width = data_width,
            .wait_states = wait_states,
            .cycles_elapsed = 0,
        };
    }
    
    /// 상태 머신 한 사이클 진행
    pub fn tick(self: *BusCycleStateMachine) BusCycleState {
        if (self.current_transaction) |*txn| {
            txn.cycles_elapsed += 1;
            
            switch (txn.state) {
                .S0 => txn.state = .S1,
                .S1 => txn.state = .S2,
                .S2 => {
                    if (txn.wait_states > 0) {
                        txn.state = .SW;
                        txn.wait_states -= 1;
                        self.total_wait_cycles += 1;
                    } else {
                        txn.state = .S3;
                    }
                },
                .SW => {
                    if (txn.wait_states > 0) {
                        txn.wait_states -= 1;
                        self.total_wait_cycles += 1;
                    } else {
                        txn.state = .S3;
                    }
                },
                .S3 => {
                    // 트랜잭션 완료 - 사이클 저장
                    self.last_transaction_cycles = txn.cycles_elapsed;
                    self.current_transaction = null;
                },
            }
            
            return txn.state;
        }
        
        return .S3; // 트랜잭션 없음
    }
    
    /// 주소에 따른 wait states 계산
    fn getWaitStates(self: *const BusCycleStateMachine, address: u32) u8 {
        // 영역별 설정 확인
        for (self.config.region_wait_states) |region| {
            if (address >= region.start and address < region.end_exclusive) {
                return region.wait_states;
            }
        }
        
        // 기본값
        return self.config.default_wait_states;
    }
    
    /// 트랜잭션이 완료되었는지 확인
    pub fn isTransactionComplete(self: *const BusCycleStateMachine) bool {
        return self.current_transaction == null;
    }
    
    /// 현재 트랜잭션의 총 사이클 수 (완료된 경우 마지막 값)
    pub fn getTransactionCycles(self: *const BusCycleStateMachine) u8 {
        if (self.current_transaction) |txn| {
            return txn.cycles_elapsed;
        }
        return self.last_transaction_cycles;
    }
    
    /// 누적 wait cycles 조회
    pub fn getTotalWaitCycles(self: *const BusCycleStateMachine) u32 {
        return self.total_wait_cycles;
    }
    
    /// 통계 초기화
    pub fn resetStats(self: *BusCycleStateMachine) void {
        self.total_wait_cycles = 0;
    }
};

/// 단순 사이클 계산 (상태 머신 없이 즉시 계산)
pub fn calculateBusCycles(
    address: u32,
    _: u8, // data_width - 현재 미사용 (향후 확장용)
    config: *const BusCycleConfig,
) u32 {
    var wait_states: u8 = config.default_wait_states;
    
    // 영역별 설정 확인
    for (config.region_wait_states) |region| {
        if (address >= region.start and address < region.end_exclusive) {
            wait_states = region.wait_states;
            break;
        }
    }
    
    // 68020 기본 버스 사이클: 4 (S0-S1-S2-S3)
    // + wait states (각 SW는 1 cycle)
    return 4 + wait_states;
}

test "bus cycle state machine basic transaction" {
    var sm = BusCycleStateMachine.init(.{});
    
    sm.startTransaction(0x1000, 0x12345678, false, 4);
    
    try std.testing.expect(!sm.isTransactionComplete());
    try std.testing.expectEqual(BusCycleState.S0, sm.current_transaction.?.state);
    
    // S0 -> S1
    _ = sm.tick();
    try std.testing.expectEqual(BusCycleState.S1, sm.current_transaction.?.state);
    
    // S1 -> S2
    _ = sm.tick();
    try std.testing.expectEqual(BusCycleState.S2, sm.current_transaction.?.state);
    
    // S2 -> S3 (no wait states)
    _ = sm.tick();
    try std.testing.expectEqual(BusCycleState.S3, sm.current_transaction.?.state);
    
    // S3 -> complete
    _ = sm.tick();
    try std.testing.expect(sm.isTransactionComplete());
    try std.testing.expectEqual(@as(u8, 4), sm.getTransactionCycles());
}

test "bus cycle with wait states" {
    var sm = BusCycleStateMachine.init(.{ .default_wait_states = 2 });
    
    sm.startTransaction(0x1000, 0xAABBCCDD, true, 4);
    
    _ = sm.tick(); // S0 -> S1
    _ = sm.tick(); // S1 -> S2
    _ = sm.tick(); // S2 -> SW (wait 1)
    try std.testing.expectEqual(BusCycleState.SW, sm.current_transaction.?.state);
    
    _ = sm.tick(); // SW (wait 2)
    try std.testing.expectEqual(BusCycleState.SW, sm.current_transaction.?.state);
    
    _ = sm.tick(); // SW -> S3
    try std.testing.expectEqual(BusCycleState.S3, sm.current_transaction.?.state);
    
    _ = sm.tick(); // complete
    try std.testing.expect(sm.isTransactionComplete());
    
    // 4 (기본) + 2 (wait) = 6 cycles
    try std.testing.expectEqual(@as(u32, 2), sm.getTotalWaitCycles());
}

test "bus cycle region-specific wait states" {
    const regions = [_]WaitStateRegion{
        .{ .start = 0x0000, .end_exclusive = 0x1000, .wait_states = 0 }, // RAM
        .{ .start = 0x8000, .end_exclusive = 0xC000, .wait_states = 3 }, // ROM
        .{ .start = 0xF000, .end_exclusive = 0xF100, .wait_states = 5 }, // UART
    };
    
    var sm = BusCycleStateMachine.init(.{
        .default_wait_states = 1,
        .region_wait_states = &regions,
    });
    
    // RAM 접근 (0 wait)
    sm.startTransaction(0x0500, 0, false, 4);
    try std.testing.expectEqual(@as(u8, 0), sm.current_transaction.?.wait_states);
    
    // ROM 접근 (3 wait)
    sm.current_transaction = null;
    sm.startTransaction(0x9000, 0, false, 4);
    try std.testing.expectEqual(@as(u8, 3), sm.current_transaction.?.wait_states);
    
    // UART 접근 (5 wait)
    sm.current_transaction = null;
    sm.startTransaction(0xF010, 0, true, 2);
    try std.testing.expectEqual(@as(u8, 5), sm.current_transaction.?.wait_states);
    
    // 기본 영역 (1 wait)
    sm.current_transaction = null;
    sm.startTransaction(0x2000, 0, false, 4);
    try std.testing.expectEqual(@as(u8, 1), sm.current_transaction.?.wait_states);
}

test "calculateBusCycles helper function" {
    const regions = [_]WaitStateRegion{
        .{ .start = 0x8000, .end_exclusive = 0xC000, .wait_states = 3 },
    };
    
    const config = BusCycleConfig{
        .default_wait_states = 1,
        .region_wait_states = &regions,
    };
    
    // 기본 영역: 4 + 1 = 5
    try std.testing.expectEqual(@as(u32, 5), calculateBusCycles(0x1000, 4, &config));
    
    // ROM 영역: 4 + 3 = 7
    try std.testing.expectEqual(@as(u32, 7), calculateBusCycles(0x9000, 4, &config));
}
