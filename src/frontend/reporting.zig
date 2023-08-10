const s = @import("std");

pub const Diagnostic = @import("reporting/diagnostic.zig");
pub const Files = @import("reporting/files.zig");
const Renderer = @import("reporting/renderer.zig").Renderer;

pub const Reporting = struct {
    files: Files,
    allocator: s.mem.Allocator,
    pub fn report(self: *Reporting, diagnostic: Diagnostic) !void {
        const stderr = s.io.getStdErr().writer();
        var renderer = Renderer(@TypeOf(stderr)){ .writer = stderr, .allocator = self.allocator };
        try renderer.render(diagnostic, &self.files);
    }
};
