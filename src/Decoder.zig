const Decoder = @This();

const Allocator = @import("std").mem.Allocator;

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
