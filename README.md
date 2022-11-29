Whisper OSC
===========

This is using the awesome [whisper.cpp](https://github.com/ggerganov/whisper.cpp) project to transcribe your microphone and send it as a message to VRChat.
It is a quick adaptation of the [stream example from whisper.cpp](https://github.com/ggerganov/whisper.cpp/tree/master/examples/stream) and uses [tinyosc](https://github.com/mhroth/tinyosc) to build the OSC messages at the moment.

Still work in progress, but already kinda works on Linux.

## Goals

- Easy to use and setup on Windows
- Easy to compile using [zig](https://ziglang.org/) as a [build system](https://kristoff.it/blog/maintain-it-with-zig/)

## How to build and run

1. Download the appropriate models from [whisper.cpp](https://github.com/ggerganov/whisper.cpp/tree/master/models) and copy them to your `$PWD/models`.
2. Install Zig and build it using `zig build -Drelease-fast=true` (Tested with `zig 0.9.1`)
3. Run it, e.g. using `zig build run -Drelease-fast=true -- -m ./models/ggml-tiny.en.bin -t 10 
--step 1100 --length 5000`.

## TODO

- [ ] Get cross compiling to windows to work
- [ ] More post processing of chat output, since VRChat throttles chatbox messages
  - Filter out reptition, non-voice tokens and simply throttle the output somehow
  - Transcriptions can also dissapear too quickly.

----

- [ ] Port it to zig and clean it up
- [ ] Consider moving from SDL to miniaudio or something else
- [ ] GUI?

## Prior Art

[Whispering Tiger](https://github.com/Sharrnah/whispering) looks really cool, but I haven't tried it yet.
I hope this project can be a bit more lightweight though, [but probably won't be as accurate and fast since it's CPU only and has some other limitations](https://github.com/ggerganov/whisper.cpp#limitations).
