const Lexer = @import("lexer.zig");
const s = @import("std");
const a = @import("../src/Ast.zig");

const Self = @This();

lexer: Lexer,
allocator: s.mem.Allocator,

pub const Error = error{ invalid_token, eof };

fn UnionTagToFieldType(comptime U: type, comptime tag: @typeInfo(U).Union.tag_type.?) type {
    const u = @typeInfo(U).Union;
    const tag_name = @tagName(tag);
    inline for (u.fields) |field| {
        if (field.name == tag_name) return field.type;
    }
    @compileError("not found???");
}

fn ask(self: *Self, comptime token: @typeInfo(Lexer.Token).Union.tag_type.?) !UnionTagToFieldType(Lexer.Token, token) {
    if (self.lexer.next_token() == token) |value| {
        return value;
    }
    return Error.invalid_token;
}

pub fn ask_file(self: *Self) !a.File {
    var items = s.ArrayList(a.Item).init(self.allocator);
    while (true)
        return .{ .items = items };
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
        }
    }
}

fn ask_fn_param(self: *Self) !struct { name: []const u8, param: a.Item.Fn.Param } {
    const name = try self.ask(.ident);
    try self.ask(.comma);
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

    var return_type = a.Type.Void;

    if (self.lexer.peek_char() != '{') return_type = try self.ask_type();

    return a.Item.Fn{ .visibility = vis, .signature = a.Item.Fn.Signature{ .name = name, .params = params, .return_type = return_type } };
}

fn ask_type(self: *Self) !a.Type {
    return switch (self.lexer.next_token()) {
        .ident => |ident| a.Type.primitive_map.get(ident) orelse .{ .Named = ident },
        else => Error.expected_type,
    };
}
