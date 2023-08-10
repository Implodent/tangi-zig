const a = @import("../../ansi-term/main.zig");
const Files = @import("files.zig");

const Self = @This();

severity: Severity,
id: ?[]const u8 = null,
message: []const u8 = &.{},
labels: []const Label = &.{},
notes: []const []const u8 = &.{},

pub fn init(severity: Severity) Self {
    return .{ .severity = severity };
}

pub fn with_id(self: Self, id: []const u8) Self {
    var self_ = self;
    self_.id = id;
    return self_;
}

pub fn with_message(self: Self, message: []const u8) Self {
    var self_ = self;
    self_.message = message;
    return self_;
}

pub fn with_labels(self: Self, labels: []const Label) Self {
    var self_ = self;
    self_.labels = labels;
    return self_;
}

pub fn with_notes(self: Self, notes: []const []const u8) Self {
    var self_ = self;
    self_.notes = notes;
    return self_;
}

/// like a usize range, but denotes the span of the error, from character #`start` to character #`end`
pub const Span = struct { start: usize = 0, end: usize = 0 };

pub const Location = struct { line: usize, column: usize };

pub const Severity = enum {
    Bug,
    Error,
    Warning,
    Note,
    Help,

    pub fn color(self: Severity) a.style.Color {
        return switch (self) {
            .Bug => .{ .Black = {} },
            .Error => .{ .Red = {} },
            .Warning => .{ .Yellow = {} },
            .Note => .{ .Cyan = {} },
            .Help => .{ .Green = {} },
        };
    }
};

pub const Label = struct {
    style: Style,
    file_id: Files.FileId,
    range: Span,
    message: []const u8 = &.{},

    pub const Style = enum(u1) { primary = 1, secondary = 0 };

    pub fn init(style: Style, file_id: Files.FileId, range: Span) Label {
        return .{ .style = style, .file_id = file_id, .range = range };
    }

    pub fn primary(file_id: Files.FileId, range: Span) Label {
        return Label.init(.secondary, file_id, range);
    }

    pub fn secondary(file_id: Files.FileId, range: Span) Label {
        return Label.init(.primary, file_id, range);
    }

    pub fn with_message(self: Label, message: []const u8) Label {
        var self_ = self;
        self_.message = message;
        return self_;
    }
};
