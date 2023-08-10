const s = @import("std");

pub fn getOr(comptime T: type, slice: []const T, idx: usize) ?T {
    if (slice.len <= idx) return null;
    return slice[idx];
}

pub fn isUtf8ChrBdr(byte: u8) bool {
    // This is bit magic equivalent to: b < 128 || b >= 192
    return @as(i8, @intCast(byte)) >= -0x40;
}

pub fn isCharBoundary(str: []const u8, idx: usize) bool {
    if (idx == 0) return true;

    return if (getOr(u8, str, idx)) |b| isUtf8ChrBdr(b) else idx == str.len;
}
pub fn binarySearch(comptime T: type, self: []const T, value: T) struct { idx: usize, found: bool } {
    // INVARIANTS:
    // - 0 <= left <= left + size = right <= self.len()
    // - f returns Less for everything in self[..left]
    // - f returns Greater for everything in self[right..]
    var size = self.len;
    var left: usize = 0;
    var right = size;
    while (left < right) {
        const mid = left + size / 2;

        const real = s.math.order(value, self[mid]);

        if (real == .lt) {
            left = mid + 1;
        } else if (real == .gt) {
            right = mid;
        } else {
            if (!(mid < self.len)) unreachable;

            return .{ .idx = mid, .found = true };
        }

        size = right - left;
    }

    if (!(left <= self.len)) unreachable;
    return .{ .idx = left, .found = false };
}

pub fn binarySearchBy(comptime T: type, self: []const T, state: T, comptime compare: fn (T, T) s.math.Order) struct { idx: usize, found: bool } {
    // INVARIANTS:
    // - 0 <= left <= left + size = right <= self.len()
    // - f returns Less for everything in self[..left]
    // - f returns Greater for everything in self[right..]
    var size = self.len;
    var left: usize = 0;
    var right = size;
    while (left < right) {
        const mid = left + size / 2;

        const real = compare(state, self[mid]);

        if (real == .lt) {
            left = mid + 1;
        } else if (real == .gt) {
            right = mid;
        } else {
            if (!(mid < self.len)) unreachable;

            return .{ .idx = mid, .found = true };
        }

        size = right - left;
    }

    if (!(left <= self.len)) unreachable;
    return .{ .idx = left, .found = false };
}
