const s = @import("std");
pub const File = struct { items: []const Item };
pub const Visibility = enum { public, inherited };

pub const Item = union(enum) {
    Fn: Fn,

    // pub fn fnName(comptime infer T: type,)
    pub const Fn = struct {
        visibility: Visibility,
        signature: Signature,
        name: []const u8,
        pub const Param = struct {
            is_comptime: bool,
            is_infer: bool,
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
    // trait: Trait,

    pub const Primitive = union(enum) {
        Number: Number,
        NumSize: NumSize,

        // signed / unsigned
        pub const Signedness = enum { signed, unsigned };
        // uN / iN
        pub const Number = struct {
            signedness: Signedness,
            bits: u16,
        };
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
};
