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

pub const rfc_4648 = Encoding.init(.{ .alphabet = standard_alphabet }) catch unreachable;

pub const rfc_4648_hex = Encoding.init(.{ .alphabet = standard_hex_alphabet }) catch unreachable;

pub const crockford = Encoding.init(.{
    .alphabet = crockford_alphabet,
    .alias_table = &crockford_alias_table,
    .case_sensitive = false,
}) catch unreachable;
