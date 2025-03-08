const Encoding = @This();

const std = @import("std");

const Allocator = std.mem.Allocator;

const Encoder = @import("Encoder.zig");
const Decoder = @import("Decoder.zig");

encoder: Encoder,
decoder: Decoder,

pub const Options = struct {
    alphabet: [32]u8,
    alias_table: ?[]const Decoder.Alias = null,
    padding: u8 = '=',
    case_sensitive: bool = true,
};

pub fn init(options: Options) !Encoding {
    return Encoding{
        .encoder = try Encoder.init(.{
            .alphabet = options.alphabet,
            .padding = options.padding,
        }),

        .decoder = try Decoder.init(.{
            .alphabet = options.alphabet,
            .alias_table = options.alias_table,
            .padding = options.padding,
            .case_sensitive = options.case_sensitive,
        }),
    };
}

pub inline fn calcEncodeSize(self: *const Encoding, source_size: usize, with_padding: bool) usize {
    return self.encoder.calcSize(source_size, with_padding);
}

pub inline fn encode(self: *const Encoding, dest: []u8, source: []const u8, with_padding: bool) ![]u8 {
    return self.encoder.encode(dest, source, with_padding);
}

pub inline fn allocEncode(self: *const Encoding, allocator: *Allocator, source: []const u8, with_padding: bool) ![]u8 {
    return self.encoder.allocEncode(allocator, source, with_padding);
}

pub inline fn calcDecodeSize(self: *const Encoding, source_size: usize) usize {
    return self.decoder.calcSize(source_size);
}

pub inline fn decode(self: *const Encoding, dest: []u8, source: []const u8) ![]u8 {
    return self.decoder.decode(dest, source);
}

pub inline fn allocDecode(self: *const Encoding, allocator: *Allocator, source: []const u8) ![]u8 {
    return self.decoder.allocDecode(allocator, source);
}

test "encoding" {
    const encoding = try Encoding.init(.{
        .alphabet = "ybndrfg8ejkmcpqxot1uwisza345h769".*,
    });

    var allocator = std.testing.allocator;

    const source = "hello world";

    const encoded = try encoding.allocEncode(&allocator, source, false);
    defer allocator.free(encoded);

    const encoded_with_padding = try encoding.allocEncode(&allocator, source, true);
    defer allocator.free(encoded_with_padding);

    const decoded = try encoding.allocDecode(&allocator, encoded);
    defer allocator.free(decoded);

    const decoded_with_padding = try encoding.allocDecode(&allocator, encoded_with_padding);
    defer allocator.free(decoded_with_padding);

    try std.testing.expectEqualStrings(source, decoded);
    try std.testing.expectEqualStrings(source, decoded_with_padding);
}

test "encoding random" {
    const encoding = try Encoding.init(.{
        .alphabet = "ybndrfg8ejkmcpqxot1uwisza345h769".*,
    });

    var allocator = std.testing.allocator;

    var prng = std.Random.DefaultPrng.init(blk: {
        var seed: u64 = undefined;

        try std.posix.getrandom(std.mem.asBytes(&seed));

        break :blk seed;
    });

    var source: [16]u8 = undefined;

    prng.fill(&source);

    const encoded = try encoding.allocEncode(&allocator, &source, false);
    defer allocator.free(encoded);

    const encoded_with_padding = try encoding.allocEncode(&allocator, &source, true);
    defer allocator.free(encoded_with_padding);

    const decoded = try encoding.allocDecode(&allocator, encoded);
    defer allocator.free(decoded);

    const decoded_with_padding = try encoding.allocDecode(&allocator, encoded_with_padding);
    defer allocator.free(decoded_with_padding);

    try std.testing.expectEqualStrings(&source, decoded);
    try std.testing.expectEqualStrings(&source, decoded_with_padding);
}
