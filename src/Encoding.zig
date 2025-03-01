const Encoding = @This();

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
