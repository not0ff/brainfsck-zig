const std = @import("std");
const pkg = @import("build.zig.zon");

pub fn build(b: *std.Build) void {
    const exe_name: []const u8 = @tagName(pkg.name);
    const exe = b.addExecutable(.{ .name = exe_name, .root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = b.standardTargetOptions(.{}),
        .optimize = b.standardOptimizeOption(.{}),
    }) });

    const opts = b.addOptions();
    opts.addOption([]const u8, "exe_name", exe_name);
    exe.root_module.addOptions("build_options", opts);

    b.installArtifact(exe);
    const run_exe = b.addRunArtifact(exe);
    if (b.args) |args| {
        run_exe.addArgs(args);
    }

    const run_step = b.step("run", "Run the interpreter");
    run_step.dependOn(&run_exe.step);
}
