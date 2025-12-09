const std = @import("std");

const AddDayOptions = struct {
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    common: *std.Build.Module,
    tests: *std.Build.Step,
    strip: bool,
};

fn add_day(b: *std.Build, day: u4, opt: AddDayOptions) void {
    const day_str = b.fmt("day{d:0>2}", .{day});
    const src_path = b.fmt("src/{s}.zig", .{day_str});

    // Check if source file exists (skip if not yet created)
    const src_file = b.path(src_path);

    const exe = b.addExecutable(.{
        .name = day_str,
        .root_module = b.createModule(.{
            .root_source_file = src_file,
            .target = opt.target,
            .optimize = opt.optimize,
            .strip = opt.strip,
            .imports = &.{
                .{ .name = "common", .module = opt.common },
            },
        }),
    });

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step(day_str, b.fmt("Run {s}", .{day_str}));
    run_step.dependOn(&run_cmd.step);

    const day_tests = b.addTest(.{ .root_module = exe.root_module });
    const run_day_tests = b.addRunArtifact(day_tests);
    opt.tests.dependOn(&run_day_tests.step);
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const strip = b.option(bool, "strip", "Strip debug symbols (default = true)") orelse true;

    const common = b.addModule("common", .{
        .root_source_file = b.path("src/common.zig"),
        .target = target,
    });

    const common_tests = b.addTest(.{
        .root_module = common,
    });
    const run_common_tests = b.addRunArtifact(common_tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_common_tests.step);

    const options = AddDayOptions{
        .target = target,
        .optimize = optimize,
        .common = common,
        .tests = test_step,
        .strip = strip,
    };

    const DAYS = 8;
    for (1..DAYS + 1) |day| {
        add_day(b, @intCast(day), options);
    }
}
