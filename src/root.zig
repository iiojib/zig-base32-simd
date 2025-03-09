const std = @import("std");

pub const Encoding = @import("Encoding.zig");
pub const Encoder = @import("Encoder.zig");
pub const Decoder = @import("Decoder.zig");

pub const standard_alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".*;
pub const standard_hex_alphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUV".*;
pub const crockford_alphabet = "0123456789ABCDEFGHJKMNPQRSTVWXYZ".*;
pub const crockford_alias_table = [_]Decoder.Alias{
    .{ 'O', '0' },
    .{ 'I', '1' },
    .{ 'L', '1' },
};

/// RFC 4648 base32 encoding.
pub const rfc_4648 = Encoding.init(.{ .alphabet = standard_alphabet }) catch unreachable;

/// RFC 4648 base32hex encoding.
pub const rfc_4648_hex = Encoding.init(.{ .alphabet = standard_hex_alphabet }) catch unreachable;

/// Crockford's base32 encoding.
pub const crockford = Encoding.init(.{
    .alphabet = crockford_alphabet,
    .alias_table = &crockford_alias_table,
    .case_sensitive = false,
}) catch unreachable;

test "rfc 4648" {
    const TestVector = struct {
        source: []const u8,
        base32: []const u8,
        base32hex: []const u8,
    };

    const vectors = [_]TestVector{
        .{ .source = "", .base32 = "", .base32hex = "" },
        .{ .source = "f", .base32 = "MY======", .base32hex = "CO======" },
        .{ .source = "fo", .base32 = "MZXQ====", .base32hex = "CPNG====" },
        .{ .source = "foo", .base32 = "MZXW6===", .base32hex = "CPNMU===" },
        .{ .source = "foob", .base32 = "MZXW6YQ=", .base32hex = "CPNMUOG=" },
        .{ .source = "fooba", .base32 = "MZXW6YTB", .base32hex = "CPNMUOJ1" },
        .{ .source = "foobar", .base32 = "MZXW6YTBOI======", .base32hex = "CPNMUOJ1E8======" },
    };

    var allocator = std.testing.allocator;

    for (vectors) |vector| {
        const base32 = try rfc_4648.allocEncode(&allocator, vector.source, true);
        defer allocator.free(base32);

        const base32_decoded = try rfc_4648.allocDecode(&allocator, base32);
        defer allocator.free(base32_decoded);

        const base32hex = try rfc_4648_hex.allocEncode(&allocator, vector.source, true);
        defer allocator.free(base32hex);

        const base32hex_decoded = try rfc_4648_hex.allocDecode(&allocator, base32hex);
        defer allocator.free(base32hex_decoded);

        try std.testing.expectEqualStrings(vector.base32, base32);
        try std.testing.expectEqualStrings(vector.source, base32_decoded);
        try std.testing.expectEqualStrings(vector.base32hex, base32hex);
        try std.testing.expectEqualStrings(vector.source, base32hex_decoded);
    }
}

test "crokford" {
    const TestVector = struct {
        source: []const u8,
        crockford: []const u8,
    };

    const vectors = [_]TestVector{
        .{ .source = "", .crockford = "" },
        .{ .source = "f", .crockford = "CR" },
        .{ .source = "fo", .crockford = "CSQG" },
        .{ .source = "foo", .crockford = "CSQPY" },
        .{ .source = "foob", .crockford = "CSQPYRG" },
        .{ .source = "fooba", .crockford = "CSQPYRK1" },
        .{ .source = "foobar", .crockford = "CSQPYRK1E8" },
    };

    var allocator = std.testing.allocator;

    for (vectors) |vector| {
        const encoded = try crockford.allocEncode(&allocator, vector.source, false);
        defer allocator.free(encoded);

        const decoded = try crockford.allocDecode(&allocator, encoded);
        defer allocator.free(decoded);

        try std.testing.expectEqualStrings(vector.crockford, encoded);
        try std.testing.expectEqualStrings(vector.source, decoded);
    }
}
