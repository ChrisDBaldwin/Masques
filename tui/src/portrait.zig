/// Portrait: animated ASCII art for each masque.
/// Each portrait has a cell buffer, an animation state machine,
/// and a pattern generator determined by domain.

const std = @import("std");
const vaxis = @import("vaxis");
const math = @import("math.zig");
const particle = @import("particle.zig");
const color_mod = @import("color.zig");
const gradient = @import("gradient.zig");
const patterns = @import("patterns/mod.zig");

/// Maximum portrait dimensions
pub const thumb_w: usize = 13;
pub const thumb_h: usize = 7;
pub const large_w: usize = 27;
pub const large_h: usize = 15;
pub const max_w: usize = large_w;
pub const max_h: usize = large_h;

pub const PortraitCell = struct {
    char: u8 = ' ',
    fg: [3]u8 = .{ 170, 170, 170 },
    bg: [3]u8 = .{ 0, 0, 0 },
    bold: bool = false,
};

pub const AnimState = enum {
    idle,
    selecting, // ramping up (10 ticks)
    selected, // full intensity
    deselecting, // ramping down (10 ticks)
    confirming, // flash → shatter → reform (15 ticks)
};

pub const Portrait = struct {
    cells: [max_h][max_w]PortraitCell = undefined,
    width: usize = thumb_w,
    height: usize = thumb_h,
    state: AnimState = .idle,
    tick: u32 = 0,
    state_tick: u16 = 0, // ticks in current state
    seed: u32,
    domain_category: gradient.DomainCategory,
    primary_color: [3]u8,
    dim_color: [3]u8,
    bright_color: [3]u8,
    particles: particle.ParticleSystem = .{},
    pattern: patterns.PatternFn,

    pub fn init(name: []const u8, domain: []const u8) Portrait {
        const seed = math.hash(name);
        const colors = color_mod.domainColors(domain);
        const cat = gradient.DomainCategory.fromDomain(domain);
        var p = Portrait{
            .seed = seed,
            .domain_category = cat,
            .primary_color = colors.primary,
            .dim_color = colors.dim,
            .bright_color = colors.bright,
            .pattern = patterns.getPattern(cat),
        };
        // Initialize cells to blank
        for (0..max_h) |y| {
            for (0..max_w) |x| {
                p.cells[y][x] = .{};
            }
        }
        return p;
    }

    pub fn setSize(self: *Portrait, w: usize, h: usize) void {
        self.width = @min(w, max_w);
        self.height = @min(h, max_h);
    }

    pub fn setState(self: *Portrait, new_state: AnimState) void {
        if (self.state == new_state) return;
        self.state = new_state;
        self.state_tick = 0;
        if (new_state == .confirming) {
            // Burst particles on confirm
            const cx: f32 = @as(f32, @floatFromInt(self.width)) / 2.0;
            const cy: f32 = @as(f32, @floatFromInt(self.height)) / 2.0;
            self.particles.burst(cx, cy, 20, self.bright_color);
        }
    }

    /// Compute intensity based on animation state
    pub fn intensity(self: *const Portrait) f32 {
        return switch (self.state) {
            .idle => {
                // Breathing: oscillate density ±8% at 0.75Hz
                // At 30fps, 0.75Hz = phase advances ~6.4/tick
                // We use tick * 6 to get roughly 0.7Hz
                const phase: u8 = @truncate(self.tick *% 6);
                const breath = math.sinFull(phase);
                return 0.5 + breath * 0.08;
            },
            .selecting => {
                // Ramp from idle to full over 10 ticks
                const t = @min(@as(f32, @floatFromInt(self.state_tick)) / 10.0, 1.0);
                return math.lerp(0.5, 1.0, t);
            },
            .selected => 1.0,
            .deselecting => {
                const t = @min(@as(f32, @floatFromInt(self.state_tick)) / 10.0, 1.0);
                return math.lerp(1.0, 0.5, t);
            },
            .confirming => {
                // Flash → shatter → reform over 15 ticks
                if (self.state_tick < 5) return 1.5; // flash: extra bright
                if (self.state_tick < 10) return 0.3; // shatter: dim
                return math.lerp(0.3, 1.0, @as(f32, @floatFromInt(self.state_tick - 10)) / 5.0);
            },
        };
    }

    /// Update one animation frame
    pub fn update(self: *Portrait) void {
        self.tick +%= 1;
        self.state_tick +|= 1;

        // Auto-transition from confirming back to selected
        if (self.state == .confirming and self.state_tick >= 15) {
            self.state = .selected;
            self.state_tick = 0;
        }
        // Auto-transition from deselecting back to idle
        if (self.state == .deselecting and self.state_tick >= 10) {
            self.state = .idle;
            self.state_tick = 0;
        }

        // Run the pattern generator
        const ctx = patterns.PatternContext{
            .width = self.width,
            .height = self.height,
            .tick = self.tick,
            .seed = self.seed,
            .intensity = self.intensity(),
            .primary_color = self.primary_color,
            .dim_color = self.dim_color,
            .bright_color = self.bright_color,
            .domain_category = self.domain_category,
        };
        self.pattern(&self.cells, ctx);

        // Update particles
        self.particles.tick();

        // Render particles onto cell buffer
        for (0..self.particles.count) |i| {
            const p = &self.particles.particles[i];
            const px: isize = @intFromFloat(p.x);
            const py: isize = @intFromFloat(p.y);
            if (px >= 0 and py >= 0) {
                const ux: usize = @intCast(px);
                const uy: usize = @intCast(py);
                if (ux < self.width and uy < self.height) {
                    // Particle intensity fades with life
                    const life_ratio = @as(f32, @floatFromInt(p.life)) / @as(f32, @floatFromInt(p.max_life));
                    if (life_ratio > 0.3) {
                        self.cells[uy][ux] = .{
                            .char = p.char,
                            .fg = p.color,
                            .bold = life_ratio > 0.6,
                        };
                    }
                }
            }
        }

        // Background tint: cells with content get a dim domain-colored bg
        {
            const bg_intensity: f32 = switch (self.state) {
                .idle => 0.08,
                .selecting => 0.12,
                .selected => 0.15,
                .deselecting => 0.08,
                .confirming => if (self.state_tick < 5) 0.3 else 0.1,
            };
            for (0..self.height) |y| {
                for (0..self.width) |x| {
                    if (self.cells[y][x].char != ' ') {
                        self.cells[y][x].bg = color_mod.dimColor(self.primary_color, bg_intensity);
                    } else {
                        // Even empty cells get a very subtle tint for depth
                        self.cells[y][x].bg = color_mod.dimColor(self.primary_color, bg_intensity * 0.3);
                    }
                }
            }
        }

        // Sparkle: 2% of cells get a random bright dot in idle
        if (self.state == .idle) {
            var rng = math.Xorshift32.init(self.seed +% self.tick);
            for (0..self.height) |y| {
                for (0..self.width) |x| {
                    if (rng.bounded(100) < 2) {
                        self.cells[y][x].fg = self.bright_color;
                        self.cells[y][x].bold = true;
                    }
                }
            }
        }
    }

    /// Static lookup table: index by ASCII byte → single-char string slice.
    /// Prevents dangling pointers from stack-local grapheme buffers.
    pub const ascii_table: [128][1]u8 = blk: {
        var t: [128][1]u8 = undefined;
        for (0..128) |i| {
            t[i] = .{@intCast(i)};
        }
        break :blk t;
    };

    /// Render portrait cells into a vaxis window
    pub fn render(self: *const Portrait, win: vaxis.Window) void {
        for (0..@min(self.height, win.height)) |y| {
            for (0..@min(self.width, win.width)) |x| {
                const pc = self.cells[y][x];
                const idx: usize = if (pc.char < 128) pc.char else ' ';
                const bg_style: vaxis.Color = if (pc.bg[0] > 0 or pc.bg[1] > 0 or pc.bg[2] > 0)
                    .{ .rgb = pc.bg }
                else
                    .default;
                win.writeCell(@intCast(x), @intCast(y), .{
                    .char = .{ .grapheme = &ascii_table[idx], .width = 1 },
                    .style = .{
                        .fg = .{ .rgb = pc.fg },
                        .bg = bg_style,
                        .bold = pc.bold,
                    },
                });
            }
        }
    }
};
