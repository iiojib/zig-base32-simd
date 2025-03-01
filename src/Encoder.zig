const Encoder = @This();

const Allocator = @import("std").mem.Allocator;

alphabet: [32]u8,
padding: [6]u8,

pub const InitError = error{
    InvalidAplhabet,
    InvalidPadding,
};

pub const EncodeError = error{
    OutBufferTooSmall,
};

pub const Options = struct {
    alphabet: [32]u8,
    padding: u8 = '=',
};

pub fn init(options: Options) InitError!Encoder {
    var char_in_alphabet = [_]bool{false} ** 256;

    for (options.alphabet) |char| {
        if (char_in_alphabet[char]) return error.InvalidAplhabet;

        char_in_alphabet[char] = true;
    }

    if (char_in_alphabet[options.padding]) return error.InvalidPadding;

    return Encoder{
        .alphabet = options.alphabet,
        .padding = .{options.padding} ** 6,
    };
}

pub fn calcSize(_: *const Encoder, source_size: usize, with_padding: bool) usize {
    if (with_padding) {
        return (source_size + 4) / 5 * 8;
    }

    return (source_size * 8 + 4) / 5;
}

pub fn encode(self: *const Encoder, dest: []u8, source: []const u8, with_padding: bool) EncodeError![]u8 {
    if (source.len == 0) return dest[0..0];

    const output_size = self.calcSize(source.len, with_padding);

    if (dest.len < output_size) return error.OutBufferTooSmall;

    var source_slice = source;
    var dest_slice = dest[0..output_size];

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

        const bytes: [16]u8 = (hi_chunk >> hi_r_shift << hi_l_shift) | (lo_chunk >> lo_r_shift) & mask;

        inline for (bytes, 0..) |char, index| dest_slice[index] = self.alphabet[char];
    }

    if (source_slice.len >= 5) {
        const hi_chunk = @shuffle(u8, source_slice[0..5].*, undefined, @Vector(8, i32){ 0, 0, 1, 1, 2, 3, 3, 4 });
        const lo_chunk = @shuffle(u8, source_slice[0..5].*, [_]u8{0}, @Vector(8, i32){ -1, 1, -1, 2, 3, -1, 4, -1 });
        const hi_r_shift = @Vector(8, u8){ 3, 0, 1, 0, 0, 2, 0, 0 };
        const hi_l_shift = @Vector(8, u8){ 0, 2, 0, 4, 1, 0, 3, 0 };
        const lo_r_shift = @Vector(8, u8){ 0, 6, 0, 4, 7, 0, 5, 0 };
        const mask: @Vector(8, u8) = @splat(0x1F);

        const bytes: [8]u8 = (hi_chunk >> hi_r_shift << hi_l_shift) | (lo_chunk >> lo_r_shift) & mask;

        inline for (bytes, 0..) |char, index| dest_slice[index] = self.alphabet[char];

        source_slice = source_slice[5..];
        dest_slice = dest_slice[8..];
    }

    switch (source_slice.len) {
        4 => {
            const hi_chunk = @shuffle(u8, source_slice[0..4].*, undefined, @Vector(7, i32){ 0, 0, 1, 1, 2, 3, 3 });
            const lo_chunk = @shuffle(u8, source_slice[0..4].*, @Vector(1, u8){0}, @Vector(7, i32){ -1, 1, -1, 2, 3, -1, -1 });
            const hi_r_shift = @Vector(7, u8){ 3, 0, 1, 0, 0, 2, 0 };
            const hi_l_shift = @Vector(7, u8){ 0, 2, 0, 4, 1, 0, 3 };
            const lo_r_shift = @Vector(7, u8){ 0, 6, 0, 4, 7, 0, 0 };
            const mask: @Vector(7, u8) = @splat(0x1F);

            const bytes: [7]u8 = hi_chunk >> hi_r_shift << hi_l_shift | lo_chunk >> lo_r_shift & mask;

            inline for (bytes, 0..) |char, index| dest_slice[index] = self.alphabet[char];

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

pub fn allocEncode(self: *const Encoder, allocator: *Allocator, source: []const u8, with_padding: bool) ![]u8 {
    const output_size = self.calcSize(source.len, with_padding);
    const dest = try allocator.alloc(u8, output_size);

    return self.encode(dest, source, with_padding);
}
