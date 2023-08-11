const s = @import("std");

pub fn Opt(comptime T: type) type {
    return union(enum) {
        some: T,
        none: void,

        const Self = @This();

        pub fn take(self: *Self) ?T {
            return switch (self) {
                .some => |value| {
                    self.* = .{ .none = {} };
                    return value;
                },
                .none => null,
            };
        }

        pub fn nullify(self: Self) ?T {
            return switch (self) {
                .some => |value| value,
                .none => null,
            };
        }

        pub fn fromNullable(value: ?T) Self {
            return if (value) |val| .{ .some = val } else .{ .none = {} };
        }
    };
}

pub fn Item(comptime Iter: type) ?type {
    if (@hasDecl(Iter, "next")) {
        return @typeInfo(@TypeOf(@field(Iter, "next"))).Fn.return_type;
    } else {
        return null;
    }
}

fn Validate(comptime Iter: type, comptime T: type, comptime result: type) type {
    const t = Item(Iter) orelse @compileError("`Iter` is not an iterator");
    if (T != t) @compileError("iterator item types don't match, expected " ++ @typeName(T) ++ ", got " ++ @typeName(t));
    return result;
}

pub fn Filter(comptime Iter: type) type {
    const T = Item(Iter) orelse @compileError("`Iter` is not an iterator");

    return struct {
        iterator: Iter,
        filter: *const fn (thing: *const T) bool,

        const Self = @This();

        pub fn next(self: *Self) ?T {
            var item = self.iterator.next() orelse return null;
            while (!self.filter(&item)) item = self.iterator.next() orelse return null;
            return item;
        }
    };
}

pub fn filter(comptime T: type, iterator: anytype, filter_fn: *const fn (thing: *const T) bool) Validate(@TypeOf(iterator), T, Filter(@TypeOf(iterator))) {
    return .{ .iterator = iterator, .filter = filter_fn };
}

pub fn FilterMap(comptime Iter: type, comptime R: type) type {
    const T = Item(Iter) orelse @compileError("`Iter` is not an iterator");

    return struct {
        iterator: Iter,
        filter_map: *const fn (thing: T) ?R,

        const Self = @This();

        pub fn next(self: *Self) ?R {
            var item = self.iterator.next() orelse return null;
            while (true) : (item = self.iterator.next() orelse return null) {
                const result = self.filter_map(item) orelse continue;
                return result;
            }
        }
    };
}

pub fn filterMap(comptime T: type, comptime R: type, iterator: anytype, filter_map: *const fn (thing: T) ?R) Validate(@TypeOf(iterator), T, FilterMap(@TypeOf(iterator), R)) {
    return .{ .filter_map = filter_map, .iterator = iterator };
}

pub fn Peekable(comptime Iter: type) type {
    const T = Item(Iter) orelse @compileError("`Iter` is not an iterator");

    return struct {
        iterator: Iter,
        peeked: Opt(Opt(T)),

        const Self = @This();

        pub fn next(self: *Self) ?T {
            return switch (self.peeked.take()) {
                .some => |inner| inner.nullify(),
                .none, null => self.iterator.next(),
            };
        }

        pub inline fn peek(self: *Self) ?*const T {
            const self_const: *const Self = @ptrCast(self);
            return switch (&self_const.peeked) {
                .some => |*value| value,
                .none => {
                    const item = self.iterator.next() orelse return null;
                    (&self.peeked).* = .{ .some = item };
                    return &item;
                },
            };
        }

        pub inline fn peekMut(self: *Self) ?*T {
            return switch (&self.peeked) {
                .some => |*value| value,
                .none => {
                    const item = self.iterator.next() orelse return null;
                    (&self.peeked).* = .{ .some = item };
                    return &item;
                },
            };
        }
    };
}

pub fn peekable(comptime T: type, iterator: anytype) Validate(@TypeOf(iterator), T, Peekable(@TypeOf(iterator))) {
    return .{ .iterator = iterator };
}

pub fn Slice(comptime T: type) type {
    return struct {
        slice: []const T,
        index: usize = 0,

        const Self = @This();

        pub fn next(self: *Self) ?T {
            if (self.index >= self.slice.len - 1) return null;
            const value = self.slice[self.index];
            self.index += 1;
            return value;
        }
    };
}

pub fn slice(comptime T: type, slc: []const T) Slice(T) {
    return .{ .slice = slc };
}

pub fn collect(comptime T: type, iterator: anytype, allocator: s.mem.Allocator) !Validate(@TypeOf(iterator), T, s.ArrayList(T)) {
    var array = s.ArrayList(T).init(allocator);

    while (iterator.next()) |item| try array.append(item);

    return array;
}
