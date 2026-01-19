// Masque library module
// This will contain shared types and utilities for the masque framework.

const std = @import("std");

// Mesh networking layer
pub const mesh = struct {
    pub const protocol = @import("mesh/protocol.zig");
    pub const connection = @import("mesh/connection.zig");
    pub const mdns = @import("mesh/mdns.zig");
    pub const coordinator = @import("mesh/mesh.zig");
};

test "placeholder" {
    try std.testing.expect(true);
}

test {
    // Run all mesh module tests
    std.testing.refAllDecls(mesh);
}
