/// Math utilities: sin/cos LUT, lerp, hash, PRNG
/// No runtime trig — all lookups from precomputed 256-entry tables.

const std = @import("std");

/// 256-entry sin lookup table, values scaled to [-127, 127] (i8 range)
pub const sin_lut: [256]i8 = blk: {
    @setEvalBranchQuota(10000);
    var table: [256]i8 = undefined;
    for (0..256) |i| {
        const angle: f64 = @as(f64, @floatFromInt(i)) * (2.0 * std.math.pi / 256.0);
        const val: f64 = @sin(angle) * 127.0;
        table[i] = @intFromFloat(std.math.clamp(val, -127.0, 127.0));
    }
    break :blk table;
};

/// Sin from phase [0..255], returns [-127..127]
pub fn sinI(phase: u8) i8 {
    return sin_lut[phase];
}

/// Cos from phase [0..255], returns [-127..127]
pub fn cosI(phase: u8) i8 {
    return sin_lut[phase +% 64]; // cos = sin + 90 degrees
}

/// Sin from phase [0..255], returns [0.0..1.0] (half-wave, clamped positive)
pub fn sinF(phase: u8) f32 {
    const v: f32 = @as(f32, @floatFromInt(sin_lut[phase])) / 127.0;
    return @max(0.0, v);
}

/// Sin from phase [0..255], returns [-1.0..1.0] (full wave)
pub fn sinFull(phase: u8) f32 {
    return @as(f32, @floatFromInt(sin_lut[phase])) / 127.0;
}

/// Linear interpolation
pub fn lerp(a: f32, b: f32, t: f32) f32 {
    return a + (b - a) * std.math.clamp(t, 0.0, 1.0);
}

/// Linear interpolation for u8
pub fn lerpU8(a: u8, b: u8, t: f32) u8 {
    const af: f32 = @floatFromInt(a);
    const bf: f32 = @floatFromInt(b);
    return @intFromFloat(std.math.clamp(lerp(af, bf, t), 0.0, 255.0));
}

/// FNV-1a hash for deriving deterministic seeds from names
pub fn hash(name: []const u8) u32 {
    var h: u32 = 2166136261;
    for (name) |byte| {
        h ^= @as(u32, byte);
        h *%= 16777619;
    }
    return h;
}

/// Xorshift32 PRNG — fast, deterministic, good enough for visual effects
pub const Xorshift32 = struct {
    state: u32,

    pub fn init(seed: u32) Xorshift32 {
        return .{ .state = if (seed == 0) 1 else seed };
    }

    pub fn next(self: *Xorshift32) u32 {
        var x = self.state;
        x ^= x << 13;
        x ^= x >> 17;
        x ^= x << 5;
        self.state = x;
        return x;
    }

    /// Returns a value in [0, max)
    pub fn bounded(self: *Xorshift32, max: u32) u32 {
        if (max == 0) return 0;
        return self.next() % max;
    }

    /// Returns a float in [0.0, 1.0)
    pub fn float(self: *Xorshift32) f32 {
        return @as(f32, @floatFromInt(self.next() & 0xFFFF)) / 65536.0;
    }
};
