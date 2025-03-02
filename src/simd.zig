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

    if (cpu.arch.isWasm() and Target.wasm.featureSetHas(cpu.features, .simd128)) {
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

inline fn shuffle32(comptime size: usize, input: [32]u8, mask: [size]u8) [size]u8 {
    const mask_16: @Vector(16, u8) = mask ++ [_]u8{0} ** (16 - size);
    const overflow_mask: @Vector(16, u8) = @splat(0xF);
    const empty: @Vector(16, u8) = @splat(0x80);

    const hi_lo_mask = mask_16 > overflow_mask;

    const hi_mask = @select(u8, hi_lo_mask, mask_16 & overflow_mask, empty);
    const lo_mask = @select(u8, hi_lo_mask, empty, mask_16);

    const result: [16]u8 = shuffle16(input[16..32].*, hi_mask) | shuffle16(input[0..16].*, lo_mask);

    return result[0..size].*;
}

inline fn fallback(comptime size: usize, input: [32]u8, mask: [size]u8) [size]u8 {
    var output: [size]u8 = undefined;

    inline for (&output, 0..) |*char, index| char.* = input[mask[index]];

    return output;
}

pub const shuffle = switch (simd_type) {
    .avx, .neon, .wasm => shuffle32,
    .no_simd => fallback,
};
