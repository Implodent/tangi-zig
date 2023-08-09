//! thank you ThePrimeagen for an amazing reference implementation of a lexer.
const Self = @This();

read_position: usize = 0,
position: usize = 0,
ch: u8 = 0,
input: []const u8,
last_token: Token = .eof,

pub fn init(input: []const u8) Self {
    var lex = Self{
        .input = input,
    };

    lex.read_char();

    return lex;
}

pub fn has_tokens(self: *Self) bool {
    return self.ch != 0;
}

pub fn next_token(self: *Self) Token {
    self.skip_whitespace();
    const tok: Token = switch (self.ch) {
        '{' => .lcurly,
        '}' => .rcurly,
        '(' => .lparen,
        ')' => .rparen,
        ',' => .comma,
        ':' => .colon,
        ';' => .semi,
        '+' => .plus,
        '-' => .dash,
        '/' => .forward_slash,
        '*' => .asterisk,
        '<' => .less_than,
        '>' => .greater_than,
        '.' => .dot,
        '?' => .question_mark,
        '!' => blk: {
            if (self.peek_char() == '=') {
                self.read_char();
                break :blk .neq;
            } else {
                break :blk .bang;
            }
        },
        '=' => blk: {
            if (self.peek_char() == '=') {
                self.read_char();
                break :blk .eqeq;
            } else {
                break :blk .eq;
            }
        },
        '"' => .{ .lit_str = self.read_str() },
        0 => .eof,
        'a'...'z', 'A'...'Z', '_' => {
            const ident = self.read_identifier();
            if (Token.keyword(ident)) |token| {
                return token;
            }
            return .{ .ident = ident };
        },
        '0'...'9' => {
            const int = self.read_int();
            return .{ .int = int };
        },
        else => .illegal,
    };
    self.last_token = tok;

    self.read_char();
    return tok;
}

fn read_str(self: *Self) []const u8 {
    const initial = self.position;
    self.read_char();
    while (self.ch != '"' or self.ch == 0) self.read_char();
    return self.input[initial + 1 .. self.position];
}

fn peek_char(self: *Self) u8 {
    if (self.read_position >= self.input.len) {
        return 0;
    } else {
        return self.input[self.read_position];
    }
}

fn read_char(self: *Self) void {
    if (self.read_position >= self.input.len) {
        self.ch = 0;
    } else {
        self.ch = self.input[self.read_position];
    }

    self.position = self.read_position;
    self.read_position += 1;
}

fn read_identifier(self: *Self) []const u8 {
    const position = self.position;

    while (isIdent(self.ch)) {
        self.read_char();
    }

    return self.input[position..self.position];
}

fn read_int(self: *Self) []const u8 {
    const position = self.position;

    while (isInt(self.ch)) {
        self.read_char();
    }

    return self.input[position..self.position];
}

fn skip_whitespace(self: *Self) void {
    while (s.ascii.isWhitespace(self.ch)) {
        self.read_char();
    }
}
const s = @import("std");
pub const Error = error{
    unexpected_eof,
};
fn isIdent(ch: u8) bool {
    return s.ascii.isAlphabetic(ch) or ch == '_';
}

pub const Token = union(enum) {
    // identifier
    ident: []const u8,
    // integer
    int: []const u8,
    lit_str: []const u8,
    lcurly,
    rcurly,
    lparen,
    rparen,
    lbrace,
    rbrace,
    comma,
    colon,
    dot,
    semi,
    plus,
    dash,
    // /
    forward_slash,
    // *
    asterisk,
    // >
    greater_than,
    // <
    less_than,
    // =
    eq,
    // !=
    neq,
    // ==
    eqeq,
    // !
    bang,
    // ?
    question_mark,
    kw_pub,
    kw_const,
    kw_var,
    kw_if,
    kw_else,
    kw_fn,
    kw_true,
    kw_false,
    kw_struct,
    kw_context,
    kw_comptime,
    kw_infer,
    // end of input
    eof,
    // something else not recognized by lexer
    illegal,
    // all recognized keywords. must be up to date with kw_* variants
    const keywords = s.ComptimeStringMap(Token, .{
        //
        .{ "const", .kw_const },
        .{ "var", .kw_var },
        .{ "if", .kw_if },
        .{ "else", .kw_else },
        .{ "fn", .kw_fn },
        .{ "true", .kw_true },
        .{ "false", .kw_false },
        .{ "pub", .kw_pub },
        .{ "struct", .kw_struct },
        .{ "context", .kw_context },
        .{
            "comptime",
            .kw_comptime,
        },
        .{ "infer", .kw_infer },
    });

    pub fn keyword(ident: []const u8) ?Token {
        return keywords.get(ident);
    }
};
fn isInt(ch: u8) bool {
    return s.ascii.isDigit(ch);
}

test Self {
    const input = "fn hello() {s.debug.print(\"world!\");}";
    var lexer = init(input);
    var tokens = [_]Token{
        //
        .kw_fn,
        .{ .ident = "hello" },
        .lparen,
        .rparen,
        .lcurly,
        .{ .ident = "s" },
        .dot,
        .{ .ident = "debug" },
        .dot,
        .{ .ident = "print" },
        .lparen,
        .{ .lit_str = "world!" },
        .rparen,
        .semi,
        .rcurly,
        .eof,
    };
    for (tokens) |token| {
        const lex_token = lexer.next_token();
        s.testing.expectEqualDeep(token, lex_token) catch {
            s.log.err("death at {}, char at pos = {c} ({1});\nexpected token: {}, actual token: {}", .{ lexer.position, input[lexer.position], token, lex_token });
            return error.TestExpectedEqual;
        };
    }
}
