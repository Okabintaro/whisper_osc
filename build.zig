const std = @import("std");

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const whisper = b.addStaticLibrary("whisper", null);
    whisper.setTarget(target);
    whisper.setBuildMode(mode);
    whisper.linkLibCpp();
    whisper.linkLibC();
    whisper.addCSourceFiles(&.{
        "./deps/whisper.cpp/whisper.cpp",
        "./deps/whisper.cpp/ggml.c",
    }, &.{
        "-Wall",
        "-W",
        "-O3",
        "-mavx",
        "-mavx2",
        "-mfma",
        "-mf16c",
    });

    // Original examples
    // const whisper_example = b.addExecutable("whisper_main", null);
    // whisper_example.setTarget(target);
    // whisper_example.addIncludeDir("./whisper.cpp");
    // whisper_example.addIncludeDir("./whisper.cpp/examples/");
    // whisper_example.addCSourceFile("./whisper.cpp/examples/main/main.cpp", &.{});
    // whisper_example.linkLibCpp();
    // whisper_example.install();
    // whisper_example.linkLibrary(whisper);
    // whisper_example.setBuildMode(mode);

    // const whisper_stream = b.addExecutable("whisper_stream", null);
    // whisper_stream.setTarget(target);
    // whisper_stream.addIncludeDir("./whisper.cpp");
    // whisper_stream.addIncludeDir("./whisper.cpp/examples/");
    // whisper_stream.addCSourceFile("./whisper.cpp/examples/stream/stream.cpp", &.{});
    // whisper_stream.linkLibCpp();
    // whisper_stream.install();
    // whisper_stream.linkLibrary(whisper);
    // whisper_stream.setBuildMode(mode);
    // whisper_stream.linkSystemLibrary("SDL2");

    const tinyosc = b.addStaticLibrary("tinyosc", null);
    tinyosc.setTarget(target);
    tinyosc.setBuildMode(mode);
    tinyosc.addIncludeDir("./deps/tinyosc");
    tinyosc.linkLibCpp();
    tinyosc.linkLibC();
    tinyosc.addCSourceFiles(&.{
        "./deps/tinyosc/tinyosc.c",
    }, &.{
        "-Wall",
        "-W",
    });

    const whisper_osc = b.addExecutable("whisper_osc", null);
    whisper_osc.setTarget(target);
    whisper_osc.setBuildMode(mode);
    whisper_osc.addIncludeDir("./deps/whisper.cpp");
    whisper_osc.addIncludeDir("./deps/whisper.cpp/examples/");
    whisper_osc.addIncludeDir("./deps/tinyosc");
    whisper_osc.addCSourceFile("./cpp/whisper_osc.cpp", &.{});
    whisper_osc.linkLibCpp();
    whisper_osc.install();
    whisper_osc.linkLibrary(whisper);
    whisper_osc.linkLibrary(tinyosc);
    whisper_osc.linkSystemLibrary("SDL2");

    const run_cmd = whisper_osc.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const tinyosc_main = b.addExecutable("tinyosc_main", null);
    tinyosc_main.setTarget(target);
    tinyosc_main.setBuildMode(mode);
    tinyosc_main.addIncludeDir("./deps/tinyosc");
    tinyosc_main.addCSourceFile("./deps/tinyosc/main.c", &.{});
    tinyosc_main.linkLibC();
    tinyosc_main.install();
    tinyosc_main.linkLibrary(tinyosc);

    const run_osc_cmd = tinyosc_main.run();
    run_osc_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_osc_step = b.step("listen_osc", "Run the tinyosc sample");
    run_osc_step.dependOn(&run_osc_cmd.step);
}
