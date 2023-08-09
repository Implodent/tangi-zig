const s = @import("std");
const ansi = @import("../ansi-term/main.zig");

const Styled = struct {
    text: []const u8,
    style: ansi.style.Style,

    pub fn print(self: Styled, allocator: s.mem.Allocator) !s.ArrayList(u8) {
        var arrl = s.ArrayList(u8).init(allocator);
        try ansi.format.updateStyle(arrl.writer(), self.style, null);
        try arrl.appendSlice(self.text);
        allocator.free(self.text);
        return arrl;
    }
    pub fn printMul(array: []const Styled, allocator: s.mem.Allocator) !s.ArrayList(u8) {
        var arrl = s.ArrayList(u8).init(allocator);
        var prev_style: ?ansi.style.Style = null;
        var writer = arrl.writer();
        defer for (array) |styled| {
            allocator.free(styled.text);
        };
        for (array) |styled| {
            try ansi.format.updateStyle(writer, styled.style, prev_style);
            prev_style = styled.style;
            try arrl.appendSlice(styled.text);
        }
        return arrl;
    }
};

pub const Level = enum {
    bug,
    err,
    warn,
    note,

    fn color(self: Level) ansi.style.Color {
        return switch (self) {
            .bug => .{ .Black = {} },
            .err => .{ .Red = {} },
            .warn => .{ .Yellow = {} },
            .note => .{ .Cyan = {} },
        };
    }

    pub fn print(self: Level, id: ?[]const u8, text: []const u8, allocator: s.mem.Allocator) ![]const Styled {
        // err[e1010] weiurwiehr
        const name = @tagName(self);
        const left = Styled{
            // err[id] or [err]
            .text = if (id) |identifier| try s.fmt.allocPrint(allocator, "{s}[{s}]", .{ name, identifier }) else try s.fmt.allocPrint(allocator, "[{s}]", .{name}),
            .style = ansi.style.Style{ .background = self.color() },
        };
        return &[2]Styled{ left, Styled{ .style = .{}, .text = try allocator.dupe(u8, text) } };
    }
};
pub const Reporting = struct {
    files: []const *const []const u8,
    allocator: s.mem.Allocator,
    pub fn report(self: *Reporting, diagnostic: Diagnostic) !void {
        const stderr = s.io.getStdErr().writer();
        defer diagnostic.deinit(self.allocator);
        try diagnostic.write(stderr, self.allocator);
    }
};

pub const Diagnostic = struct {
    file_id: usize,
    span: Span,
    level: Level,
    id: ?[]const u8,
    text: []const u8,

    pub fn write(self: Diagnostic, writer: anytype, allocator: s.mem.Allocator) !void {
        const mul = try Styled.printMul(try self.level.print(self.id, self.text, allocator), allocator);
        defer mul.deinit();
        _ = try writer.write(mul.items);
    }

    pub fn deinit(self: Diagnostic, allocator: s.mem.Allocator) void {
        allocator.free(self.text);
    }
};
/// like a usize range, but denotes the span of the error, from character #`start` to character #`end`
pub const Span = struct { start: usize, end: usize };
