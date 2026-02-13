const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Static library for embedding in other projects
    const lib = b.addStaticLibrary(.{
        .name = "m68020-emu",
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lib);

    // Shared library for dynamic linking (Python ctypes, etc.)
    const shared_lib = b.addSharedLibrary(.{
        .name = "m68020-emu",
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(shared_lib);

    // Standalone executable for testing
    const exe = b.addExecutable(.{
        .name = "m68020-emu-test",
        .root_source_file = b.path("tests/integration/general.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);

    // Shift/Rotate test executable
    const shift_test = b.addExecutable(.{
        .name = "m68020-emu-test-shift",
        .root_source_file = b.path("tests/core/test_shift.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(shift_test);

    // Bit operations test executable
    const bits_test = b.addExecutable(.{
        .name = "m68020-emu-test-bits",
        .root_source_file = b.path("tests/core/test_bits.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(bits_test);

    // Stack operations test executable
    const stack_test = b.addExecutable(.{
        .name = "m68020-emu-test-stack",
        .root_source_file = b.path("tests/core/test_stack.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(stack_test);

    // Phase 1 test executable
    const phase1_test = b.addExecutable(.{
        .name = "m68020-emu-test-phase1",
        .root_source_file = b.path("tests/core/test_phase1.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(phase1_test);

    // Phase 2 test executable
    const phase2_test = b.addExecutable(.{
        .name = "m68020-emu-test-phase2",
        .root_source_file = b.path("tests/core/test_phase2.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(phase2_test);

    // Phase 3 test executable
    const phase3_test = b.addExecutable(.{
        .name = "m68020-emu-test-phase3",
        .root_source_file = b.path("tests/core/test_phase3.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(phase3_test);

    // BCD test executable
    const bcd_test = b.addExecutable(.{
        .name = "m68020-emu-test-bcd",
        .root_source_file = b.path("tests/core/test_bcd.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(bcd_test);

    // 68020 instruction tests
    const test_68020_exe = b.addExecutable(.{
        .name = "m68020-emu-test-68020",
        .root_source_file = b.path("tests/core/test_68020.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(test_68020_exe);

    // Interrupt tests
    const test_interrupts_exe = b.addExecutable(.{
        .name = "m68020-emu-test-interrupts",
        .root_source_file = b.path("tests/core/test_interrupts.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(test_interrupts_exe);

    // Cycle accurate demo
    const cycle_demo = b.addExecutable(.{
        .name = "cycle-accurate-demo",
        .root_source_file = b.path("tests/core/test_cycle_accurate.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(cycle_demo);

    // Run step
    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the test executable");
    run_step.dependOn(&run_cmd.step);

    // Run shift test step
    const run_shift = b.addRunArtifact(shift_test);
    run_shift.step.dependOn(b.getInstallStep());
    const run_shift_step = b.step("test-shift", "Run shift/rotate tests");
    run_shift_step.dependOn(&run_shift.step);

    // Run bits test step
    const run_bits = b.addRunArtifact(bits_test);
    run_bits.step.dependOn(b.getInstallStep());
    const run_bits_step = b.step("test-bits", "Run bit operation tests");
    run_bits_step.dependOn(&run_bits.step);

    // Run stack test step
    const run_stack = b.addRunArtifact(stack_test);
    run_stack.step.dependOn(b.getInstallStep());
    const run_stack_step = b.step("test-stack", "Run stack operation tests");
    run_stack_step.dependOn(&run_stack.step);

    // Run Phase 1 test step
    const run_phase1 = b.addRunArtifact(phase1_test);
    run_phase1.step.dependOn(b.getInstallStep());
    const run_phase1_step = b.step("test-phase1", "Run Phase 1 (JMP/BSR/DBcc/Scc) tests");
    run_phase1_step.dependOn(&run_phase1.step);

    // Run Phase 2 test step
    const run_phase2 = b.addRunArtifact(phase2_test);
    run_phase2.step.dependOn(b.getInstallStep());
    const run_phase2_step = b.step("test-phase2", "Run Phase 2 (RTR/RTE/TRAP/TAS) tests");
    run_phase2_step.dependOn(&run_phase2.step);

    // Run Phase 3 test step
    const run_phase3 = b.addRunArtifact(phase3_test);
    run_phase3.step.dependOn(b.getInstallStep());
    const run_phase3_step = b.step("test-phase3", "Run Phase 3 (EXG/CMPM/CHK) tests");
    run_phase3_step.dependOn(&run_phase3.step);

    // Run BCD test step
    const run_bcd = b.addRunArtifact(bcd_test);
    run_bcd.step.dependOn(b.getInstallStep());
    const run_bcd_step = b.step("test-bcd", "Run BCD (ABCD/SBCD/NBCD) tests");
    run_bcd_step.dependOn(&run_bcd.step);

    // Run 68020 test step
    const run_68020 = b.addRunArtifact(test_68020_exe);
    run_68020.step.dependOn(b.getInstallStep());
    const run_68020_step = b.step("test-68020", "Run 68020 exclusive instruction tests");
    run_68020_step.dependOn(&run_68020.step);

    // Run cycle accurate demo
    const run_cycle_demo = b.addRunArtifact(cycle_demo);
    run_cycle_demo.step.dependOn(b.getInstallStep());
    const run_cycle_demo_step = b.step("demo-cycles", "Run cycle-accurate demo");
    run_cycle_demo_step.dependOn(&run_cycle_demo.step);

    // Example: Fibonacci
    const fibonacci = b.addExecutable(.{
        .name = "fibonacci",
        .root_source_file = b.path("examples/fibonacci.zig"),
        .target = target,
        .optimize = optimize,
    });
    fibonacci.root_module.addImport("cpu", &lib.root_module);
    b.installArtifact(fibonacci);
    const run_fib = b.addRunArtifact(fibonacci);
    run_fib.step.dependOn(b.getInstallStep());
    const run_fib_step = b.step("demo-fib", "Run Fibonacci calculator demo");
    run_fib_step.dependOn(&run_fib.step);

    // Example: Bit Field Operations
    const bitfield_demo = b.addExecutable(.{
        .name = "bitfield-demo",
        .root_source_file = b.path("examples/bitfield_demo.zig"),
        .target = target,
        .optimize = optimize,
    });
    bitfield_demo.root_module.addImport("cpu", &lib.root_module);
    b.installArtifact(bitfield_demo);
    const run_bitfield = b.addRunArtifact(bitfield_demo);
    run_bitfield.step.dependOn(b.getInstallStep());
    const run_bitfield_step = b.step("demo-bitfield", "Run 68020 bit field operations demo");
    run_bitfield_step.dependOn(&run_bitfield.step);

    // Example: Exception Handling
    const exception_demo = b.addExecutable(.{
        .name = "exception-demo",
        .root_source_file = b.path("examples/exception_demo.zig"),
        .target = target,
        .optimize = optimize,
    });
    exception_demo.root_module.addImport("cpu", &lib.root_module);
    b.installArtifact(exception_demo);
    const run_exception = b.addRunArtifact(exception_demo);
    run_exception.step.dependOn(b.getInstallStep());
    const run_exception_step = b.step("demo-exception", "Run 68020 exception handling demo");
    run_exception_step.dependOn(&run_exception.step);

    // Unit tests
    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("tests/integration/general.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe_unit_tests.root_module.addImport("m68020", &lib.root_module);
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const external_vector_tests = b.addTest(.{
        .root_source_file = b.path("src/core/external_vectors.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_external_vector_tests = b.addRunArtifact(external_vector_tests);

    const scheduler_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/core/scheduler.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_scheduler_unit_tests = b.addRunArtifact(scheduler_unit_tests);

    const mac_lc_tests = b.addTest(.{
        .root_source_file = b.path("tests/integration/mac_lc.zig"),
        .target = target,
        .optimize = optimize,
    });
    mac_lc_tests.root_module.addImport("m68020", &lib.root_module);
    const run_mac_lc_tests = b.addRunArtifact(mac_lc_tests);

    const interrupts_tests = b.addTest(.{
        .root_source_file = b.path("tests/integration/interrupts.zig"),
        .target = target,
        .optimize = optimize,
    });
    interrupts_tests.root_module.addImport("m68020", &lib.root_module);
    const run_interrupts_tests = b.addRunArtifact(interrupts_tests);

    const video_timing_tests = b.addTest(.{
        .root_source_file = b.path("tests/integration/video_timing.zig"),
        .target = target,
        .optimize = optimize,
    });
    video_timing_tests.root_module.addImport("m68020", &lib.root_module);
    const run_video_timing_tests = b.addRunArtifact(video_timing_tests);

    const interrupt_propagation_tests = b.addTest(.{
        .root_source_file = b.path("tests/integration/interrupt_propagation.zig"),
        .target = target,
        .optimize = optimize,
    });
    interrupt_propagation_tests.root_module.addImport("m68020", &lib.root_module);
    const run_interrupt_propagation_tests = b.addRunArtifact(interrupt_propagation_tests);

    const scsi_tests = b.addTest(.{
        .root_source_file = b.path("tests/core/scsi_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    scsi_tests.root_module.addImport("m68020", &lib.root_module);
    const run_scsi_tests = b.addRunArtifact(scsi_tests);

    const adb_tests = b.addTest(.{
        .root_source_file = b.path("tests/core/adb_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    adb_tests.root_module.addImport("m68020", &lib.root_module);
    const run_adb_tests = b.addRunArtifact(adb_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
    test_step.dependOn(&run_external_vector_tests.step);
    test_step.dependOn(&run_scheduler_unit_tests.step);
    test_step.dependOn(&run_mac_lc_tests.step);
    test_step.dependOn(&run_interrupts_tests.step);
    test_step.dependOn(&run_video_timing_tests.step);
    test_step.dependOn(&run_interrupt_propagation_tests.step);
    test_step.dependOn(&run_scsi_tests.step);
    test_step.dependOn(&run_adb_tests.step);

    const memory_map_tests = b.addTest(.{
        .root_source_file = b.path("tests/integration/memory_map_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    memory_map_tests.root_module.addImport("m68020", &lib.root_module);
    const run_memory_map_tests = b.addRunArtifact(memory_map_tests);
    test_step.dependOn(&run_memory_map_tests.step);
}
