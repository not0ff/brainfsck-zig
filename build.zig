const std = @import("std");
const pkg = @import("build.zig.zon");

pub fn build(b: *std.Build) void {
    const optimize = b.standardOptimizeOption(.{
        .preferred_optimize_mode = .Debug,
    });
    const target = b.standardTargetOptions(.{});

    const exe_name = "brainfsck-zig";
    const exe = b.addExecutable(.{
        .name = exe_name,
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            // .strip = true,
            .single_threaded = true,
        }),
    });

    const opts = b.addOptions();
    opts.addOption([]const u8, "exe_name", exe_name);
    exe.root_module.addOptions("build_options", opts);

    b.installArtifact(exe);
    const run_exe = b.addRunArtifact(exe);
    if (b.args) |args| {
        run_exe.addArgs(args);
    }

    const run_step = b.step("run", "Run the applicator");
    run_step.dependOn(&run_exe.step);
}
