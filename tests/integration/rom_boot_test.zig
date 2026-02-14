const std = @import("std");
const m68020 = @import("m68020");
const M68k = m68020.M68k;
const Memory = m68020.Memory;
const MacLcSystem = m68020.MacLcSystem;

// ROM Boot Test Harness
// Loads Mac LC ROM and attempts to execute the first N instructions.
// Reports: PC, SR, registers, and any errors encountered.
//
// This test requires a ROM file at rom_and_bin/Mac_LC.ROM.
// If the ROM is not found, the test is skipped (not failed).

test "Mac LC ROM boot smoke test" {
    const allocator = std.testing.allocator;

    // Create Mac LC system with ROM
    const sys = MacLcSystem.init(allocator, 4 * 1024 * 1024, "rom_and_bin/Mac_LC.ROM") catch |err| {
        std.debug.print("  [SKIP] Cannot create MacLcSystem: {}\n", .{err});
        return;
    };
    defer sys.deinit(allocator);

    // Verify ROM was loaded (not dummy)
    if (sys.rom_size <= 4) {
        std.debug.print("  [SKIP] ROM not found at rom_and_bin/Mac_LC.ROM\n", .{});
        return;
    }
    std.debug.print("\n=== Mac LC ROM Boot Test ===\n", .{});
    std.debug.print("  ROM size: {} bytes ({} KB)\n", .{ sys.rom_size, sys.rom_size / 1024 });

    // Verify ROM header (reset vectors)
    const ssp_vec = readRom32(sys, 0);
    const pc_vec = readRom32(sys, 4);
    std.debug.print("  ROM SSP vector: 0x{X:0>8}\n", .{ssp_vec});
    std.debug.print("  ROM PC vector:  0x{X:0>8}\n", .{pc_vec});

    // Create CPU
    var cpu = M68k.init(allocator);
    defer cpu.deinit();

    // Install Mac LC MMIO hooks
    cpu.memory.setBusHook(MacLcSystem.busHook, sys);
    cpu.memory.setAddressTranslator(MacLcSystem.addressTranslator, sys);
    cpu.memory.setMmio(MacLcSystem.mmioRead, MacLcSystem.mmioWrite, sys);
    MacLcSystem.configureBusCycles(&cpu.memory);

    // Reset CPU (loads SSP and PC from ROM overlay)
    std.debug.print("\n--- CPU Reset ---\n", .{});
    sys.resetOverlay();
    cpu.reset();
    std.debug.print("  Post-reset A7 (SSP): 0x{X:0>8}\n", .{cpu.a[7]});
    std.debug.print("  Post-reset PC:       0x{X:0>8}\n", .{cpu.pc});
    std.debug.print("  Post-reset SR:       0x{X:0>4}\n", .{cpu.sr});

    // Verify reset loaded correct vectors from ROM
    try std.testing.expectEqual(ssp_vec, cpu.a[7]);
    try std.testing.expectEqual(pc_vec, cpu.pc);

    // Execute first N steps
    const MAX_STEPS: u32 = 200;
    std.debug.print("\n--- Executing up to {} steps ---\n", .{MAX_STEPS});

    var last_pc: u32 = cpu.pc;
    var total_cycles: u64 = 0;
    var steps_executed: u32 = 0;
    var error_msg: ?[]const u8 = null;
    var stuck_count: u32 = 0;

    var step: u32 = 0;
    while (step < MAX_STEPS) : (step += 1) {
        const prev_pc = cpu.pc;

        // Log first 20 steps and every 50th step
        const should_log = step < 20 or (step % 50 == 0);

        if (should_log) {
            // Read opcode at current PC for logging
            const opcode = cpu.memory.read16Bus(cpu.pc, .{
                .function_code = 0b110,
                .space = .Program,
                .is_write = false,
            }) catch 0xFFFF;
            std.debug.print("  [{:>3}] PC=0x{X:0>8} opcode=0x{X:0>4} SR=0x{X:0>4}", .{ step, cpu.pc, opcode, cpu.sr });
        }

        const cycles = cpu.step() catch |err| {
            std.debug.print("\n  *** CPU ERROR at step {}: {} ***\n", .{ step, err });
            std.debug.print("      PC=0x{X:0>8} SR=0x{X:0>4}\n", .{ cpu.pc, cpu.sr });
            error_msg = @errorName(err);
            break;
        };

        total_cycles += cycles;
        steps_executed += 1;

        // Sync system (timers, VBL, etc.)
        sys.sync(@intCast(cycles));

        // Check for pending interrupts
        const irq = sys.getIrqLevel();
        if (irq > 0) {
            cpu.setInterruptLevel(@truncate(irq));
        }

        if (should_log) {
            std.debug.print(" -> PC=0x{X:0>8} ({} cyc)\n", .{ cpu.pc, cycles });
        }

        // Detect infinite loop (PC not advancing)
        if (cpu.pc == prev_pc) {
            stuck_count += 1;
            if (stuck_count > 10) {
                std.debug.print("  *** STUCK: PC=0x{X:0>8} not advancing for {} steps ***\n", .{ cpu.pc, stuck_count });
                break;
            }
        } else {
            stuck_count = 0;
        }

        last_pc = cpu.pc;
    }

    // Final state dump
    std.debug.print("\n--- Final State ---\n", .{});
    std.debug.print("  Steps executed: {}\n", .{steps_executed});
    std.debug.print("  Total cycles:   {}\n", .{total_cycles});
    std.debug.print("  Final PC:       0x{X:0>8}\n", .{cpu.pc});
    std.debug.print("  Final SR:       0x{X:0>4}\n", .{cpu.sr});
    std.debug.print("  Final A7 (SP):  0x{X:0>8}\n", .{cpu.a[7]});
    if (error_msg) |msg| {
        std.debug.print("  Error:          {s}\n", .{msg});
    }

    // Register dump
    std.debug.print("  D: ", .{});
    for (cpu.d) |d| std.debug.print("{X:0>8} ", .{d});
    std.debug.print("\n  A: ", .{});
    for (cpu.a) |a| std.debug.print("{X:0>8} ", .{a});
    std.debug.print("\n", .{});

    // Overlay status
    std.debug.print("  ROM overlay:    {}\n", .{sys.isOverlayActive()});
    std.debug.print("  Address mode:   {}-bit\n", .{if (sys.address_mode_32) @as(u32, 32) else 24});

    // The test passes if we executed at least 1 step without crashing
    try std.testing.expect(steps_executed > 0);
    std.debug.print("\n=== Boot test complete ({} steps, {} cycles) ===\n", .{ steps_executed, total_cycles });
}

fn readRom32(sys: *MacLcSystem, offset: u32) u32 {
    if (offset + 3 >= sys.rom_size) return 0;
    const b0: u32 = sys.rom[offset];
    const b1: u32 = sys.rom[offset + 1];
    const b2: u32 = sys.rom[offset + 2];
    const b3: u32 = sys.rom[offset + 3];
    return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3;
}
