const std = @import("std");
const sdl = @cImport({
    @cInclude("SDL.h");
    @cInclude("SDL_audio.h");
});

const fvad = @cImport({
    @cInclude("fvad.h");
});

const w = @cImport({
    @cInclude("whisper.h");
});

const network = @import("./deps/zig-network/network.zig");
const tinyosc = @cImport(
    @cInclude("tinyosc.h"),
);

const wav = @import("deps/zig-wav/wav.zig");
const circbuf = @import("CircularBuffer.zig");
pub const log_level: std.log.Level = .info;

const WHISPER_SAMPLE_RATE = 16000;

const bufferSamples = WHISPER_SAMPLE_RATE * 60;
const AudioBuffer = circbuf.AudioBuffer(bufferSamples, 4096, f32);
var continousBuffer = AudioBuffer{};
var speechBuffer: [bufferSamples]f32 = .{0} ** bufferSamples;

pub fn main() anyerror!void {
    if (sdl.SDL_Init(sdl.SDL_INIT_AUDIO) < 0) {
        sdl.SDL_LogError(sdl.SDL_LOG_CATEGORY_APPLICATION, "Couldn't initialize SDL: %s\n", sdl.SDL_GetError());
        return;
    }
    const stdout = std.io.getStdOut().writer();

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
    if (fvad.fvad_set_mode(fvad_handle, 3) != 0) {
        std.log.err("Can't set vad mode, it's invalid", .{});
        return;
    }

    // TODO: Move to its own module for Debouncing
    var voiceDetected: bool = false;
    var voiceSamples: usize = 0;
    var voiceDetecedFiltered: bool = false;
    var voiceDetecedFiltered_: bool = false;

    var voiceStart: usize = 0;
    var voiceEnd: usize = 0;

    // Init whisper
    var whisper = w.whisper_init("./models/ggml-base.en.bin");
    var w_params = w.whisper_full_default_params(0);
    w_params.n_threads = 6;
    w_params.print_progress = false;
    w_params.print_timestamps = false;
    w_params.no_context = true;

    try network.init();
    defer network.deinit();
    var sock = try network.Socket.create(.ipv4, .udp);
    defer sock.close();
    try sock.connect(.{
        .address = .{ .ipv4 = network.Address.IPv4.init(127, 0, 0, 1) },
        .port = 9000,
    });
    var msgbuf: [256]u8 = undefined;

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
            // std.log.warn("WARNING: cannot process audio fast enough, dropping audio...", .{});
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
        _ = sdl.SDL_DequeueAudio(audio_device, &continousBuffer.buffer[continousBuffer.end], n_samples_new * @sizeOf(f32));
        continousBuffer.produced();

        // TODO: Fill circular buffer

        // FVad: Detect Voice Segments in input
        voiceDetected = vad: {
            const buffer = continousBuffer.get();
            // std.log.debug("inbuffer: {d}!", .{buffer});
            var vad_buffer: [480]i16 = undefined;
            var n_detections: i32 = 0;
            const n_slices = @divFloor(buffer.len, 480);

            var i: usize = 0;
            var k: usize = 0;
            while (k < n_slices) : (k += 1) {
                var j: usize = 0;
                while (j < vad_buffer.len) : (j += 1) {
                    const floatval = std.math.clamp(buffer[i], -1.0, 1.0);
                    i += 1;
                    // TODO: Introduce volume meter here?
                    vad_buffer[j] = @floatToInt(i16, floatval * 32767.0);
                }
                // std.log.debug("buffer: {d}!", .{vad_buffer});
                n_detections += fvad.fvad_process(fvad_handle, &vad_buffer, vad_buffer.len);
            }
            voiceDetected = n_detections == n_slices;

            // std.log.debug("detections: {d}!", .{n_detections});
            break :vad voiceDetected;
        };

        if (voiceDetected) {
            voiceSamples += 1;
        } else {
            voiceEnd = continousBuffer.start;
            voiceSamples = 0;
        }
        voiceDetecedFiltered = voiceSamples >= 3;
        if (voiceDetecedFiltered and !voiceDetecedFiltered_) {
            var start: i64 = @intCast(i64, continousBuffer.start) - 4 * 4096;
            if (start < 0) {
                std.debug.print("Wrapping from {d}", .{start});
                start = (@intCast(i64, continousBuffer.chunksize) * @intCast(i64, continousBuffer.nChunks)) + start;
                std.debug.print("to {d}", .{start});
            }
            std.debug.assert(start > 0);
            voiceStart = @intCast(usize, start);
            std.log.info("Voice detected! s: {d}", .{voiceStart});
            const msg_len = tinyosc.tosc_writeMessage(&msgbuf, msgbuf.len, "/chatbox/typing", "T", true);
            _ = try sock.send(msgbuf[0..msg_len]);
        }
        if (!voiceDetecedFiltered and voiceDetecedFiltered_) {
            std.log.info("Voice lost: s:{d}, e:{d}", .{ voiceStart, voiceEnd });

            // Save the saved slices into wav
            const w_samples = continousBuffer.copyTo(&speechBuffer, voiceStart, voiceEnd);
            const speech = speechBuffer[0..w_samples];

            // Detect using whisper
            {
                var strbuf: [320]u8 = undefined;
                const ret = w.whisper_full(whisper, w_params, @ptrCast([*c]const f32, speech), @intCast(c_int, speech.len));
                std.log.info("whisper ret: {d}", .{ret});
                const n_segments = w.whisper_full_n_segments(whisper);
                var i: c_int = 0;
                var stri: usize = 0;
                while (i < n_segments) : (i += 1) {
                    const text = std.mem.span(w.whisper_full_get_segment_text(whisper, i));
                    if (std.mem.count(u8, text, "[") > 0 or std.mem.count(u8, text, "(") > 0) {
                        std.log.info("Ignoring non text segment {s}", .{text});
                        continue;
                    }
                    std.mem.copy(u8, strbuf[stri..], text);
                    stri += text.len;
                }
                strbuf[stri] = 0;
                const fullText = strbuf[0 .. stri + 1];
                try stdout.print("Text: {s}\n", .{fullText});
                const msg_len = tinyosc.tosc_writeMessage(&msgbuf, msgbuf.len, "/chatbox/input", "sTT", @ptrCast([*]const u8, fullText), true, true);
                _ = try sock.send(msgbuf[0..msg_len]);
            }

            // Save wav with the detected text
            const save_wav = false;
            if (save_wav) {
                // TODO: Optimize, buffer and move to another thread probably
                var fileNameBuf: [256]u8 = undefined;
                const fileName = try std.fmt.bufPrint(&fileNameBuf, "test_{d}.wav", .{n_iter});
                var file = try std.fs.cwd().createFile(fileName, .{});
                defer file.close();
                const MySaver = wav.Saver(@TypeOf(file).Writer);
                try MySaver.writeHeader(file.writer(), .{
                    .num_channels = 1,
                    .sample_rate = WHISPER_SAMPLE_RATE,
                    .format = .signed16_lsb,
                });
                std.log.debug("Writing {d} samples to {s}!", .{ w_samples, "test.wav" });
                for (speech) |sample| {
                    const floatval = std.math.clamp(sample, -1.0, 1.0);
                    const y = @floatToInt(i16, floatval * 32767.0);
                    try file.writer().writeIntLittle(i16, y);
                }
                try MySaver.patchHeader(file.writer(), file.seekableStream(), w_samples * 2);
            }
        }
        voiceDetecedFiltered_ = voiceDetecedFiltered;

        n_iter += 1;
    } // While

    fvad.fvad_free(fvad_handle);

    sdl.SDL_CloseAudioDevice(audio_device);
    sdl.SDL_CloseAudio();
    sdl.SDL_Quit();
    w.whisper_free(whisper);
    std.log.info("ByeBye", .{});
}
