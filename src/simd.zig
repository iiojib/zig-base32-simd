const std = @import("std");
const builtin = @import("builtin");

const Target = std.Target;
const SemanticVersion = std.SemanticVersion;

const cpu = builtin.cpu;
const zig_version = builtin.zig_version;

inline fn avx(input: @Vector(16, u8), mask: @Vector(16, u8)) @Vector(16, u8) {
    return asm volatile (
        \\VPSHUFB %[mask], %[input], %[output]
        : [output] "=x" (-> @Vector(16, u8)),
        : [mask] "x" (mask),
          [input] "x" (input),
    );
}

inline fn neon(input: @Vector(16, u8), mask: @Vector(16, u8)) @Vector(16, u8) {
    return asm volatile (
        \\TBL.16B %[output], {%[input]}, %[mask]
        : [output] "=x" (-> @Vector(16, u8)),
        : [input] "x" (input),
          [mask] "x" (mask),
    );
}

inline fn wasm(input: @Vector(16, u8), mask: @Vector(16, u8)) @Vector(16, u8) {
    return asm volatile (
        \\local.get %[input]
        \\local.get %[mask]
        \\i8x16.swizzle
        \\local.set %[output]
        : [output] "=r" (-> @Vector(16, u8)),
        : [input] "r" (input),
          [mask] "r" (mask),
    );
}

const SimdType = enum {
    avx,
    neon,
    wasm,
    no_simd,
};

const simd_type: SimdType = blk: {
    if (cpu.arch.isX86() and Target.x86.featureSetHas(cpu.features, .avx)) {
        break :blk .avx;
    }

    if (cpu.arch.isAARCH64() and Target.aarch64.featureSetHas(cpu.features, .neon)) {
        break :blk .neon;
    }

    // WASM inlining fails in Zig 0.14.0 due to a bug in LLVM 19.
    const supported_wasm_version = SemanticVersion{ .major = 0, .minor = 13, .patch = 0 };
    const is_supported_wasm_version = SemanticVersion.order(zig_version, supported_wasm_version) != .gt;

    if (cpu.arch.isWasm() and Target.wasm.featureSetHas(cpu.features, .simd128) and is_supported_wasm_version) {
        break :blk .wasm;
    }

    break :blk .no_simd;
};

const shuffle16 = switch (simd_type) {
    .avx => avx,
    .neon => neon,
    .wasm => wasm,
    .no_simd => unreachable,
};

// The basic shuffle instruction operates on 128-bit lanes,
// so we split the 32-byte input into two 16-byte vectors ([0..16], [16..32]).
// The mask is also split into two base-16 components,
// where the high component retains only the lower 4 bits of values greater than 15.
//
// example:
// mask: 15  9 20 22 14  8  3  2 12  5 25 22 10 12 25 18
// high:  -  -  4  6  -  -  -  -  -  -  9  6  -  -  9  2
// low:  15  9  -  - 14  8  3  2 12  5  -  - 10 12  -  -
inline fn shuffle32(comptime size: usize, input: [32]u8, mask: [size]u8) [size]u8 {
    // Extend the mask to 16 bytes and zero out the remaining slots.
    const mask_16: @Vector(16, u8) = mask ++ [_]u8{0} ** (16 - size);
    // Threshold to determine if mask values belong to the high or low component.
    const overflow_mask: @Vector(16, u8) = @splat(0xF);
    // Vector of 0x80 values used for empty mask slots. These values are used to zero out the corresponding slots in the output during shuffling.
    const empty: @Vector(16, u8) = @splat(0x80);

    // Boolean vector to determine if mask values belong to the high or low component.
    const hi_lo_mask = mask_16 > overflow_mask;

    const hi_mask = @select(u8, hi_lo_mask, mask_16 & overflow_mask, empty);
    const lo_mask = @select(u8, hi_lo_mask, empty, mask_16);

    const result: [16]u8 = shuffle16(input[16..32].*, hi_mask) | shuffle16(input[0..16].*, lo_mask);

    // Truncate the result to the original size.
    return result[0..size].*;
}

// Fallback implementation for platforms without SIMD support.
inline fn fallback(comptime size: usize, input: [32]u8, mask: [size]u8) [size]u8 {
    var output: [size]u8 = undefined;

    inline for (&output, 0..) |*char, index| char.* = input[mask[index]];

    return output;
}

/// Shuffles 32 bytes of input data using a runtime known 16-byte mask.
pub const shuffle = switch (simd_type) {
    .avx, .neon, .wasm => shuffle32,
    .no_simd => fallback,
};

test "simd" {
    if (simd_type == .no_simd) return error.SkipZigTest;

    // Base16 alphabet.
    const input = "0123456789ABCDEF".*;
    // "encoding" word in 4-bit segments.
    const mask = [_]u8{ 6, 5, 6, 14, 6, 3, 6, 15, 6, 4, 6, 9, 6, 14, 6, 7 };
    // "encoding" in base16.
    const expected = "656E636F64696E67";

    const result: [16]u8 = shuffle16(input, mask);

    try std.testing.expectEqualStrings(expected, &result);
}

test "shuffle" {
    // z-base32 alphabet.
    const input = "ybndrfg8ejkmcpqxot1uwisza345h769".*;
    // "zig base32" string in 5-bit segments.
    const mask = [_]u8{ 15, 9, 20, 22, 14, 8, 3, 2, 12, 5, 25, 22, 10, 12, 25, 18 };
    // "zig base32" in z-base32.
    const expected = "xjwsqedncf3skc31";

    const result = shuffle(16, input, mask);

    try std.testing.expectEqualStrings(expected, &result);
}
