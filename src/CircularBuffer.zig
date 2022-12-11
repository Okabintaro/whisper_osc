const std = @import("std");
const testing = std.testing;

pub fn AudioBuffer(comptime size: comptime_int, comptime chunksize: comptime_int, comptime T: type) type {
    return struct {
        const This = @This();

        nChunks: usize = @divFloor(size, chunksize),
        chunksize: usize = chunksize,
        buffer: [size]T = .{0} ** size,
        start: usize = 0,
        end: usize = 0,

        pub fn put(this: *This, value: []const T) void {
            var dest = this.buffer[this.end .. this.end + chunksize];
            std.mem.copy(T, dest, value);
            this.produced();
        }

        pub fn produced(this: *This) void {
            this.end += chunksize;
            if (this.end > this.buffer.len - chunksize) {
                this.end = 0;
            }
        }
        pub fn consumed(this: *This) void {
            this.start += chunksize;
            if (this.start > this.buffer.len - chunksize) {
                this.start = 0;
            }
        }

        pub fn get(this: *This) []T {
            defer this.consumed();
            return this.buffer[this.start .. this.start + chunksize];
        }

        pub fn copyTo(this: *This, dest: []T, start: usize, end: usize) usize {
            std.debug.assert(start <= this.buffer.len);
            std.debug.assert(end <= this.buffer.len);
            if (end > start) {
                // Usual case: Straing copy, no wrapping needed
                const len = end - start;
                std.debug.assert(dest.len >= len);
                std.mem.copy(T, dest, this.buffer[start..end]);
                return len;
            } else {
                // Tricky case: Wrap

                // Only consider real data in buffer
                const bufferEnd: usize = @divFloor(this.buffer.len, chunksize) * chunksize;
                const len = (bufferEnd - start) + end;
                std.debug.assert(dest.len >= len);

                var j: usize = 0;
                var i: usize = start;
                while (i < bufferEnd) : (i += 1) {
                    dest[j] = this.buffer[i];
                    j += 1;
                }
                i = 0;
                while (i < end) : (i += 1) {
                    dest[j] = this.buffer[i];
                    j += 1;
                }
                return len;
            }
        }
    };
}

test "filling it up" {
    var buf = AudioBuffer(48, 16, f32){};
    var data: [16]f32 = undefined;
    var i: usize = 0;
    while (i < data.len) : (i += 1) {
        data[i] = @intToFloat(f32, i);
    }
    buf.put(&data);
    buf.put(&data);
    buf.put(&data);

    try testing.expectEqualSlices(f32, &data, buf.buffer[0..16]);
    try testing.expectEqualSlices(f32, &data, buf.buffer[16..32]);
    try testing.expectEqualSlices(f32, &data, buf.buffer[32..48]);
}

test "consuming" {
    var buf = AudioBuffer(48, 10, f32){};
    var data: [48]f32 = undefined;
    var i: usize = 0;
    while (i < data.len) : (i += 1) {
        data[i] = @intToFloat(f32, i);
    }

    buf.put(data[0..10]);
    try testing.expectEqualSlices(f32, data[0..10], buf.get());
    buf.put(data[0..10]);
    try testing.expectEqualSlices(f32, data[0..10], buf.get());
    buf.put(data[0..10]);
    try testing.expectEqualSlices(f32, data[0..10], buf.get());
    buf.put(data[0..10]);
    try testing.expectEqualSlices(f32, data[0..10], buf.get());
    buf.put(data[0..10]);
    try testing.expectEqualSlices(f32, data[0..10], buf.get());
    buf.put(data[0..10]);
    try testing.expectEqualSlices(f32, data[0..10], buf.get());
}

// test "Wrong Chunksize" {
//     var buf = AudioBuffer(48, 10, f32){};
//     var data: [48]f32 = undefined;
//     var i: usize = 0;
//     while (i < data.len) : (i += 1) {
//         data[i] = @intToFloat(f32, i);
//     }
//
//     // TODO: This should fail properly
//     // buf.put(data[0..32]);
// }

test "copyTo" {
    var buf = AudioBuffer(80, 32, f32){};
    var data: [128]f32 = undefined;

    var i: usize = 0;
    while (i < data.len) : (i += 1) {
        data[i] = @intToFloat(f32, i);
    }

    buf.put(data[0..32]);
    try testing.expectEqualSlices(f32, data[0..32], buf.buffer[0..32]);
    buf.put(data[32..64]);
    buf.put(data[64..96]); // Wrapping, overwrites first bytes again
    try testing.expectEqualSlices(f32, data[64..96], buf.buffer[0..32]);

    var dest: [48]f32 = undefined;
    const len = buf.copyTo(&dest, 64, 32);
    try testing.expectEqual(@as(usize, 32), len);
    try testing.expectEqualSlices(f32, dest[0..32], buf.get());
    try testing.expectEqualSlices(f32, dest[0..32], data[64..96]);
}
