const s = @import("std");
const Lexer = @import("frontend/lexer.zig");
const Parser = @import("frontend/parser.zig");
const r = @import("frontend/reporting.zig");

pub fn main() !void {
    var gpa = s.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() != .ok) unreachable;
    const alloc = gpa.allocator();
    var args = s.process.args();
    _ = args.next();
    const file = args.next() orelse return error.no_file;
    const fd = (try s.fs.cwd().openFile(file, .{}));
    const code = try fd.readToEndAlloc(alloc, @truncate(try fd.getEndPos()));
    defer alloc.free(code);
    var reporting = r.Reporting{ .files = &[1]*const []const u8{&code}, .allocator = alloc };
    var parser = Parser{ .lexer = Lexer.init(code), .allocator = alloc, .file_id = 0, .reporter = &reporting };
    const parsed = try parser.parse_reporting() orelse return error.invalid_ast;
    defer alloc.free(parsed.items);
    s.log.debug("{}", .{parsed});
}
