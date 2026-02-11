/// Particle system for bursts, sparks, and confirm animations.
/// Lightweight: bounded array, no allocations.

const math = @import("math.zig");

pub const max_particles: usize = 64;

pub const Particle = struct {
    x: f32, // position (fractional cells)
    y: f32,
    vx: f32, // velocity (cells per tick)
    vy: f32,
    life: u16, // remaining ticks
    max_life: u16,
    char: u8, // display character
    color: [3]u8, // RGB color
};

pub const ParticleSystem = struct {
    particles: [max_particles]Particle = undefined,
    count: usize = 0,
    rng: math.Xorshift32 = math.Xorshift32.init(12345),

    pub fn tick(self: *ParticleSystem) void {
        var i: usize = 0;
        while (i < self.count) {
            self.particles[i].x += self.particles[i].vx;
            self.particles[i].y += self.particles[i].vy;
            self.particles[i].vy += 0.02; // gravity
            if (self.particles[i].life > 0) {
                self.particles[i].life -= 1;
            }
            if (self.particles[i].life == 0) {
                // Remove by swapping with last
                self.count -= 1;
                if (i < self.count) {
                    self.particles[i] = self.particles[self.count];
                }
            } else {
                i += 1;
            }
        }
    }

    pub fn spawn(self: *ParticleSystem, p: Particle) void {
        if (self.count >= max_particles) return;
        self.particles[self.count] = p;
        self.count += 1;
    }

    /// Spawn a burst of particles from a center point
    pub fn burst(self: *ParticleSystem, cx: f32, cy: f32, count: u8, color: [3]u8) void {
        for (0..count) |_| {
            const angle_idx: u8 = @truncate(self.rng.next());
            const speed = self.rng.float() * 0.5 + 0.1;
            const vx = @as(f32, @floatFromInt(math.cosI(angle_idx))) / 127.0 * speed;
            const vy = @as(f32, @floatFromInt(math.sinI(angle_idx))) / 127.0 * speed * 0.5; // half for aspect ratio
            const chars = ".*+#'";
            const char_idx = self.rng.bounded(@intCast(chars.len));
            self.spawn(.{
                .x = cx,
                .y = cy,
                .vx = vx,
                .vy = vy,
                .life = @intCast(self.rng.bounded(15) + 5),
                .max_life = 20,
                .char = chars[char_idx],
                .color = color,
            });
        }
    }

    /// Spawn rising sparks (for forge pattern)
    pub fn sparks(self: *ParticleSystem, cx: f32, base_y: f32, width: f32, color: [3]u8) void {
        for (0..2) |_| {
            const x = cx + (self.rng.float() - 0.5) * width;
            self.spawn(.{
                .x = x,
                .y = base_y,
                .vx = (self.rng.float() - 0.5) * 0.15,
                .vy = -(self.rng.float() * 0.3 + 0.1), // upward
                .life = @intCast(self.rng.bounded(12) + 4),
                .max_life = 16,
                .char = if (self.rng.bounded(3) == 0) '*' else '.',
                .color = color,
            });
        }
    }

    pub fn clear(self: *ParticleSystem) void {
        self.count = 0;
    }
};
