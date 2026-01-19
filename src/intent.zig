// Intent pattern matching for masques
// Implements glob-style matching for intent qualification
//
// Patterns:
//   "implement *"  - matches "implement parser", "implement tests"
//   "delete *"     - matches "delete file", "delete database"
//   "review code"  - exact match only
//
// Rules:
//   1. Denied patterns take precedence over allowed
//   2. If no patterns match, intent is denied by default
//   3. Empty pattern list means nothing is allowed/denied

const std = @import("std");

/// Check if an intent is qualified (allowed) given the masque's patterns
pub fn qualifyIntent(
    allowed: []const []const u8,
    denied: []const []const u8,
    intent: []const u8,
) bool {
    // First check denied patterns - they take precedence
    for (denied) |pattern| {
        if (matchGlob(pattern, intent)) {
            return false;
        }
    }

    // Then check allowed patterns
    for (allowed) |pattern| {
        if (matchGlob(pattern, intent)) {
            return true;
        }
    }

    // Default: denied
    return false;
}

/// Match a glob pattern against a string
/// Supports:
///   * - matches any sequence of characters
///   ? - matches any single character
pub fn matchGlob(pattern: []const u8, str: []const u8) bool {
    return matchGlobRecursive(pattern, str, 0, 0);
}

fn matchGlobRecursive(pattern: []const u8, str: []const u8, pi: uptr, si: utptr) bool {
    const pi_usize: usize = @intCast(pi);
    const si_usize: usize = @intCast(si);

    // Base case: both pattern and string exhausted
    if (pi_usize >= pattern.len and si_usize >= str.len) {
        return true;
    }

    // Pattern exhausted but string remains
    if (pi_usize >= pattern.len) {
        return false;
    }

    const pc = pattern[pi_usize];

    // Handle '*' - matches zero or more characters
    if (pc == '*') {
        // Try matching zero characters (skip the *)
        if (matchGlobRecursive(pattern, str, pi + 1, si)) {
            return true;
        }
        // Try matching one or more characters (consume one char from str)
        if (si_usize < str.len) {
            return matchGlobRecursive(pattern, str, pi, si + 1);
        }
        return false;
    }

    // String exhausted but pattern has more (non-* chars)
    if (si_usize >= str.len) {
        return false;
    }

    const sc = str[si_usize];

    // Handle '?' - matches any single character
    if (pc == '?') {
        return matchGlobRecursive(pattern, str, pi + 1, si + 1);
    }

    // Literal character match (case-insensitive)
    if (std.ascii.toLower(pc) == std.ascii.toLower(sc)) {
        return matchGlobRecursive(pattern, str, pi + 1, si + 1);
    }

    return false;
}

// Use isize for recursive index arithmetic
const uptr = isize;
const utptr = isize;

test "glob exact match" {
    try std.testing.expect(matchGlob("hello", "hello"));
    try std.testing.expect(!matchGlob("hello", "world"));
    try std.testing.expect(!matchGlob("hello", "hello world"));
}

test "glob wildcard *" {
    try std.testing.expect(matchGlob("implement *", "implement parser"));
    try std.testing.expect(matchGlob("implement *", "implement tests"));
    try std.testing.expect(matchGlob("implement *", "implement "));
    try std.testing.expect(!matchGlob("implement *", "delete parser"));

    try std.testing.expect(matchGlob("* code", "review code"));
    try std.testing.expect(matchGlob("* code", "delete code"));

    try std.testing.expect(matchGlob("*", "anything"));
    try std.testing.expect(matchGlob("*", ""));
}

test "glob wildcard ?" {
    try std.testing.expect(matchGlob("te?t", "test"));
    try std.testing.expect(matchGlob("te?t", "text"));
    try std.testing.expect(!matchGlob("te?t", "tent"));
    try std.testing.expect(!matchGlob("te?t", "teast"));
}

test "glob case insensitive" {
    try std.testing.expect(matchGlob("IMPLEMENT *", "implement parser"));
    try std.testing.expect(matchGlob("implement *", "IMPLEMENT PARSER"));
}

test "qualify intent" {
    const allowed = &[_][]const u8{ "implement *", "test *", "review *" };
    const denied = &[_][]const u8{ "delete *", "rush *" };

    // Allowed intents
    try std.testing.expect(qualifyIntent(allowed, denied, "implement parser"));
    try std.testing.expect(qualifyIntent(allowed, denied, "test feature"));
    try std.testing.expect(qualifyIntent(allowed, denied, "review code"));

    // Denied intents
    try std.testing.expect(!qualifyIntent(allowed, denied, "delete database"));
    try std.testing.expect(!qualifyIntent(allowed, denied, "rush deployment"));

    // Not in either list - denied by default
    try std.testing.expect(!qualifyIntent(allowed, denied, "deploy production"));
}

test "deny takes precedence" {
    const allowed = &[_][]const u8{"*"}; // Allow everything
    const denied = &[_][]const u8{"delete *"}; // But deny delete

    try std.testing.expect(qualifyIntent(allowed, denied, "implement parser"));
    try std.testing.expect(!qualifyIntent(allowed, denied, "delete files"));
}
