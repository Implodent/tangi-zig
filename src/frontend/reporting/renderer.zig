const s = @import("std");
const str = @import("../../util/zig-string.zig");
const ansi = @import("../../ansi-term/main.zig");
const u = @import("../../util.zig");
const iter = @import("../../util/itertools.zig");

fn countDigits(n: usize) usize {
    var nf: f64 = @floatFromInt(n +| @as(usize, 1));
    return @intFromFloat(@ceil(@log10(nf)));
}

const Files = @import("files.zig");
const Diagnostic = @import("diagnostic.zig");

const SingleLabel = struct { style: Diagnostic.Label.Style, range: Diagnostic.Span, message: []const u8 };
const MultiLabel = union(enum) {
    Top: usize,
    Left,
    Bottom: struct { end: usize, message: []const u8 },
};

const MultiLabelTriple = struct { pos: usize, style: Diagnostic.Label.Style, label: MultiLabel };

fn cmpr(a: Diagnostic.Span, b: Diagnostic.Span) s.math.Order {
    return switch (s.math.order(a.start, b.start)) {
        .eq => s.math.order(a.end, b.end),
        else => |ord| ord,
    };
}

fn cmpl(a: SingleLabel, b: SingleLabel) s.math.Order {
    return cmpr(a.range, b.range);
}

const tab_width: usize = 4;
const start_context_lines: usize = 3;
const end_context_lines: usize = 1;
const before_label_lines: usize = 0;
const after_label_lines: usize = 0;
const trim_chars: []const u8 = "\n\r\x00";

const Styles = struct {
    const blue: ansi.style.Color = if (@import("builtin").os.tag == .windows) .{ .Cyan = {} } else .{ .Blue = {} };

    const line_number: ansi.style.Style = .{ .foreground = blue };
    const source_border: ansi.style.Style = .{ .foreground = blue };
    const note_bullet: ansi.style.Style = .{ .foreground = blue };
};

const Chars = struct {
    const snippet_start: []const u8 = "┌─";
    const source_border_left: []const u8 = "│";
    const source_border_left_break: []const u8 = "·";
    const note_bullet: u8 = '=';
    const single_primary_caret: u8 = '^';
    const single_secondary_caret: u8 = '-';
    const mutli_primary_caret_start: u8 = '^';
    const multi_primary_caret_end: u8 = '^';
    const multi_secondary_caret_start: u8 = '\'';
    const multi_secondary_caret_end: u8 = '\'';
    const multi_top_left: []const u8 = "╭";
    const multi_top: []const u8 = "─";
    const multi_bottom_left: []const u8 = "╰";
    const multi_bottom: []const u8 = "─";
    const multi_left: []const u8 = "│";
    const pointer_left: []const u8 = "│";
};

pub fn Renderer(comptime W: type) type {
    return struct {
        writer: W,
        last_style: ?ansi.style.Style = null,
        allocator: s.mem.Allocator,

        const Self = @This();

        const LabeledFile = struct {
            file_id: Files.FileId,
            start: usize,
            name: Files.Name,
            location: Diagnostic.Location,
            num_multi_labels: usize,
            lines: s.hash_map.AutoHashMap(usize, Line),
            max_label_style: Diagnostic.Label.Style,

            pub fn getOrInsertLine(self: *LabeledFile, allocator: s.mem.Allocator, line_index: usize, line_range: Diagnostic.Span, line_number: usize) !*Line {
                const result = try self.lines.getOrPut(line_index);
                if (!result.found_existing) {
                    result.value_ptr.* = .{ .range = line_range, .number = line_number, .single_labels = s.ArrayList(SingleLabel).init(allocator), .multi_labels = s.ArrayList(MultiLabelTriple).init(allocator), .must_render = false };
                }
                return result.value_ptr;
            }
        };

        const Line = struct {
            number: usize,
            range: Diagnostic.Span,
            single_labels: s.ArrayList(SingleLabel),
            multi_labels: s.ArrayList(MultiLabelTriple),
            must_render: bool,
        };

        pub fn render(self: *Self, diagnostic: Diagnostic, files: *const Files) !void {
            var labeled_files: s.ArrayList(LabeledFile) = s.ArrayList(LabeledFile).init(self.allocator);
            const allocator = self.allocator;
            var outer_padding: usize = 0;
            for (diagnostic.labels) |label| {
                const start_line_index = try files.lineIndex(label.file_id, label.range.start);
                const start_line_number = try files.lineNumber(label.file_id, start_line_index);
                const start_line_range = try files.lineRange(label.file_id, start_line_index);
                const end_line_index = try files.lineIndex(label.file_id, label.range.end);
                const end_line_number = try files.lineNumber(label.file_id, end_line_index);
                const end_line_range = try files.lineRange(label.file_id, end_line_index);

                outer_padding = @max(outer_padding, countDigits(start_line_number));
                outer_padding = @max(outer_padding, countDigits(end_line_number));

                var labeled_file: *LabeledFile = if ((for (labeled_files.items) |*file| {
                    if (label.file_id == file.file_id) break file;
                } else null)) |file| blk: {
                    if ((@intFromEnum(file.max_label_style) > @intFromEnum(label.style)) or (file.max_label_style == label.style and file.start > label.range.start)) {
                        file.start = label.range.start;
                        file.location = try files.location(label.file_id, label.range.start);
                        file.max_label_style = label.style;
                    }

                    break :blk file;
                } else blk: {
                    try labeled_files.append(.{ .file_id = label.file_id, .start = label.range.start, .name = try files.name(label.file_id), .location = try files.location(label.file_id, label.range.start), .num_multi_labels = 0, .lines = s.AutoHashMap(usize, Line).init(allocator), .max_label_style = label.style });
                    var last = labeled_files.getLast();
                    break :blk &last;
                };

                for (1..(before_label_lines + 1)) |offset| {
                    const result = @subWithOverflow(start_line_index, offset);
                    if (result.@"1" == 1) break;
                    const index = result.@"0";

                    const range = files.lineRange(label.file_id, index) catch break;
                    var line = try labeled_file.getOrInsertLine(allocator, index, range, start_line_number - offset, allocator);
                    line.must_render = true;
                }

                for (1..(after_label_lines + 1)) |offset| {
                    const index = end_line_index + offset;

                    const range = files.lineRange(label.file_id, index) catch break;
                    var line = try labeled_file.getOrInsertLine(allocator, index, range, end_line_number - offset);
                    line.must_render = true;
                }

                if (start_line_index == end_line_index) {
                    const label_start = label.range.start - start_line_range.start;
                    const label_end = @max(label.range.end - start_line_range.start, label_start + 1);
                    var line = try labeled_file.getOrInsertLine(allocator, start_line_index, start_line_range, start_line_number);
                    const index = (u.binarySearchBy(
                        SingleLabel,
                        line.single_labels.items,
                        SingleLabel{
                            .message = &.{},
                            .style = .primary,
                            .range = .{
                                .start = label_start,
                                .end = label_end,
                            },
                        },
                        cmpl,
                    )).idx;
                    try line.single_labels.insert(index, .{
                        .style = label.style,
                        .range = .{
                            .start = label_start,
                            .end = label_end,
                        },
                        .message = label.message,
                    });
                    line.must_render = true;
                } else {
                    const label_index = labeled_file.num_multi_labels;
                    labeled_file.num_multi_labels += 1;
                    const label_start = label.range.start - start_line_range.start;

                    const start_line = try labeled_file.getOrInsertLine(allocator, start_line_index, start_line_range, start_line_number);
                    try start_line.multi_labels.append(.{ .pos = label_index, .style = label.style, .label = .{ .Top = label_start } });

                    start_line.must_render = true;

                    for (start_line_index + 1..end_line_index) |line_index| {
                        const line_range = try files.lineRange(label.file_id, line_index);
                        const line_number = try files.lineNumber(label.file_id, line_index);

                        outer_padding = @max(outer_padding, countDigits(line_number));

                        var line = try labeled_file.getOrInsertLine(allocator, line_index, line_range, line_number);
                        try line.multi_labels.append(
                            .{
                                .pos = label_index,
                                .style = label.style,
                                .label = .{
                                    .Left = {},
                                },
                            },
                        );
                        line.must_render = line.must_render or ((line_index - start_line_index <= start_context_lines) or (end_line_index - line_index <= end_context_lines));
                    }

                    const label_end = label.range.end - end_line_range.start;

                    var end_line = try labeled_file.getOrInsertLine(
                        allocator,
                        end_line_index,
                        end_line_range,
                        end_line_number,
                    );
                    try end_line.multi_labels.append(
                        .{
                            .pos = label_index,
                            .style = label.style,
                            .label = .{
                                .Bottom = .{
                                    .end = label_end,
                                    .message = label.message,
                                },
                            },
                        },
                    );
                    end_line.must_render = true;
                }
            }
            try self.render_header(&diagnostic);
            for (labeled_files.items, 0..) |labeled_file, idx| {
                const is_end = idx == labeled_files.items.len - 1;
                _ = is_end;
                const source = try files.source(labeled_file.file_id);
                if (labeled_file.lines.count() != 0) {
                    try self.render_snippet_start(outer_padding, .{ .name = labeled_file.name, .location = labeled_file.location });
                    try self.render_snippet_empty(outer_padding, diagnostic.severity, labeled_file.num_multi_labels, &.{});
                }

                var lines = iter.peekable(s.AutoHashMap(usize, Line).Entry, labeled_file.lines.iterator());

                while (lines.next()) |line_entry| {
                    const line_index: usize = line_entry.key_ptr.*;
                    _ = line_index;
                    const line: *Line = line_entry.value_ptr;
                    try self.render_snippet_source(outer_padding, line.number, source[line.range.start..line.range.end], diagnostic.severity, line.single_labels.items, labeled_file.num_multi_labels, line.multi_labels.items);
                }
            }
        }

        fn write(self: *Self, comptime fmt: []const u8, args: anytype) !void {
            try s.fmt.format(self.writer, fmt, args);
        }
        fn writeln(self: *Self) !void {
            try self.writer.writeAll("\n");
        }

        fn set_style(self: *Self, style: ansi.style.Style) !void {
            try ansi.format.updateStyle(self.writer, style, self.last_style);
            self.last_style = style;
        }

        fn reset_style(self: *Self) !void {
            try ansi.format.resetStyle(self.writer);
            self.last_style = null;
        }

        fn render_header(self: *Self, diagnostic: *const Diagnostic) !void {
            try self.set_style(.{ .background = diagnostic.severity.color() });
            if (diagnostic.id) |id| try self.write(" {s} {s} ", .{ @tagName(diagnostic.severity), id }) else try self.write(" {s} ", .{@tagName(diagnostic.severity)});
            try self.reset_style();
            try self.write(": {s}", .{diagnostic.message});
            try self.writeln();
        }

        fn render_snippet_start(self: *Self, outer_padding: usize, locus: Locus) !void {
            try self.outer_gutter(outer_padding);
            try self.set_style(Styles.source_border);
            try self.write("{s}", .{Chars.snippet_start});
            try self.reset_style();
            try self.write(" ", .{});
            try self.snippet_locus(locus);
            try self.writeln();
        }

        fn render_snippet_empty(self: *Self, outer_padding: usize, severity: Diagnostic.Severity, num_multi_labels: usize, multi_labels: []const MultiLabelTriple) !void {
            try self.outer_gutter(outer_padding);
            try self.border_left();
            try self.inner_gutter(severity, num_multi_labels, multi_labels);
            try self.writeln();
        }

        fn border_left(self: *Self) !void {
            try self.set_style(Styles.source_border);
            try self.write("{s}", Chars.source_border_left);
            try self.reset_style();
        }

        fn inner_gutter_space(self: *Self) !void {
            try self.write("  ", .{});
        }

        fn inner_gutter(
            self: *Self,
            severity: Diagnostic.Severity,
            num_multi_labels: usize,
            multi_labels: []const MultiLabelTriple,
        ) !void {
            var index: usize = 0;
            for (0..num_multi_labels) |label_column| {
                const real = u.getOr(MultiLabelTriple, multi_labels, index);
                if (if (real) |triple| blk: {
                    if (triple.pos == label_column) {
                        switch (triple.label) {
                            .left, .bottom => {
                                try self.label_multi_left(severity, triple.style, null);
                            },
                            .top => {
                                try self.inner_gutter_space();
                            },
                        }
                        break :blk true;
                    } else {
                        break :blk false;
                    }
                } else false) index = s.math.clamp(index, 0, multi_labels.len - 1);
            }
        }

        fn render_snippet_source(
            self: *Self,
            outer_padding: usize,
            line_number: usize,
            _source: []const u8,
            severity: Diagnostic.Severity,
            single_labels: []const SingleLabel,
            num_multi_labels: usize,
            multi_labels: []const MultiLabelTriple,
        ) !void {
            _ = single_labels;
            const source = s.mem.trimRight(_source, trim_chars);
            {
                try self.outer_gutter_number(line_number, outer_padding);
                try self.border_left();

                var multi_labels_iter = iter.peekable(iter.slice(MultiLabelTriple, multi_labels));
                for (0..num_multi_labels) |label_column| {
                    const result: ?*const MultiLabelTriple = multi_labels_iter.peek();
                    if (result) |*peeked| {
                        if (peeked.pos == label_column) {
                            switch (peeked.label) {
                                .top => |start| {
                                    if (start <= source.len - s.mem.trimLeft(u8, source, " \n\r").len) {
                                        try self.label_multi_top_left(severity, peeked.style);
                                    } else {
                                        try self.inner_gutter_space();
                                    }
                                },
                                .left, .bottom => try self.label_multi_left(severity, peeked.style, null),
                            }
                        }
                    }
                }
            }
        }
        fn snippet_locus(self: *Self, locus: Locus) !void {
            try self.write("{s}:{d}:{d}", .{
                locus.name,
                locus.location.line,
                locus.location.column,
            });
        }

        fn outer_gutter(self: *Self, outer_padding: usize) !void {
            // write!(self, "{space: >width$} ", space = "", width = outer_padding)?;
            try repeat(self.writer, " ", outer_padding);
        }

        fn outer_gutter_number(self: *Self, line_number: usize, outer_padding: usize) !void {
            self.set_style(Styles.line_number);
            try self.write("{d}", .{line_number});
            try repeat(self.writer, " ", outer_padding);
        }
    };
}

pub const Locus = struct { name: []const u8, location: Diagnostic.Location };

pub fn repeat(writer: anytype, value: []const u8, times: usize) !void {
    for (0..times) |_| {
        try writer.writeAll(value);
    }
}
