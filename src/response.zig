const std = @import("std");
const http = std.http;

const Headers = @import("headers.zig").Headers;

pub const Response = struct {
    status: http.Status,
    headers: Headers,
    arena: *std.heap.ArenaAllocator,
    body_text: []const u8,
    http_client: *http.Client,

    pub fn deinit(self: *Response) void {
        self.http_client.deinit();
        self.arena.allocator().destroy(self.http_client);
        self.arena.deinit();
        self.arena.child_allocator.destroy(self.arena);
    }

    pub fn text(self: *Response) []const u8 {
        return self.body_text;
    }

    pub fn json(self: *Response, comptime T: type) !std.json.Parsed(T) {
        const allocator = self.arena.allocator();
        return try std.json.parseFromSlice(T, allocator, self.body_text, .{
            .ignore_unknown_fields = true,
        });
    }
};
