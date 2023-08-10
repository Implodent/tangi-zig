const s = @import("std");
const Lexer = @import("frontend/lexer.zig");
const Parser = @import("frontend/parser.zig");
const r = @import("frontend/reporting.zig");

pub fn main() !void {
    var gpa = s.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() != .ok) s.debug.panic("leakzs !", .{});
    var arena = s.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();
    const alloc = arena.allocator();
    var args = s.process.args();
    _ = args.next();
    const file = args.next() orelse return error.no_file;
    const fd = (try s.fs.cwd().openFile(file, .{}));
    const code = try fd.readToEndAlloc(alloc, @truncate(try fd.getEndPos()));
    var reporting = r.Reporting{
        .files = r.Files{
            .files = &[_]r.Files.File{
                try r.Files.File.init(file, code, alloc),
            },
        },
        .allocator = alloc,
    };
    var parser = Parser{ .lexer = Lexer.init(code), .allocator = alloc, .file_id = 0, .reporter = &reporting };
    const parsed = try parser.parse_reporting() orelse return;
    s.log.debug("{}", .{parsed});
}
