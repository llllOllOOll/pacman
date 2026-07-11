const std = @import("std");

// Although this function looks imperative, it does not perform the build
// directly and instead it mutates the build graph (`b`) that will be then
// executed by an external runner. The functions in `std.Build` implement a DSL
// for defining build steps and express dependencies between them, allowing the
// build runner to parallelize the build automatically (and the cache system to
// know when a step doesn't need to be re-run).
pub fn build(b: *std.Build) void {
    // Add module for consumers to import
    _ = b.addModule("pacman", .{
        .root_source_file = b.path("src/root.zig"),
    });

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // Tests use a vendored, patched copy of the Zig stdlib, only for this
    // test step — it does not affect the "pacman" module registered above,
    // nor how consumer projects (spider, orbitx) build. See
    // vendor/zig-lib-patched/PATCH_NOTES.md for the reason and how to remove
    // this once the fix (ziglang/zig#19878) ships in an official release.
    const test_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .link_libc = true,
    });

    const tests = b.addTest(.{
        .root_module = test_mod,
        .zig_lib_dir = b.path("vendor/zig-lib-patched"),
    });

    const run_tests = b.addRunArtifact(tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
