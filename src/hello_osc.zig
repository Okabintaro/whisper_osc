const std = @import("std");
const network = @import("./deps/zig-network/network.zig");
const tinyosc = @cImport(
    @cInclude("tinyosc.h"),
);

pub fn main() anyerror!void {
    try network.init();
    defer network.deinit();

    var sock = try network.Socket.create(.ipv4, .udp);
    defer sock.close();
    try sock.connect(.{
        .address = .{ .ipv4 = network.Address.IPv4.init(127, 0, 0, 1) },
        .port = 9000,
    });
    try sock.setReadTimeout(3000000); // 3 seconds
    var msgbuf: [256]u8 = undefined;
    var strbuf: [256]u8 = undefined;

    var i: usize = 0;
    while (i < 10) : (i += 1) {
        const on = i % 2 == 0;
        const msg_len = tinyosc.tosc_writeMessage(&msgbuf, msgbuf.len, "/chatbox/typing", "T", true);
        const sent = try sock.send(msgbuf[0..msg_len]);
        std.debug.print("Sent {} {d} over udp.\n", .{ on, sent });
        std.time.sleep(1.5 * 10e8);
    }
    const text = try std.fmt.bufPrintZ(&strbuf, "Hello from Zig {d}", .{i});
    const msg_len = tinyosc.tosc_writeMessage(&msgbuf, msgbuf.len, "/chatbox/input", "sTT", @ptrCast([*]u8, text), true, true);
    const sent = try sock.send(msgbuf[0..msg_len]);
    std.debug.print("Sent {s} {d} over udp.\n", .{ text, sent });
}
