const Encoder = @This();

const std = @import("std");

const simd = @import("simd.zig");

const Allocator = std.mem.Allocator;

alphabet: [32]u8,
padding: [6]u8,

/// Intialization errors.
pub const InitError = error{
    InvalidAplhabet,
    InvalidPadding,
};

/// Encoding errors.
pub const EncodeError = error{
    OutBufferTooSmall,
};

/// Encoder options.
pub const Options = struct {
    alphabet: [32]u8,
    padding: u8 = '=',
};

/// Initializes a new encoder instance.
pub fn init(options: Options) InitError!Encoder {
    var char_in_alphabet = [_]bool{false} ** 256;

    for (options.alphabet) |char| {
        // Check for duplicate characters.
        if (char_in_alphabet[char]) return error.InvalidAplhabet;

        char_in_alphabet[char] = true;
    }

    // Check that padding character is not in the alphabet.
    if (char_in_alphabet[options.padding]) return error.InvalidPadding;

    return Encoder{
        .alphabet = options.alphabet,
        // Populate padding array with the padding character.
        .padding = .{options.padding} ** 6,
    };
}

/// Calculates the size required to encode the source data.
pub fn calcSize(_: *const Encoder, source_size: usize, with_padding: bool) usize {
    if (with_padding) {
        return (source_size + 4) / 5 * 8;
    }

    return (source_size * 8 + 4) / 5;
}

/// Encodes the source data into the destination buffer.
pub fn encode(self: *const Encoder, dest: []u8, source: []const u8, with_padding: bool) EncodeError![]u8 {
    if (source.len == 0) return dest[0..0];

    const output_size = self.calcSize(source.len, with_padding);

    if (dest.len < output_size) return error.OutBufferTooSmall;

    var source_slice = source;
    var dest_slice = dest[0..output_size];

    // Encode each 10 bytes to 16 bytes at a time using SIMD.
    while (source_slice.len >= 10) : ({
        source_slice = source_slice[10..];
        dest_slice = dest_slice[16..];
    }) {
        const hi_chunk = @shuffle(u8, source_slice[0..10].*, undefined, @Vector(16, i32){ 0, 0, 1, 1, 2, 3, 3, 4, 5, 5, 6, 6, 7, 8, 8, 9 });
        const lo_chunk = @shuffle(u8, source_slice[0..10].*, [_]u8{0}, @Vector(16, i32){ -1, 1, -1, 2, 3, -1, 4, -1, -1, 6, -1, 7, 8, -1, 9, -1 });
        const hi_r_shift = @Vector(16, u8){ 3, 0, 1, 0, 0, 2, 0, 0, 3, 0, 1, 0, 0, 2, 0, 0 };
        const hi_l_shift = @Vector(16, u8){ 0, 2, 0, 4, 1, 0, 3, 0, 0, 2, 0, 4, 1, 0, 3, 0 };
        const lo_r_shift = @Vector(16, u8){ 0, 6, 0, 4, 7, 0, 5, 0, 0, 6, 0, 4, 7, 0, 5, 0 };
        const mask: @Vector(16, u8) = @splat(0x1F);

        const bytes = (hi_chunk >> hi_r_shift << hi_l_shift) | (lo_chunk >> lo_r_shift) & mask;

        dest_slice[0..16].* = simd.shuffle(16, self.alphabet[0..32].*, bytes);
    }

    // Encode 5 bytes to 8 bytes at a time using SIMD.
    if (source_slice.len >= 5) {
        const hi_chunk = @shuffle(u8, source_slice[0..5].*, undefined, @Vector(8, i32){ 0, 0, 1, 1, 2, 3, 3, 4 });
        const lo_chunk = @shuffle(u8, source_slice[0..5].*, [_]u8{0}, @Vector(8, i32){ -1, 1, -1, 2, 3, -1, 4, -1 });
        const hi_r_shift = @Vector(8, u8){ 3, 0, 1, 0, 0, 2, 0, 0 };
        const hi_l_shift = @Vector(8, u8){ 0, 2, 0, 4, 1, 0, 3, 0 };
        const lo_r_shift = @Vector(8, u8){ 0, 6, 0, 4, 7, 0, 5, 0 };
        const mask: @Vector(8, u8) = @splat(0x1F);

        const bytes: [8]u8 = (hi_chunk >> hi_r_shift << hi_l_shift) | (lo_chunk >> lo_r_shift) & mask;

        dest_slice[0..8].* = simd.shuffle(8, self.alphabet[0..32].*, bytes);

        source_slice = source_slice[5..];
        dest_slice = dest_slice[8..];
    }

    // Encode the remaining bytes.
    switch (source_slice.len) {
        // Using SIMD is still efficient to encode 4 bytes to 7 bytes at a time.
        4 => {
            const hi_chunk = @shuffle(u8, source_slice[0..4].*, undefined, @Vector(7, i32){ 0, 0, 1, 1, 2, 3, 3 });
            const lo_chunk = @shuffle(u8, source_slice[0..4].*, @Vector(1, u8){0}, @Vector(7, i32){ -1, 1, -1, 2, 3, -1, -1 });
            const hi_r_shift = @Vector(7, u8){ 3, 0, 1, 0, 0, 2, 0 };
            const hi_l_shift = @Vector(7, u8){ 0, 2, 0, 4, 1, 0, 3 };
            const lo_r_shift = @Vector(7, u8){ 0, 6, 0, 4, 7, 0, 0 };
            const mask: @Vector(7, u8) = @splat(0x1F);

            const bytes: [7]u8 = hi_chunk >> hi_r_shift << hi_l_shift | lo_chunk >> lo_r_shift & mask;

            dest_slice[0..7].* = simd.shuffle(7, self.alphabet[0..32].*, bytes);

            if (with_padding) dest_slice[7] = self.padding[0];
        },

        3 => {
            dest_slice[0] = self.alphabet[source_slice[0] >> 3 & 0x1F];
            dest_slice[1] = self.alphabet[source_slice[0] << 2 | source_slice[1] >> 6 & 0x1F];
            dest_slice[2] = self.alphabet[source_slice[1] >> 1 & 0x1F];
            dest_slice[3] = self.alphabet[source_slice[1] << 4 | source_slice[2] >> 4 & 0x1F];
            dest_slice[4] = self.alphabet[source_slice[2] << 1 & 0x1F];

            if (with_padding) dest_slice[5..8].* = self.padding[0..3].*;
        },

        2 => {
            dest_slice[0] = self.alphabet[source_slice[0] >> 3 & 0x1F];
            dest_slice[1] = self.alphabet[source_slice[0] << 2 | source_slice[1] >> 6 & 0x1F];
            dest_slice[2] = self.alphabet[source_slice[1] >> 1 & 0x1F];
            dest_slice[3] = self.alphabet[source_slice[1] << 4 & 0x1F];

            if (with_padding) dest_slice[4..8].* = self.padding[0..4].*;
        },

        1 => {
            dest_slice[0] = self.alphabet[source_slice[0] >> 3 & 0x1F];
            dest_slice[1] = self.alphabet[source_slice[0] << 2 & 0x1F];

            if (with_padding) dest_slice[2..8].* = self.padding;
        },

        else => {},
    }

    return dest[0..output_size];
}

/// Allocates a buffer and encodes the source data into it.
/// The caller is responsible for freeing the returned buffer.
pub fn allocEncode(self: *const Encoder, allocator: *Allocator, source: []const u8, with_padding: bool) ![]u8 {
    const output_size = self.calcSize(source.len, with_padding);
    const dest = try allocator.alloc(u8, output_size);

    return self.encode(dest, source, with_padding);
}

test "calc size" {
    const encoder = try Encoder.init(.{
        .alphabet = "ybndrfg8ejkmcpqxot1uwisza345h769".*,
    });

    const source = "hello world";

    const size = encoder.calcSize(source.len, false);
    const size_with_padding = encoder.calcSize(source.len, true);

    try std.testing.expect(size == 18);
    try std.testing.expect(size_with_padding == 24);
}

test "encode" {
    const encoder = try Encoder.init(.{
        .alphabet = "ybndrfg8ejkmcpqxot1uwisza345h769".*,
    });

    var allocator = std.testing.allocator;

    const source = "hello world";
    const expected = "pb1sa5dxrb5s6hucco";
    const expected_with_padding = expected ++ "======";

    const encoded = try encoder.allocEncode(&allocator, source, false);
    defer allocator.free(encoded);

    const encoded_with_padding = try encoder.allocEncode(&allocator, source, true);
    defer allocator.free(encoded_with_padding);

    try std.testing.expectEqualStrings(expected, encoded);
    try std.testing.expectEqualStrings(expected_with_padding, encoded_with_padding);
}

test "encode with custom padding" {
    const encoder = try Encoder.init(.{
        .alphabet = "ybndrfg8ejkmcpqxot1uwisza345h769".*,
        .padding = '!',
    });

    var allocator = std.testing.allocator;

    const source = "hello world";
    const expected = "pb1sa5dxrb5s6hucco!!!!!!";

    const encoded = try encoder.allocEncode(&allocator, source, true);
    defer allocator.free(encoded);

    try std.testing.expectEqualStrings(expected, encoded);
}

test "encode errors" {
    const encoder = try Encoder.init(.{
        .alphabet = "ybndrfg8ejkmcpqxot1uwisza345h769".*,
    });

    var buf = [_]u8{};
    const source = "hello world";
    const err = encoder.encode(&buf, source, true);

    try std.testing.expect(err == error.OutBufferTooSmall);
}

test "init errors" {
    const invalid_padding = Encoder.init(.{
        .alphabet = "ybndrfg8ejkmcpqxot1uwisza345h769".*,
        .padding = 'y',
    });

    try std.testing.expect(invalid_padding == error.InvalidPadding);

    const invalid_alphabet = Encoder.init(.{
        .alphabet = "yyndrfg8ejkmcpqxot1uwisza345h769".*,
    });

    try std.testing.expect(invalid_alphabet == error.InvalidAplhabet);
}
