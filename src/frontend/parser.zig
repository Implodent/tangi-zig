const Lexer = @import("lexer.zig");
const s = @import("std");
const r = @import("reporting.zig");
const a = @import("../Ast.zig");
const e = @import("errors.zig");

const Self = @This();

lexer: Lexer,
allocator: s.mem.Allocator,
reporter: *r.Reporting,
file_id: usize,

pub const Error = error{ invalid_token, eof, expected_type, duplicate_param_name };

fn UnionTagToFieldType(comptime U: type, comptime tag: @typeInfo(U).Union.tag_type.?) type {
    const u = @typeInfo(U).Union;
    const tag_name = @tagName(tag);
    inline for (u.fields) |field| {
        if (s.mem.eql(u8, field.name, tag_name)) return field.type;
    }
    @compileError("not found???");
}

inline fn ask(
    self: *Self,
    comptime token: @typeInfo(Lexer.Token).Union.tag_type.?,
) !UnionTagToFieldType(Lexer.Token, token) {
    self.lexer.expectation = token;
    const next_token = self.lexer.next_token();
    if (next_token == token) {
        return @field(next_token, @tagName(token));
    }
    return Error.invalid_token;
}

pub fn parse_reporting(self: *Self) !?a.File {
    return self.ask_file() catch |err| {
        try self.reporter.report(switch (err) {
            error.invalid_token => r.Diagnostic.init(.Error).with_id(e.InvalidToken).with_message(try s.fmt.allocPrint(self.allocator, "invalid token {s}, expected {?s}", .{ @tagName(self.lexer.last_token), if (self.lexer.expectation) |expectation| @tagName(expectation) else null })).with_labels(&[_]r.Diagnostic.Label{r.Diagnostic.Label.primary(self.file_id, self.lexer.span()).with_message("here")}),
            // error.expected_type => r.Diagnostic{ .file_id = self.file_id, .id = e.ExpectedType, .level = .err, .span = self.lexer.span(), .text = "Expected a type" },
            else => r.Diagnostic.init(.Bug).with_id("EFUCKYOU").with_message("h"),
        });
        return null;
    };
}

pub fn ask_file(self: *Self) !a.File {
    var items = s.ArrayList(a.Item).init(self.allocator);
    defer items.deinit();
    while (true) {
        try items.append(try self.ask_item());
        if (self.lexer.last_token == .eof) {
            break;
        }
    }
    return .{ .items = try items.toOwnedSlice() };
}

fn ask_item(self: *Self) !a.Item {
    var vis: a.Visibility = .inherited;
    var state: enum { start, func } = .start;
    while (true) {
        switch (self.lexer.next_token()) {
            .kw_pub => if (state == .start) {
                vis = .public;
            } else return error.invalid_token,
            .kw_fn => return .{ .Fn = try self.ask_fn(true, vis) },
            else => return error.invalid_token,
        }
    }
}

fn ask_fn_param(self: *Self) !struct { name: []const u8, param: a.Item.Fn.Param } {
    const name = try self.ask(.ident);
    try self.ask(.colon);
    const ty = try self.ask_type();
    return .{
        .name = name,
        .param = .{ .ty = ty },
    };
}

fn ask_fn(self: *Self, already_consumed_fn_token: bool, vis: a.Visibility) !a.Item.Fn {
    if (!already_consumed_fn_token) try self.ask(.kw_fn);
    const name = try self.ask(.ident);
    var params = s.StringHashMap(a.Item.Fn.Param).init(self.allocator);
    try self.ask(.lparen);
    var just_started = true;
    while (just_started or self.lexer.next_token() == .comma) {
        just_started = false;
        if (self.lexer.peek_char() == ')') break;
        const next_param = try self.ask_fn_param();
        const result = try params.getOrPut(next_param.name);
        if (result.found_existing) return Error.duplicate_param_name;
        result.value_ptr.* = next_param.param;
    }
    try self.ask(.rparen);

    var return_type = a.Type{ .void = {} };

    if (self.lexer.peek_char() != '{') return_type = try self.ask_type();

    return a.Item.Fn{ .visibility = vis, .signature = a.Item.Fn.Signature{ .name = name, .params = params, .return_type = return_type } };
}

fn ask_type(self: *Self) !a.Type {
    return switch (self.lexer.next_token()) {
        .ident => |ident| a.Type.primitive_map.get(ident) orelse .{ .named = ident },
        else => Error.expected_type,
    };
}

fn eqq(token: Lexer.Token, tag: @typeInfo(Lexer.Token).Union.tag_type.?) bool {
    if (token == tag) {
        return true;
    }
    return false;
}
