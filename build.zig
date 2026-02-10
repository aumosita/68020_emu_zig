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
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);
    
    // Shift/Rotate test executable
    const shift_test = b.addExecutable(.{
        .name = "m68020-emu-test-shift",
        .root_source_file = b.path("src/test_shift.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(shift_test);
    
    // Bit operations test executable
    const bits_test = b.addExecutable(.{
        .name = "m68020-emu-test-bits",
        .root_source_file = b.path("src/test_bits.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(bits_test);
    
    // Stack operations test executable
    const stack_test = b.addExecutable(.{
        .name = "m68020-emu-test-stack",
        .root_source_file = b.path("src/test_stack.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(stack_test);
    
    // Phase 1 test executable
    const phase1_test = b.addExecutable(.{
        .name = "m68020-emu-test-phase1",
        .root_source_file = b.path("src/test_phase1.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(phase1_test);

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

    // Unit tests
    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
}
