const s = @import("std");
pub const File = struct { items: []const Item };
pub const Visibility = enum { public, inherited };

pub const Item = union(enum) {
    Fn: Fn,

    // pub fn fnName(comptime infer T: type,)
    pub const Fn = struct {
        visibility: Visibility,
        signature: Signature,
        pub const Param = struct {
            is_comptime: bool = false,
            is_infer: bool = false,
            ty: Type,
        };
        pub const Signature = struct { name: []const u8, params: s.StringHashMap(Param), return_type: Type };
    };
};

pub const Type = union(enum) {
    primitive: Primitive,
    array: Array,
    nullable: Nullable,
    error_union: ErrorUnion,
    tuple: Tuple,
    structure: Structure,
    void,
    named: []const u8,
    // trait: Trait,

    pub const Primitive = union(enum) {
        Number: Number,
        Float: Float,
        Bool,
        NumSize: NumSize,

        // signed / unsigned
        pub const Signedness = enum { signed, unsigned };
        // uN / iN
        pub const Number = struct {
            signedness: Signedness,
            bits: u16,
        };
        pub const Float = struct { bits: u16 };
        // usize / isize
        pub const NumSize = struct { signedness: Signedness };
    };

    pub const Array = union(enum) {
        // [T]
        Const: Const,
        // [1T]
        Sized: Sized,
        // [?T]
        Unsized: Unsized,
        pub const Const = struct { ty: *const Type, child_constant: bool = true };
        pub const Sized = struct { size: usize, ty: *const Type, child_constant: bool = true };
        pub const Unsized = struct { ty: *const Type, child_const: bool };
    };

    pub const Nullable = struct { inner: *const Type };

    pub const ErrorUnion = struct {
        err: *const Type,
        inner: *const Type,
    };

    pub const Tuple = struct { inner: []const Type };

    pub const Structure = struct {
        fields: s.StringHashMap(Field),

        pub const Field = struct { ty: Type };
    };

    pub const primitive_map = s.ComptimeStringMap(Type, [_]prim_pair{ .{ "void", .void }, .{ "bool", .{ .primitive = Primitive.Bool } } } ++ genNumbers());
    const prim_pair = struct { []const u8, Type };

    fn genNumbers() []const prim_pair {
        comptime var result: []const prim_pair = &.{};
        inline for (@as(u8, 1)..128) |bits| {
            result = result ++ &[2]prim_pair{
                .{
                    s.fmt.comptimePrint("u{}", .{bits}),
                    .{ .primitive = .{ .Number = .{ .signedness = .unsigned, .bits = @as(u16, bits) } } },
                },
                .{
                    s.fmt.comptimePrint("i{}", .{bits}),
                    .{
                        .primitive = .{
                            .Number = .{
                                .signedness = .signed,
                                .bits = @as(u16, bits),
                            },
                        },
                    },
                },
            };
        }
        return result ++ &[2]prim_pair{ .{ "f32", .{ .primitive = .{ .Float = .{ .bits = 32 } } } }, .{ "f64", .{ .primitive = .{ .Float = .{ .bits = 64 } } } } };
    }
};
