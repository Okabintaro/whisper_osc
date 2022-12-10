const std = @import("std");
const sdl = @cImport({
    @cInclude("SDL.h");
    @cInclude("SDL_audio.h");
});

const fvad = @cImport({
    @cInclude("fvad.h");
});

const wav = @import("deps/zig-wav/wav.zig");

const WHISPER_SAMPLE_RATE = 16000;
const buffersize_bytes = WHISPER_SAMPLE_RATE * 30 * 4;
var gbuffer: [buffersize_bytes]u8 = .{0} ** buffersize_bytes;

pub fn writeWavTest() anyerror!void {
    var file = try std.fs.cwd().createFile("test.wav", .{});
    defer file.close();
    const MySaver = wav.Saver(@TypeOf(file).Writer);
    try MySaver.writeHeader(file.writer(), .{
        .num_channels = 1,
        .sample_rate = WHISPER_SAMPLE_RATE,
        .format = .signed16_lsb,
    });

    var i: usize = 0;
    while (i < WHISPER_SAMPLE_RATE) : (i += 1) {
        const x: f32 = (@intToFloat(f32, i) / @intToFloat(f32, WHISPER_SAMPLE_RATE)) * 880.0;
        const y: i16 = @floatToInt(i16, std.math.sin(x) * 32767.0);
        try file.writer().writeIntLittle(i16, y);
    }

    try MySaver.patchHeader(file.writer(), file.seekableStream(), WHISPER_SAMPLE_RATE * 2);
}

pub fn main() anyerror!void {
    var fba = std.heap.FixedBufferAllocator.init(&gbuffer);
    const allocator = fba.allocator();
    var audioSlice = try allocator.alloc(i16, WHISPER_SAMPLE_RATE * 20);
    var asi: usize = 0;
    var n_slice: usize = 0;
    try writeWavTest();

    if (sdl.SDL_Init(sdl.SDL_INIT_AUDIO) < 0) {
        sdl.SDL_LogError(sdl.SDL_LOG_CATEGORY_APPLICATION, "Couldn't initialize SDL: %s\n", sdl.SDL_GetError());
        return;
    }

    var capture_id: i32 = 2;
    _ = sdl.SDL_SetHintWithPriority(sdl.SDL_HINT_AUDIO_RESAMPLING_MODE, "medium", sdl.SDL_HINT_OVERRIDE);
    const nDevices = sdl.SDL_GetNumAudioDevices(sdl.SDL_TRUE);
    {
        var i: i32 = 0;
        while (i < nDevices) {
            const name = sdl.SDL_GetAudioDeviceName(i, sdl.SDL_TRUE);
            std.log.debug("Capture Device {d}: {s}", .{ i, name });
            i += 1;
        }
    }

    var capture_spec_requested: sdl.SDL_AudioSpec = std.mem.zeroes(sdl.SDL_AudioSpec);
    capture_spec_requested.freq = WHISPER_SAMPLE_RATE;
    capture_spec_requested.format = sdl.AUDIO_F32;
    capture_spec_requested.channels = 1;
    capture_spec_requested.samples = 1024;

    var capture_spec_obtained: sdl.SDL_AudioSpec = std.mem.zeroes(sdl.SDL_AudioSpec);
    var audio_device = sdl.SDL_OpenAudioDevice(sdl.SDL_GetAudioDeviceName(capture_id, sdl.SDL_TRUE), sdl.SDL_TRUE, &capture_spec_requested, &capture_spec_obtained, 0);
    if (audio_device == 0) {
        sdl.SDL_LogError(sdl.SDL_LOG_CATEGORY_APPLICATION, "Couldn't open audio device: %s\n", sdl.SDL_GetError());
        return;
    }

    // const n_samples: i32 = (3000 / 1000) * WHISPER_SAMPLE_RATE;
    const n_samples: i32 = WHISPER_SAMPLE_RATE / 4;
    var buffer: [n_samples * 2]f32 = [_]f32{0} ** (n_samples * 2);
    std.log.debug("n_samples: {d}", .{n_samples});
    // const int n_samples_len = (params.length_ms / 1000.0) * WHISPER_SAMPLE_RATE;
    // const int n_samples_30s = 30 * WHISPER_SAMPLE_RATE;
    // const int n_samples_keep = 0.2 * WHISPER_SAMPLE_RATE;

    var is_running: bool = true;
    var n_iter: i32 = 0;
    sdl.SDL_PauseAudioDevice(audio_device, 0);
    var fvad_handle = fvad.fvad_new();
    if (fvad_handle == null) {
        std.log.err("Could not initialize VFAD", .{});
        return;
    }
    if (fvad.fvad_set_sample_rate(fvad_handle, WHISPER_SAMPLE_RATE) != 0) {
        std.log.err("Invalid sample rate: {d}", .{WHISPER_SAMPLE_RATE});
        return;
    }
    if (fvad.fvad_set_mode(fvad_handle, 0) != 0) {
        std.log.err("Can't set vad mode, it's invalid", .{});
        return;
    }

    var voiceDetected: bool = false;
    var voiceDetected_: bool = false;
    var voiceSamples: u32 = 0;

    std.log.info("Ready... Waiting for input.", .{});
    while (is_running) {
        var event: sdl.SDL_Event = undefined;
        while (sdl.SDL_PollEvent(&event) == sdl.SDL_TRUE) {
            switch (event.type) {
                sdl.SDL_QUIT => {
                    is_running = false;
                    break;
                },
                else => {},
            }
        }
        if (!is_running) {
            break;
        }

        // process new audio
        if (n_iter > 0 and sdl.SDL_GetQueuedAudioSize(audio_device) > (2 * n_samples * @sizeOf(f32))) {
            std.log.warn("WARNING: cannot process audio fast enough, dropping audio...", .{});
            sdl.SDL_ClearQueuedAudio(audio_device);
        }

        // Wait for Audio
        var queued_bytes: u32 = sdl.SDL_GetQueuedAudioSize(audio_device);
        while (queued_bytes < n_samples * @sizeOf(f32)) {
            sdl.SDL_Delay(1);
            queued_bytes = sdl.SDL_GetQueuedAudioSize(audio_device);
        }
        // Load Audio into buffer
        var n_samples_new: u32 = sdl.SDL_GetQueuedAudioSize(audio_device) / @sizeOf(f32);
        _ = sdl.SDL_DequeueAudio(audio_device, &buffer, n_samples_new * @sizeOf(f32));

        // Dumb energy/volume based VAD
        {
            var i: u32 = n_samples_new;
            var sum: f32 = 0;
            while (i > 0) : (i -= 1) {
                sum += std.math.absFloat(buffer[i]);
            }
            // std.log.debug("Sum: {d}", .{sum});
        }

        // FVad: Detect Voice
        {
            var i: usize = 0;
            var vad_buffer: [480]i16 = undefined;
            var n_detections: i32 = 0;
            var all_detections: i32 = 0;
            while (i < n_samples_new) {
                var j: usize = 0;
                while (j < vad_buffer.len) {
                    const floatval = std.math.clamp(buffer[i], -1.0, 1.0);
                    vad_buffer[j] = @floatToInt(i16, floatval * 32767.0);
                    i += 1;
                    j += 1;
                }
                all_detections += 1;

                n_detections += fvad.fvad_process(fvad_handle, &vad_buffer, vad_buffer.len);
            }

            voiceDetected_ = voiceDetected;
            voiceDetected = n_detections == all_detections;
            if (!voiceDetected_ and voiceDetected) {
                std.log.info("Voice detected: {d}/{d}!", .{ n_detections, all_detections });
            }
            if (voiceDetected) {
                voiceSamples += 1;
                // Save into audioSlice for saving
                {
                    i = 0;
                    while (i < n_samples_new) : (i += 1) {
                        const floatval = std.math.clamp(buffer[i], -1.0, 1.0);
                        audioSlice[asi] = @floatToInt(i16, floatval * 32767.0);
                        asi += 1;
                    }
                }
                // Copy samples into audioSlice
            }
            if (voiceDetected_ and !voiceDetected) {
                std.log.info("Voice lost after {d}", .{voiceSamples});
                voiceSamples = 0;
                // Save the saved slices into wav
                {
                    var file = try std.fs.cwd().createFile("test.wav", .{});
                    defer file.close();
                    const MySaver = wav.Saver(@TypeOf(file).Writer);
                    try MySaver.writeHeader(file.writer(), .{
                        .num_channels = 1,
                        .sample_rate = WHISPER_SAMPLE_RATE,
                        .format = .signed16_lsb,
                    });

                    std.log.debug("Writing {d} samples to {s}!", .{ asi, "test.wav" });
                    i = 0;
                    while (i < asi) : (i += 1) {
                        const y: i16 = audioSlice[i];
                        try file.writer().writeIntLittle(i16, y);
                    }
                    asi = 0;

                    try MySaver.patchHeader(file.writer(), file.seekableStream(), asi * 2);
                    n_slice += 1;
                    break;
                }
            }
        }

        //
        n_iter += 1;
    } // While

    fvad.fvad_free(fvad_handle);

    sdl.SDL_CloseAudioDevice(audio_device);
    sdl.SDL_CloseAudio();
    sdl.SDL_Quit();
}
