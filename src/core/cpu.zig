const std = @import("std");
const memory = @import("memory.zig");
const decoder = @import("decoder.zig");
const executor = @import("executor.zig");
const registers = @import("registers.zig");
const exception = @import("exception.zig");
const interrupt = @import("interrupt.zig");

pub const M68k = struct {
    const ICacheSets = 32;
    const ICacheWays = 2;
    const ICacheLine = struct { valid: bool, tag: u32, data: u32, lru: bool };
    pub const ICacheStats = struct { hits: u64, misses: u64 };
    pub const PipelineMode = enum(u8) { off = 0, approx = 1, detailed = 2 };
    pub const CoprocessorResult = union(enum) {
        handled: u32,
        unavailable: void,
        fault: u32, // fault address
    };
    pub const BkptResult = union(enum) {
        handled: u32,
        illegal: void,
    };
    pub const CoprocessorHandler = *const fn (ctx: ?*anyopaque, m68k: *M68k, opcode: u16, pc: u32) CoprocessorResult;
    pub const BkptHandler = *const fn (ctx: ?*anyopaque, m68k: *M68k, vector: u3, pc: u32) BkptResult;

    pub const FLAG_C = registers.FLAG_C;
    pub const FLAG_V = registers.FLAG_V;
    pub const FLAG_Z = registers.FLAG_Z;
    pub const FLAG_N = registers.FLAG_N;
    pub const FLAG_X = registers.FLAG_X;
    pub const FLAG_M = registers.FLAG_M;
    pub const FLAG_S = registers.FLAG_S;
    pub const StackKind = registers.StackKind;

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
    pmmu_compat_enabled: bool,
    pmmu_mmusr: u32,
    pending_irq_level: u3,
    pending_irq_vector: ?u8,
    stopped: bool,
    coprocessor_handler: ?CoprocessorHandler,
    coprocessor_ctx: ?*anyopaque,
    bkpt_handler: ?BkptHandler,
    bkpt_ctx: ?*anyopaque,
    icache: [ICacheSets][ICacheWays]ICacheLine,
    memory: memory.Memory,
    decoder: decoder.Decoder,
    executor: executor.Executor,
    cycles: u64,
    last_data_access_addr: u32,
    last_data_access_is_write: bool,
    split_bus_cycle_penalty_enabled: bool,
    icache_fetch_miss_penalty: u32,
    icache_hit_count: u64,
    icache_miss_count: u64,
    bus_retry_limit: u8,
    bus_retry_count: u8,
    profiler_enabled: bool = false,
    profiler_data: ?*CycleProfilerData = null,
    pipeline_mode: PipelineMode,
    allocator: std.mem.Allocator,

    pub const CycleProfilerData = struct {
        instruction_counts: [256]u64 = [_]u64{0} ** 256,
        instruction_cycles: [256]u64 = [_]u64{0} ** 256,
        total_steps: u64 = 0,
        total_cycles: u64 = 0,
    };

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
            .pmmu_compat_enabled = false,
            .pmmu_mmusr = 0,
            .pending_irq_level = 0,
            .pending_irq_vector = null,
            .stopped = false,
            .coprocessor_handler = null,
            .coprocessor_ctx = null,
            .bkpt_handler = null,
            .bkpt_ctx = null,
            .icache = [_][ICacheWays]ICacheLine{[_]ICacheLine{.{ .valid = false, .tag = 0, .data = 0, .lru = false }} ** ICacheWays} ** ICacheSets,
            .memory = memory.Memory.initWithConfig(allocator, config),
            .decoder = decoder.Decoder.init(),
            .executor = executor.Executor.init(),
            .cycles = 0,
            .last_data_access_addr = 0,
            .last_data_access_is_write = false,
            .split_bus_cycle_penalty_enabled = false,
            .icache_fetch_miss_penalty = 2,
            .icache_hit_count = 0,
            .icache_miss_count = 0,
            .bus_retry_limit = 3,
            .bus_retry_count = 0,
            .profiler_enabled = false,
            .profiler_data = null,
            .pipeline_mode = .off,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *M68k) void {
        if (self.profiler_data) |data| {
            self.allocator.destroy(data);
        }
        self.memory.deinit();
    }

    pub fn reset(self: *M68k) void {
        for (&self.d) |*reg| reg.* = 0;
        for (&self.a) |*reg| reg.* = 0;
        self.sr = 0x2700;
        // Use bus path (MMIO/overlay-aware) for reset vectors
        const supervisor_data = memory.BusAccess{
            .function_code = 0b101, // Supervisor data
            .space = .Data,
            .is_write = false,
        };
        self.a[7] = self.memory.read32Bus(self.getExceptionVector(0), supervisor_data) catch 0;
        self.pc = self.memory.read32Bus(self.getExceptionVector(1), supervisor_data) catch 0;
        self.isp = self.a[7];
        self.msp = self.a[7];
        self.usp = 0;
        self.pending_irq_level = 0;
        self.pending_irq_vector = null;
        self.stopped = false;
        self.pmmu_mmusr = 0;
        self.cacr = 0;
        self.caar = 0;
        self.invalidateICache();
        self.cycles = 0;
        self.last_data_access_addr = 0;
        self.last_data_access_is_write = false;
        self.icache_hit_count = 0;
        self.icache_miss_count = 0;
        self.bus_retry_count = 0;
        _ = self.memory.takeSplitCyclePenalty();
    }

    pub fn getExceptionVector(self: *const M68k, vector_number: u8) u32 {
        return exception.getExceptionVector(self, vector_number);
    }

    pub fn readWord(self: *const M68k, addr: u32) u16 {
        return self.memory.read16(addr) catch 0;
    }

    pub fn step(self: *M68k) !u32 {
        _ = self.memory.takeSplitCyclePenalty();
        if (try self.handlePendingInterrupt()) {
            self.bus_retry_count = 0;
            return self.finalizeStepCycles(44);
        }
        if (self.stopped) {
            self.bus_retry_count = 0;
            return self.finalizeStepCycles(4);
        }
        const fetch = self.fetchInstructionWord(self.pc) catch |err| switch (err) {
            error.BusRetry => {
                if (self.bus_retry_count < self.bus_retry_limit) {
                    self.bus_retry_count += 1;
                    return self.finalizeStepCycles(4);
                }
                try self.enterBusErrorFrameA(self.pc, self.pc, .{
                    .function_code = self.getProgramFunctionCode(),
                    .space = .Program,
                    .is_write = false,
                });
                self.bus_retry_count = 0;
                return self.finalizeStepCycles(exception.faultCycles(.instruction_fetch));
            },
            error.BusHalt => {
                self.bus_retry_count = 0;
                self.stopped = true;
                return self.finalizeStepCycles(4);
            },
            error.BusError => {
                self.bus_retry_count = 0;
                try self.enterBusErrorFrameA(self.pc, self.pc, .{
                    .function_code = self.getProgramFunctionCode(),
                    .space = .Program,
                    .is_write = false,
                });
                const cycles = exception.faultCycles(.instruction_fetch);
                return self.finalizeStepCycles(cycles);
            },
            error.AddressError => {
                self.bus_retry_count = 0;
                try self.enterAddressErrorFrameA(self.pc, self.pc, .{
                    .function_code = self.getProgramFunctionCode(),
                    .space = .Program,
                    .is_write = false,
                });
                const cycles = exception.faultCycles(.instruction_fetch);
                return self.finalizeStepCycles(cycles);
            },
            else => return err,
        };
        const opcode = fetch.opcode;
        // Hot-path optimization: NOP has no side effects beyond PC/cycle update.
        if (opcode == 0x4E71) {
            self.pc += 2;
            self.bus_retry_count = 0;
            const cycles = 4 + fetch.penalty_cycles;
            self.recordProfiler(opcode, cycles);
            return self.finalizeStepCycles(cycles);
        }
        // Hot-path optimization: ADDQ/SUBQ long to data register direct.
        if ((opcode & 0xF000) == 0x5000 and ((opcode >> 6) & 0x3) == 0x2 and ((opcode >> 3) & 0x7) == 0x0) {
            const reg: u3 = @truncate(opcode & 0x7);
            const imm3: u3 = @truncate((opcode >> 9) & 0x7);
            const imm: u32 = if (imm3 == 0) 8 else imm3;
            const is_sub = ((opcode >> 8) & 1) != 0;
            const d = self.d[reg];
            const r = if (is_sub) d -% imm else d +% imm;
            self.d[reg] = r;
            self.applyAddSubFlagsLong(d, imm, r, is_sub);
            self.pc += 2;
            self.bus_retry_count = 0;
            const cycles = 4 + fetch.penalty_cycles;
            self.recordProfiler(opcode, cycles);
            return self.finalizeStepCycles(cycles);
        }
        // Hot-path optimization: BRA.S with 8-bit displacement (excluding ext forms).
        if ((opcode & 0xFF00) == 0x6000 and (opcode & 0x00FF) != 0 and (opcode & 0x00FF) != 0x00FF) {
            const disp8: i8 = @bitCast(@as(u8, @truncate(opcode)));
            self.pc = @bitCast(@as(i32, @bitCast(self.pc)) + 2 + @as(i32, disp8));
            self.bus_retry_count = 0;
            const base_cycles: u32 = 10 + self.pipelineBranchFlushPenalty();
            const cycles = base_cycles + fetch.penalty_cycles;
            self.recordProfiler(opcode, cycles);
            return self.finalizeStepCycles(cycles);
        }
        // Hot-path optimization: common RTE format-0 frame unwind in supervisor mode.
        if (opcode == 0x4E73) {
            if (!self.getFlag(FLAG_S)) {
                try self.enterException(8, self.pc, 0, null);
                const cycles = 34 + fetch.penalty_cycles;
                self.recordProfiler(opcode, cycles);
                return self.finalizeStepCycles(cycles);
            }
            const sp = self.a[7];
            if (sp + 7 < self.memory.size and (!self.memory.enforce_alignment or (sp & 1) == 0)) {
                const frame_word_addr = sp + 6;
                const fv_hi: u16 = self.memory.data[frame_word_addr];
                const fv_lo: u16 = self.memory.data[frame_word_addr + 1];
                const format_vector = (fv_hi << 8) | fv_lo;
                const format: u4 = @truncate(format_vector >> 12);
                if (format == 0) {
                    const sr_hi: u16 = self.memory.data[sp];
                    const sr_lo: u16 = self.memory.data[sp + 1];
                    const restored_sr: u16 = (sr_hi << 8) | sr_lo;

                    const b0: u32 = self.memory.data[sp + 2];
                    const b1: u32 = self.memory.data[sp + 3];
                    const b2: u32 = self.memory.data[sp + 4];
                    const b3: u32 = self.memory.data[sp + 5];
                    const restored_pc: u32 = (b0 << 24) | (b1 << 16) | (b2 << 8) | b3;

                    self.a[7] = sp + 8;
                    self.setSR(restored_sr);
                    self.pc = restored_pc;
                    const cycles = 20 + fetch.penalty_cycles;
                    self.recordProfiler(opcode, cycles);
                    return self.finalizeStepCycles(cycles);
                }
            }
        }
        M68k.current_instance = self;
        M68k.decode_fault_addr = null;
        M68k.decode_fault_kind = .Bus;
        defer M68k.current_instance = null;
        const instruction = self.decoder.decode(opcode, self.pc, &M68k.globalReadWord) catch |err| switch (err) {
            error.IllegalInstruction => {
                try self.enterException(4, self.pc, 0, null);
                return self.finalizeStepCycles(34 + fetch.penalty_cycles);
            },
            else => return err,
        };
        if (M68k.decode_fault_addr) |fault_addr| {
            if (M68k.decode_fault_kind == .Address) {
                try self.enterAddressErrorFrameA(self.pc, fault_addr, .{
                    .function_code = self.getProgramFunctionCode(),
                    .space = .Program,
                    .is_write = false,
                });
            } else {
                try self.enterBusErrorFrameA(self.pc, fault_addr, .{
                    .function_code = self.getProgramFunctionCode(),
                    .space = .Program,
                    .is_write = false,
                });
            }
            self.bus_retry_count = 0;
            const cycles = exception.faultCycles(.decode_extension_fetch) + fetch.penalty_cycles;
            return self.finalizeStepCycles(cycles);
        }
        self.last_data_access_addr = self.pc;
        self.last_data_access_is_write = false;
        const cycles_used = self.executor.execute(self, &instruction) catch |err| switch (err) {
            error.BusRetry => {
                if (self.bus_retry_count < self.bus_retry_limit) {
                    self.bus_retry_count += 1;
                    return self.finalizeStepCycles(4 + fetch.penalty_cycles);
                }
                try self.enterBusErrorFrameA(self.pc, self.last_data_access_addr, .{
                    .function_code = self.dfc,
                    .space = .Data,
                    .is_write = self.last_data_access_is_write,
                });
                self.bus_retry_count = 0;
                return self.finalizeStepCycles(exception.faultCycles(.execute_data_access) + fetch.penalty_cycles);
            },
            error.BusHalt => {
                self.bus_retry_count = 0;
                self.stopped = true;
                return self.finalizeStepCycles(4 + fetch.penalty_cycles);
            },
            error.BusError => {
                self.bus_retry_count = 0;
                try self.enterBusErrorFrameA(self.pc, self.last_data_access_addr, .{
                    .function_code = self.dfc,
                    .space = .Data,
                    .is_write = self.last_data_access_is_write,
                });
                const cycles = exception.faultCycles(.execute_data_access) + fetch.penalty_cycles;
                return self.finalizeStepCycles(cycles);
            },
            error.InvalidAddress => {
                self.bus_retry_count = 0;
                try self.enterBusErrorFrameA(self.pc, self.last_data_access_addr, .{
                    .function_code = self.dfc,
                    .space = .Data,
                    .is_write = self.last_data_access_is_write,
                });
                const cycles = exception.faultCycles(.execute_data_access) + fetch.penalty_cycles;
                return self.finalizeStepCycles(cycles);
            },
            error.AddressError => {
                self.bus_retry_count = 0;
                try self.enterAddressErrorFrameA(self.pc, self.last_data_access_addr, .{
                    .function_code = self.dfc,
                    .space = .Data,
                    .is_write = self.last_data_access_is_write,
                });
                const cycles = exception.faultCycles(.execute_data_access) + fetch.penalty_cycles;
                return self.finalizeStepCycles(cycles);
            },
            error.InvalidOperand, error.InvalidExtensionWord, error.InvalidControlRegister, error.Err => {
                self.bus_retry_count = 0;
                try self.enterException(4, self.pc, 0, null);
                return self.finalizeStepCycles(34 + fetch.penalty_cycles);
            },
            else => return err,
        };
        self.bus_retry_count = 0;
        const final_cycles = cycles_used + fetch.penalty_cycles;
        if (self.profiler_enabled) {
            if (self.profiler_data) |data| {
                const group: u8 = @truncate(opcode >> 8);
                data.instruction_counts[group] += 1;
                data.instruction_cycles[group] += final_cycles;
                data.total_steps += 1;
                data.total_cycles += final_cycles;
            }
        }
        return self.finalizeStepCycles(final_cycles);
    }

    threadlocal var current_instance: ?*const M68k = null;
    const DecodeFaultKind = enum { Bus, Address };
    threadlocal var decode_fault_addr: ?u32 = null;
    threadlocal var decode_fault_kind: DecodeFaultKind = .Bus;

    fn globalReadWord(addr: u32) u16 {
        if (M68k.current_instance) |inst| {
            const access = memory.BusAccess{
                .function_code = inst.getProgramFunctionCode(),
                .space = .Program,
                .is_write = false,
            };
            return inst.memory.read16Bus(addr, access) catch |err| {
                M68k.decode_fault_addr = addr;
                M68k.decode_fault_kind = switch (err) {
                    error.AddressError => .Address,
                    else => .Bus,
                };
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

    pub fn noteDataAccess(self: *M68k, addr: u32, is_write: bool) void {
        self.last_data_access_addr = addr;
        self.last_data_access_is_write = is_write;
    }

    pub inline fn getFlag(self: *const M68k, comptime flag: u16) bool {
        return registers.getFlag(self, flag);
    }

    pub inline fn setFlag(self: *M68k, comptime flag: u16, value: bool) void {
        registers.setFlag(self, flag, value);
    }

    pub inline fn setFlags(self: *M68k, result: u32, size: decoder.DataSize) void {
        registers.setFlags(self, result, size);
    }

    pub fn setSR(self: *M68k, new_sr: u16) void {
        registers.setSR(self, new_sr);
    }

    pub fn setInterruptLevel(self: *M68k, level: u3) void {
        interrupt.setInterruptLevel(self, level);
    }

    pub fn setCoprocessorHandler(self: *M68k, handler: ?CoprocessorHandler, ctx: ?*anyopaque) void {
        self.coprocessor_handler = handler;
        self.coprocessor_ctx = ctx;
    }

    pub fn setBkptHandler(self: *M68k, handler: ?BkptHandler, ctx: ?*anyopaque) void {
        self.bkpt_handler = handler;
        self.bkpt_ctx = ctx;
    }

    pub fn setPmmuCompatEnabled(self: *M68k, enabled: bool) void {
        self.pmmu_compat_enabled = enabled;
    }

    pub fn setSplitBusCyclePenaltyEnabled(self: *M68k, enabled: bool) void {
        self.split_bus_cycle_penalty_enabled = enabled;
    }

    pub fn setICacheFetchMissPenalty(self: *M68k, penalty_cycles: u32) void {
        self.icache_fetch_miss_penalty = penalty_cycles;
    }

    pub fn getICacheFetchMissPenalty(self: *const M68k) u32 {
        return self.icache_fetch_miss_penalty;
    }

    pub fn clearICacheStats(self: *M68k) void {
        self.icache_hit_count = 0;
        self.icache_miss_count = 0;
    }

    pub fn getICacheStats(self: *const M68k) ICacheStats {
        return .{ .hits = self.icache_hit_count, .misses = self.icache_miss_count };
    }

    pub fn setPipelineMode(self: *M68k, mode: PipelineMode) void {
        self.pipeline_mode = mode;
    }

    pub fn getPipelineMode(self: *const M68k) PipelineMode {
        return self.pipeline_mode;
    }

    pub fn setBusRetryLimit(self: *M68k, limit: u8) void {
        self.bus_retry_limit = limit;
    }

    pub fn getBusRetryCount(self: *const M68k) u8 {
        return self.bus_retry_count;
    }

    pub fn enableProfiler(self: *M68k) !void {
        if (self.profiler_data == null) {
            self.profiler_data = try self.allocator.create(CycleProfilerData);
            self.profiler_data.?.* = .{};
        }
        self.profiler_enabled = true;
    }

    pub fn disableProfiler(self: *M68k) void {
        self.profiler_enabled = false;
    }

    pub fn resetProfiler(self: *M68k) void {
        if (self.profiler_data) |data| {
            data.* = .{};
        }
    }

    pub fn getProfilerData(self: *const M68k) ?*const CycleProfilerData {
        return self.profiler_data;
    }

    pub fn printProfilerReport(self: *const M68k) void {
        const data = self.profiler_data orelse return;
        if (data.total_steps == 0) return;

        std.debug.print("\n--- 68020 Cycle Profiler Report ---\n", .{});
        std.debug.print("Total Instructions: {}\n", .{data.total_steps});
        std.debug.print("Total Cycles:       {}\n", .{data.total_cycles});
        std.debug.print("Avg Cycles/Inst:    {d:.2}\n", .{@as(f64, @floatFromInt(data.total_cycles)) / @as(f64, @floatFromInt(data.total_steps))});
        std.debug.print("\nTop 10 Instruction Groups by Cycle Usage:\n", .{});

        const Entry = struct { group: u8, cycles: u64, count: u64 };
        var entries: [256]Entry = undefined;
        for (0..256) |i| {
            entries[i] = .{ .group = @truncate(i), .cycles = data.instruction_cycles[i], .count = data.instruction_counts[i] };
        }

        // Sort by cycles descending
        std.mem.sort(Entry, &entries, {}, struct {
            fn lessThan(_: void, a: Entry, b: Entry) bool {
                return a.cycles > b.cycles;
            }
        }.lessThan);

        var shown: usize = 0;
        for (entries) |e| {
            if (e.cycles == 0 or shown >= 10) break;
            const percentage = (@as(f64, @floatFromInt(e.cycles)) / @as(f64, @floatFromInt(data.total_cycles))) * 100.0;
            std.debug.print("{:2}. Group 0x{X:02}: {:10} cycles ({:6.2}%) - Executed {:8} times\n", .{ shown + 1, e.group, e.cycles, percentage, e.count });
            shown += 1;
        }
        std.debug.print("-----------------------------------\n", .{});
    }

    fn recordProfiler(self: *M68k, opcode: u16, cycles: u32) void {
        if (self.profiler_enabled) {
            if (self.profiler_data) |data| {
                const group: u8 = @truncate(opcode >> 8);
                data.instruction_counts[group] += 1;
                data.instruction_cycles[group] += cycles;
                data.total_steps += 1;
                data.total_cycles += cycles;
            }
        }
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
        for (&self.icache) |*set| {
            for (set) |*line| {
                line.* = .{ .valid = false, .tag = 0, .data = 0, .lru = false };
            }
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
        const long_addr = addr >> 2;
        const set_index: usize = @intCast(long_addr & (ICacheSets - 1));
        const tag = long_addr >> std.math.log2_int(u32, ICacheSets);
        const use_low_word = (addr & 0x2) != 0;

        // Way lookup
        for (0..ICacheWays) |way| {
            var line = &self.icache[set_index][way];
            if (line.valid and line.tag == tag) {
                self.icache_hit_count += 1;
                line.lru = true; // Mark as recently used
                // Flip other way's LRU if it was true
                const other_way = 1 - way;
                self.icache[set_index][other_way].lru = false;

                const opcode: u16 = if (use_low_word)
                    @truncate(line.data & 0xFFFF)
                else
                    @truncate(line.data >> 16);
                return .{ .opcode = opcode, .penalty_cycles = 0 };
            }
        }

        self.icache_miss_count += 1;
        const aligned_addr = addr & ~@as(u32, 0x3);
        const fetched = try self.memory.read32Bus(aligned_addr, access);

        // Replacement policy: find invalid way or use LRU
        var target_way: usize = 0;
        if (self.icache[set_index][0].valid and !self.icache[set_index][0].lru) {
            target_way = 0;
        } else if (self.icache[set_index][1].valid and !self.icache[set_index][1].lru) {
            target_way = 1;
        } else if (!self.icache[set_index][0].valid) {
            target_way = 0;
        } else if (!self.icache[set_index][1].valid) {
            target_way = 1;
        } else {
            // Both valid, use the one with lru=false
            target_way = if (self.icache[set_index][0].lru) @as(usize, 1) else @as(usize, 0);
        }

        self.icache[set_index][target_way] = .{ .valid = true, .tag = tag, .data = fetched, .lru = true };
        self.icache[set_index][1 - target_way].lru = false;

        const opcode: u16 = if (use_low_word)
            @truncate(fetched & 0xFFFF)
        else
            @truncate(fetched >> 16);
        return .{ .opcode = opcode, .penalty_cycles = self.icache_fetch_miss_penalty };
    }

    fn finalizeStepCycles(self: *M68k, base_cycles: u32) u32 {
        const split_penalty = self.memory.takeSplitCyclePenalty();
        const total = base_cycles + if (self.split_bus_cycle_penalty_enabled) split_penalty else 0;
        self.cycles += total;
        return total;
    }

    fn pipelineBranchFlushPenalty(self: *const M68k) u32 {
        return switch (self.pipeline_mode) {
            .off => 0,
            .approx => 2,
            .detailed => 4,
        };
    }

    fn applyAddSubFlagsLong(self: *M68k, d: u32, s: u32, r: u32, is_sub: bool) void {
        const sign: u32 = 0x80000000;
        self.setFlag(FLAG_Z, r == 0);
        self.setFlag(FLAG_N, (r & sign) != 0);
        if (is_sub) {
            const borrow = s > d;
            const overflow = (((d ^ s) & (d ^ r)) & sign) != 0;
            self.setFlag(FLAG_C, borrow);
            self.setFlag(FLAG_X, borrow);
            self.setFlag(FLAG_V, overflow);
        } else {
            const carry = (@as(u64, d) + @as(u64, s)) > 0xFFFF_FFFF;
            const overflow = ((~(d ^ s) & (d ^ r)) & sign) != 0;
            self.setFlag(FLAG_C, carry);
            self.setFlag(FLAG_X, carry);
            self.setFlag(FLAG_V, overflow);
        }
    }

    pub fn enterBusErrorFrameA(self: *M68k, return_pc: u32, fault_addr: u32, access: memory.BusAccess) !void {
        try exception.enterBusErrorFrameA(self, return_pc, fault_addr, access);
    }

    pub fn enterAddressErrorFrameA(self: *M68k, return_pc: u32, fault_addr: u32, access: memory.BusAccess) !void {
        try exception.enterAddressErrorFrameA(self, return_pc, fault_addr, access);
    }

    pub fn raiseBusError(self: *M68k, fault_addr: u32, access: memory.BusAccess) !void {
        try exception.enterBusErrorFrameA(self, self.pc, fault_addr, access);
    }

    pub fn setInterruptVector(self: *M68k, level: u3, vector: u8) void {
        interrupt.setInterruptVector(self, level, vector);
    }

    pub fn setSpuriousInterrupt(self: *M68k, level: u3) void {
        interrupt.setSpuriousInterrupt(self, level);
    }

    pub fn getStackPointer(self: *const M68k, kind: StackKind) u32 {
        return registers.getStackPointer(self, kind);
    }

    pub fn getStackRegister(self: *const M68k, kind: StackKind) u32 {
        return switch (kind) {
            .User => self.usp,
            .Interrupt => self.isp,
            .Master => self.msp,
        };
    }

    pub fn setStackPointer(self: *M68k, kind: StackKind, value: u32) void {
        registers.setStackPointer(self, kind, value);
    }

    pub fn setStackRegister(self: *M68k, kind: StackKind, value: u32) void {
        switch (kind) {
            .User => self.usp = value,
            .Interrupt => self.isp = value,
            .Master => self.msp = value,
        }
    }

    pub fn pushExceptionFrame(self: *M68k, status_word: u16, return_pc: u32, vector: u8, format: u4) !void {
        try exception.pushExceptionFrame(self, status_word, return_pc, vector, format);
    }

    pub fn enterException(self: *M68k, vector: u8, return_pc: u32, format: u4, new_ipl: ?u3) !void {
        try exception.enterException(self, vector, return_pc, format, new_ipl);
    }

    fn handlePendingInterrupt(self: *M68k) !bool {
        return interrupt.handlePendingInterrupt(self);
    }
};

test {
    _ = @import("cpu_test.zig");
}
