const std = @import("std");

fn linkSDL(step: *std.build.LibExeObjStep) void {
    if (step.target.isWindows()) {
        step.addLibPath("deps/SDL2-2.26.0/x86_64-w64-mingw32/lib/");
        step.addIncludeDir("deps/SDL2-2.26.0/x86_64-w64-mingw32/include/SDL2");
        step.defineCMacro("SDL_MAIN_HANDLED", "1");
        step.linkSystemLibraryName("SDL2");
        step.linkSystemLibrary("wsock32");
        step.linkSystemLibrary("pthread");
        step.linkSystemLibrary("ws2_32");
        step.linkSystemLibrary("c");
        step.linkSystemLibrary("gdi32");
        step.linkSystemLibrary("user32");
        step.linkSystemLibrary("kernel32");
    } else {
        step.linkSystemLibrary("SDL2");
    }
}

pub fn build(b: *std.build.Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    // Dependencies as static libraries
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
    const tinyosc = b.addStaticLibrary("tinyosc", null);
    tinyosc.setTarget(target);
    tinyosc.setBuildMode(mode);
    tinyosc.addIncludeDir("./deps/tinyosc");
    tinyosc.linkLibC();
    tinyosc.addCSourceFiles(&.{
        "./deps/tinyosc/tinyosc.c",
    }, &.{
        "-Wall",
        "-W",
    });
    // fvad for voice activity detection
    const fvad_path = "./deps/libfvad";
    const fvad = b.addStaticLibrary("fvad", null);
    fvad.setTarget(target);
    fvad.setBuildMode(mode);
    fvad.addIncludeDir(fvad_path ++ "/include");
    fvad.addIncludeDir(fvad_path ++ "/src");
    fvad.linkLibC();
    fvad.addCSourceFiles(&.{
        fvad_path ++ "/src/common.h",
        fvad_path ++ "/src/fvad.c",
        fvad_path ++ "/src/signal_processing/division_operations.c",
        fvad_path ++ "/src/signal_processing/energy.c",
        fvad_path ++ "/src/signal_processing/get_scaling_square.c",
        fvad_path ++ "/src/signal_processing/resample_48khz.c",
        fvad_path ++ "/src/signal_processing/resample_by_2_internal.h",
        fvad_path ++ "/src/signal_processing/resample_by_2_internal.c",
        fvad_path ++ "/src/signal_processing/resample_fractional.c",
        fvad_path ++ "/src/signal_processing/signal_processing_library.h",
        fvad_path ++ "/src/signal_processing/spl_inl.h",
        fvad_path ++ "/src/signal_processing/spl_inl.c",
        fvad_path ++ "/src/vad/vad_core.h",
        fvad_path ++ "/src/vad/vad_core.c",
        fvad_path ++ "/src/vad/vad_filterbank.h",
        fvad_path ++ "/src/vad/vad_filterbank.c",
        fvad_path ++ "/src/vad/vad_gmm.h",
        fvad_path ++ "/src/vad/vad_gmm.c",
        fvad_path ++ "/src/vad/vad_sp.h",
        fvad_path ++ "/src/vad/vad_sp.c",
    }, &.{
        "-Wall",
        "-W",
    });

    // Zig Implementation
    const whisper_zig = b.addExecutable("whisperzig", "src/main.zig");
    whisper_zig.setTarget(target);
    whisper_zig.setBuildMode(mode);
    whisper_zig.addIncludeDir("./deps/whisper.cpp");
    whisper_zig.addIncludeDir("./deps/whisper.cpp/examples/");
    whisper_zig.addIncludeDir(fvad_path ++ "/include");
    whisper_zig.addIncludeDir("./deps/tinyosc");
    whisper_zig.linkLibCpp();
    whisper_zig.install();
    whisper_zig.linkLibrary(whisper);
    whisper_zig.linkLibrary(tinyosc);
    whisper_zig.linkLibrary(fvad);

    const whisper_test = b.addTest("./src/CircularBuffer.zig");
    whisper_test.setBuildMode(mode);
    whisper_test.setTarget(target);
    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&whisper_test.step);

    // C++ Implementation
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

    linkSDL(whisper_osc);
    linkSDL(whisper_zig);

    const run_cmd = whisper_zig.run();
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const run_cpp_cmd = whisper_osc.run();
    run_cpp_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cpp_cmd.addArgs(args);
    }
    const run_cpp_step = b.step("run_cpp", "Run the C++ app/example");
    run_cpp_step.dependOn(&run_cpp_cmd.step);

    if (target.isLinux()) {
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
}
