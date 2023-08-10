const s = @import("std");
const d = @import("diagnostic.zig");
const Span = d.Span;
const Location = d.Location;
const u = @import("../../util.zig");

files: []const File,

pub const File = struct {
    name: Name,
    source: Source,
    line_starts: []const usize,

    pub fn init(file_name: Name, file_source: Source, allocator: s.mem.Allocator) !File {
        return .{ .name = file_name, .source = file_source, .line_starts = try lineStarts(file_source).collect(allocator) };
    }

    pub fn lineStart(self: *const File, line_index: usize) !usize {
        return switch (s.math.order(line_index, self.line_starts.len)) {
            .lt => self.line_starts[line_index],
            .eq => self.source.len,
            .gt => return Error.LineTooLarge,
        };
    }
};
pub const Error = error{ FileMissing, LineTooLarge };

pub const FileId = usize;
pub const Name = []const u8;
pub const Source = []const u8;

const Self = @This();

fn get(self: *const Self, id: FileId) !File {
    return u.getOr(File, self.files, id) orelse Error.FileMissing;
}

pub fn name(self: *const Self, id: FileId) !Name {
    return (try self.get(id)).name;
}

pub fn source(self: *const Self, id: FileId) !Source {
    return (try self.get(id)).source;
}

pub fn lineIndex(self: *const Self, id: FileId, byte_index: usize) !usize {
    const find = u.binarySearch(usize, (try self.get(id)).line_starts, byte_index);
    return if (find.found) find.idx else find.idx -| 1;
}

pub fn lineNumber(self: *const Self, id: FileId, line_index: usize) !usize {
    _ = id;
    _ = self;
    return line_index + 1;
}

pub fn columnNumber(self: *const Self, id: FileId, line_index: usize, byte_index: usize) !usize {
    const src = try self.source(id);
    const line_range = try self.lineRange(id, line_index);
    const column_index = columnIndex(src, line_range, byte_index);

    return column_index + 1;
}

pub fn location(self: *const Self, id: FileId, byte_index: usize) !Location {
    const line_index = try self.lineIndex(id, byte_index);

    return .{ .line = try self.lineNumber(id, line_index), .column = try self.columnNumber(id, line_index, byte_index) };
}

pub fn lineRange(self: *const Self, id: FileId, line_index: usize) !Span {
    const file = try self.get(id);
    const line_start = try file.lineStart(line_index);
    const next_line_start = try file.lineStart(line_index + 1);

    return .{ .start = line_start, .end = next_line_start };
}

pub const LineStarts = struct {
    src: Source,
    index: usize = 0,
    stopped: bool = false,

    const scalar = '\n';

    pub fn next(self: *LineStarts) ?usize {
        const index = self.index;
        if (index >= self.src.len - 1) return null;
        // find next pos. if not null, add pos, return previous.
        if (s.mem.indexOfScalarPos(u8, self.src, index, scalar)) |next_index| {
            self.index += next_index;
        } else
        // if stopped, return null and end.
        if (self.stopped) return null
        // if not stopped, stop at next iteration.
        else self.stopped = true;

        return index;
    }

    pub fn collect(self: LineStarts, allocator: s.mem.Allocator) ![]const usize {
        var this = self;
        var ar = s.ArrayList(usize).init(allocator);
        while (this.next()) |idx| try ar.append(idx);
        return ar.toOwnedSlice();
    }
};

pub fn lineStarts(src: Source) LineStarts {
    return .{ .src = src };
}

pub fn columnIndex(src: Source, line_range: Span, byte_index: usize) usize {
    const end_index = @min(byte_index, @min(line_range.end, src.len));

    var result: usize = 0;

    if (line_range.start > end_index) unreachable;

    for (line_range.start..end_index) |byte_idx| {
        if (u.isCharBoundary(src, byte_idx)) result += 1;
    }

    return result;
}
