const Decoder = @This();

const std = @import("std");

const Allocator = std.mem.Allocator;

decode_table: [256]u8,
padding: u8,

const unicode_inverse_case_table: [256]u8 = blk: {
    var table: [256]u8 = undefined;

    for (&table, 0..) |*char, index| {
        char.* = switch (index) {
            'A'...'Z', 'À'...'Ö', 'Ø'...'Þ' => index | 0x20,
            'a'...'z', 'à'...'ö', 'ø'...'þ' => index & 0xDF,
            else => index,
        };
    }

    break :blk table;
};

pub const InitError = error{
    InvalidAlphabet,
    InvalidAliasTable,
    InvalidPadding,
};

pub const DecodeError = error{
    OutBufferTooSmall,
    InvalidCharacter,
    MalformedInput,
};

pub const Alias = struct { u8, u8 };

pub const Options = struct {
    alphabet: [32]u8,
    alias_table: ?[]const Alias = null,
    padding: u8 = '=',
    case_sensitive: bool = true,
};

const invlid_char = 0xFF;

pub fn init(options: Options) InitError!Decoder {
    var decode_table = [_]u8{invlid_char} ** 256;

    if (options.case_sensitive) {
        for (options.alphabet, 0..) |char, index| {
            if (decode_table[char] != invlid_char) return error.InvalidAlphabet;

            decode_table[char] = @truncate(index);
        }
    } else {
        for (options.alphabet, 0..) |char, index| {
            const has_char = decode_table[char] != invlid_char;
            const has_inverse_char = decode_table[unicode_inverse_case_table[char]] != invlid_char;

            if (has_char or has_inverse_char) return error.InvalidAlphabet;

            decode_table[char] = @truncate(index);
            decode_table[unicode_inverse_case_table[char]] = @truncate(index);
        }
    }

    if (options.alias_table != null) {
        if (options.case_sensitive) {
            for (options.alias_table.?) |alias| {
                const alias_char, const alphabet_char = alias;
                const has_alias_char = decode_table[alias_char] != invlid_char;
                const has_alphabet_char = decode_table[alphabet_char] != invlid_char;

                if (has_alias_char or !has_alphabet_char) return error.InvalidAliasTable;

                decode_table[alias_char] = decode_table[alphabet_char];
            }
        } else {
            for (options.alias_table.?) |alias| {
                const alias_char, const alphabet_char = alias;
                const has_alias_char = decode_table[alias_char] != invlid_char;
                const has_inverse_alias_char = decode_table[unicode_inverse_case_table[alias_char]] != invlid_char;
                const has_alphabet_char = decode_table[alphabet_char] != invlid_char;

                if (has_alias_char or has_inverse_alias_char or !has_alphabet_char) return error.InvalidAliasTable;

                decode_table[alias_char] = decode_table[alphabet_char];
                decode_table[unicode_inverse_case_table[alias_char]] = decode_table[alphabet_char];
            }
        }
    }

    if (decode_table[options.padding] != invlid_char) return error.InvalidPadding;

    return Decoder{
        .decode_table = decode_table,
        .padding = options.padding,
    };
}

inline fn calcSourceSizeWithoutPadding(self: *const Decoder, source: []const u8) usize {
    var size = source.len;

    while (size > 0 and source[size - 1] == self.padding) size -= 1;

    return size;
}

inline fn calcOutputSize(size_without_padding: usize) usize {
    return size_without_padding * 5 / 8;
}

pub fn calcSize(self: *const Decoder, source: []const u8) usize {
    const size = self.calcSourceSizeWithoutPadding(source);

    return calcOutputSize(size);
}

inline fn getChunk(self: *const Decoder, source: []const u8, comptime size: usize) DecodeError![size]u8 {
    var chunk: @Vector(size, u8) = source[0..size].*;
    const invalid: @Vector(size, u8) = @splat(invlid_char);

    inline for (source[0..size], 0..) |char, index| chunk[index] = self.decode_table[char];

    if (@reduce(.Or, chunk == invalid)) return error.InvalidCharacter;

    return chunk;
}

pub fn decode(self: *const Decoder, dest: []u8, source: []const u8) DecodeError![]u8 {
    if (source.len == 0) return dest[0..0];

    const source_size = self.calcSourceSizeWithoutPadding(source);
    const output_size = calcOutputSize(source_size);

    if (dest.len < output_size) return error.OutBufferTooSmall;

    var source_slice = source[0..source_size];
    var dest_slice = dest[0..output_size];

    while (source_slice.len >= 16) : ({
        source_slice = source_slice[16..];
        dest_slice = dest_slice[10..];
    }) {
        const chunk = try self.getChunk(source_slice, 16);
        const hi_chunk = @shuffle(u8, chunk, undefined, @Vector(10, u8){ 0, 1, 3, 4, 6, 8, 9, 11, 12, 14 });
        const mid_chunk = @shuffle(u8, chunk, undefined, @Vector(10, u8){ 1, 2, 4, 5, 7, 9, 10, 12, 13, 15 });
        const lo_chunk = @shuffle(u8, chunk, [_]u8{0}, @Vector(10, i32){ -1, 3, -1, 6, -1, -1, 11, -1, 14, -1 });
        const hi_l_shift = @Vector(10, u8){ 3, 6, 4, 7, 5, 3, 6, 4, 7, 5 };
        const mid_r_shift = @Vector(10, u8){ 2, 0, 1, 0, 0, 2, 0, 1, 0, 0 };
        const mid_l_shift = @Vector(10, u8){ 0, 1, 0, 2, 0, 0, 1, 0, 2, 0 };
        const lo_r_shift = @Vector(10, u8){ 0, 4, 0, 3, 0, 0, 4, 0, 3, 0 };

        dest_slice[0..10].* = (hi_chunk << hi_l_shift) | (mid_chunk >> mid_r_shift << mid_l_shift) | (lo_chunk >> lo_r_shift);
    }

    if (source_slice.len >= 8) {
        const chunk = try self.getChunk(source_slice, 8);
        const hi_chunk = @shuffle(u8, chunk, undefined, @Vector(5, u8){ 0, 1, 3, 4, 6 });
        const mid_chunk = @shuffle(u8, chunk, undefined, @Vector(5, u8){ 1, 2, 4, 5, 7 });
        const lo_chunk = @shuffle(u8, chunk, [_]u8{0}, @Vector(5, i32){ -1, 3, -1, 6, -1 });
        const hi_l_shift = @Vector(5, u8){ 3, 6, 4, 7, 5 };
        const mid_r_shift = @Vector(5, u8){ 2, 0, 1, 0, 0 };
        const mid_l_shift = @Vector(5, u8){ 0, 1, 0, 2, 0 };
        const lo_r_shift = @Vector(5, u8){ 0, 4, 0, 3, 0 };

        dest_slice[0..5].* = (hi_chunk << hi_l_shift) | (mid_chunk >> mid_r_shift << mid_l_shift) | (lo_chunk >> lo_r_shift);

        source_slice = source_slice[8..];
        dest_slice = dest_slice[5..];
    }

    switch (source_slice.len) {
        7 => {
            const chunk = try self.getChunk(source_slice, 7);

            dest_slice[0] = (chunk[0] << 3) | (chunk[1] >> 2);
            dest_slice[1] = (chunk[1] << 6) | (chunk[2] << 1) | (chunk[3] >> 4);
            dest_slice[2] = (chunk[3] << 4) | (chunk[4] >> 1);
            dest_slice[3] = (chunk[4] << 7) | (chunk[5] << 2) | (chunk[6] >> 3);
        },

        5 => {
            const chunk = try self.getChunk(source_slice, 5);

            dest_slice[0] = (chunk[0] << 3) | (chunk[1] >> 2);
            dest_slice[1] = (chunk[1] << 6) | (chunk[2] << 1) | (chunk[3] >> 4);
            dest_slice[2] = (chunk[3] << 4) | (chunk[4] >> 1);
        },

        4 => {
            const chunk = try self.getChunk(source_slice, 4);

            dest_slice[0] = (chunk[0] << 3) | (chunk[1] >> 2);
            dest_slice[1] = (chunk[1] << 6) | (chunk[2] << 1) | (chunk[3] >> 4);
        },

        2 => {
            const chunk = try self.getChunk(source_slice, 2);

            dest_slice[0] = (chunk[0] << 3) | (chunk[1] >> 2);
        },

        0 => {},

        else => return error.MalformedInput,
    }

    return dest[0..output_size];
}

pub fn allocDecode(self: *const Decoder, allocator: *Allocator, source: []const u8) ![]u8 {
    const output_size = self.calcSize(source);
    const dest = try allocator.alloc(u8, output_size);

    errdefer allocator.free(dest);

    return self.decode(dest, source);
}

test "calc size" {
    const decoder = try Decoder.init(.{ .alphabet = "ybndrfg8ejkmcpqxot1uwisza345h769".* });

    const source = "pb1sa5dxrb5s6hucco";
    const source_with_padding = source ++ "======";

    const size = decoder.calcSize(source);
    const size_with_padding = decoder.calcSize(source_with_padding);

    try std.testing.expect(size == 11);
    try std.testing.expect(size_with_padding == 11);
}

test "decode" {
    const decoder = try Decoder.init(.{ .alphabet = "ybndrfg8ejkmcpqxot1uwisza345h769".* });

    var allocator = std.testing.allocator;

    const source = "pb1sa5dxrb5s6hucco";
    const source_with_padding = source ++ "======";
    const expected = "hello world";

    const decoded = try decoder.allocDecode(&allocator, source);
    defer allocator.free(decoded);

    const decoded_with_padding = try decoder.allocDecode(&allocator, source_with_padding);
    defer allocator.free(decoded_with_padding);

    try std.testing.expectEqualStrings(expected, decoded);
    try std.testing.expectEqualStrings(expected, decoded_with_padding);
}

test "decode case insensitive" {
    const decoder = try Decoder.init(.{
        .alphabet = "ybndrfg8ejkmcpqxot1uwisza345h769".*,
        .case_sensitive = false,
    });

    var allocator = std.testing.allocator;

    const source = "pB1Sa5dXrB5S6HUCco";
    const source_with_padding = source ++ "======";
    const expected = "hello world";

    const decoded = try decoder.allocDecode(&allocator, source);
    defer allocator.free(decoded);

    const decoded_with_padding = try decoder.allocDecode(&allocator, source_with_padding);
    defer allocator.free(decoded_with_padding);

    try std.testing.expectEqualStrings(expected, decoded);
    try std.testing.expectEqualStrings(expected, decoded_with_padding);
}

test "decode with alias" {
    const decoder = try Decoder.init(.{
        .alphabet = "ybndrfg8ejkmcpqxot1uwisza345h769".*,
        .alias_table = &[_]Alias{
            .{ 'l', '1' },
            .{ '0', 'o' },
        },
    });

    var allocator = std.testing.allocator;

    const source = "pblsa5dxrb5s6hucc0";
    const source_with_padding = source ++ "======";
    const expected = "hello world";

    const decoded = try decoder.allocDecode(&allocator, source);
    defer allocator.free(decoded);

    const decoded_with_padding = try decoder.allocDecode(&allocator, source_with_padding);
    defer allocator.free(decoded_with_padding);

    try std.testing.expectEqualStrings(expected, decoded);
    try std.testing.expectEqualStrings(expected, decoded_with_padding);
}

test "decode errors" {
    const decoder = try Decoder.init(.{ .alphabet = "ybndrfg8ejkmcpqxot1uwisza345h769".* });

    var allocator = std.testing.allocator;

    const buf = [_]u8{};
    const buffer_too_small = decoder.decode(&buf, "pb1sa5dxrb5s6hucco");
    const invalid_character = decoder.allocDecode(&allocator, "pb1sa5dxrb5s6hucc0");
    const malformed_input = decoder.allocDecode(&allocator, "pb1sa5dxrb5s6hucc");

    try std.testing.expect(buffer_too_small == error.OutBufferTooSmall);
    try std.testing.expect(invalid_character == error.InvalidCharacter);
    try std.testing.expect(malformed_input == error.MalformedInput);
}

test "init errors" {
    const invalid_padding = Decoder.init(.{
        .alphabet = "ybndrfg8ejkmcpqxot1uwisza345h769".*,
        .padding = 'y',
    });

    try std.testing.expect(invalid_padding == error.InvalidPadding);

    const invalid_alphabet = Decoder.init(.{
        .alphabet = "yyndrfg8ejkmcpqxot1uwisza345h769".*,
    });

    try std.testing.expect(invalid_alphabet == error.InvalidAlphabet);

    const case_conflict = Decoder.init(.{
        .alphabet = "yYndrfg8ejkmcpqxot1uwisza345h769".*,
        .case_sensitive = false,
    });

    try std.testing.expect(case_conflict == error.InvalidAlphabet);

    const invalid_alias = Decoder.init(.{
        .alphabet = "ybndrfg8ejkmcpqxot1uwisza345h769".*,
        .alias_table = &[_]Alias{.{ '0', 'O' }},
    });

    try std.testing.expect(invalid_alias == error.InvalidAliasTable);

    const alias_conflict = Decoder.init(.{
        .alphabet = "ybndrfg8ejkmcpqxot1uwisza345h769".*,
        .alias_table = &[_]Alias{.{ 'i', '1' }},
    });

    try std.testing.expect(alias_conflict == error.InvalidAliasTable);

    const alias_case_conflict = Decoder.init(.{
        .alphabet = "ybndrfg8ejkmcpqxot1uwisza345h769".*,
        .alias_table = &[_]Alias{.{ 'I', '1' }},
        .case_sensitive = false,
    });

    try std.testing.expect(alias_case_conflict == error.InvalidAliasTable);

    const alias_padding_conflict = Decoder.init(.{
        .alphabet = "ybndrfg8ejkmcpqxot1uwisza345h769".*,
        .alias_table = &[_]Alias{.{ '!', '1' }},
        .padding = '!',
    });

    try std.testing.expect(alias_padding_conflict == error.InvalidPadding);
}
