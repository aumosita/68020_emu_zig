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

    const scc_tests = b.addTest(.{
        .root_source_file = b.path("tests/core/scc_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    scc_tests.root_module.addImport("m68020", &lib.root_module);
    const run_scc_tests = b.addRunArtifact(scc_tests);
    test_step.dependOn(&run_scc_tests.step);

    const iwm_tests = b.addTest(.{
        .root_source_file = b.path("tests/core/iwm_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    iwm_tests.root_module.addImport("m68020", &lib.root_module);
    const run_iwm_tests = b.addRunArtifact(iwm_tests);
    test_step.dependOn(&run_iwm_tests.step);

    const rom_boot_test = b.addTest(.{
        .root_source_file = b.path("tests/integration/rom_boot_test.zig"),
        .target = target,
        .optimize = optimize,
    });
    rom_boot_test.root_module.addImport("m68020", &lib.root_module);
    const run_rom_boot_test = b.addRunArtifact(rom_boot_test);
    test_step.dependOn(&run_rom_boot_test.step);
}
