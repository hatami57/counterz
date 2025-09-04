const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});

    const optimize = b.standardOptimizeOption(.{});
    const lib_mod = b.createModule(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // host version

    const host_exe_mod = b.createModule(.{
        .root_source_file = b.path("src/host.zig"),
        .target = target,
        .optimize = optimize,
    });
    host_exe_mod.addImport("counterz_lib", lib_mod);
    const counterz = b.dependency("zig_webui", .{
        .target = target,
        .optimize = optimize,
        .enable_tls = false, // whether enable tls support
        .is_static = true, // whether static link
    });

    host_exe_mod.addImport("webui", counterz.module("webui"));

    // client version
    const client_exe_mod = b.createModule(.{
        .root_source_file = b.path("src/client.zig"),
        .target = target,
        .optimize = optimize,
    });
    host_exe_mod.addImport("counterz_lib", lib_mod);

    const lib = b.addLibrary(.{
        .linkage = .static,
        .name = "counterz",
        .root_module = lib_mod,
    });

    b.installArtifact(lib);

    const host_exe = b.addExecutable(.{
        .name = "counterz_host",
        .root_module = host_exe_mod,
    });

    const vite_build = b.addSystemCommand(&[_][]const u8{
        "sh",
        "-c",
        "command -v bun >/dev/null 2>&1 && bun vite build || echo 'bun not found, skipping vite build'",
    });
    vite_build.cwd = b.path("src/html/counterz-ui");
    const copy_index_html = b.addSystemCommand(&[_][]const u8{
        "sh",
        "-c",
        "test -f dist/index.html && cp dist/index.html ../index.html || echo 'no index.html to copy'",
    });
    copy_index_html.cwd = b.path("src/html/counterz-ui");
    copy_index_html.step.dependOn(&vite_build.step);

    host_exe.step.dependOn(&copy_index_html.step);

    b.installArtifact(host_exe);

    const client_exe = b.addExecutable(.{
        .name = "counterz_client",
        .root_module = client_exe_mod,
    });

    b.installArtifact(client_exe);

    const run_cmd = b.addRunArtifact(host_exe);

    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const lib_unit_tests = b.addTest(.{
        .root_module = lib_mod,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_module = host_exe_mod,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
}
