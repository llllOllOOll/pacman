const std = @import("std");

const Io = std.Io;
const Response = @import("response.zig").Response;
const FetchOptions = @import("request.zig").FetchOptions;
const fetchGet = @import("request.zig").fetchGet;
const fetchPost = @import("request.zig").fetchPost;

pub const Client = struct {
    io: Io,
    allocator: std.mem.Allocator,
    base_url: []const u8,
    headers: []const std.http.Header,

    pub fn init(io: Io, allocator: std.mem.Allocator, opts: struct {
        base_url: []const u8,
        headers: []const std.http.Header = &.{},
    }) Client {
        return .{
            .io = io,
            .allocator = allocator,
            .base_url = opts.base_url,
            .headers = opts.headers,
        };
    }

    pub fn get(self: *Client, path: []const u8, opts: FetchOptions) !Response {
        const full_url = try std.mem.concat(self.allocator, u8, &.{ self.base_url, path });
        var opts_with_headers = opts;
        opts_with_headers.headers = self.headers;
        const res = fetchGet(self.io, self.allocator, full_url, opts_with_headers);
        // free the URL string that was allocated for the request
        self.allocator.free(full_url);
        return res;
    }

    pub fn post(self: *Client, path: []const u8, opts: FetchOptions) !Response {
        const full_url = try std.mem.concat(self.allocator, u8, &.{ self.base_url, path });
        var opts_with_headers = opts;
        opts_with_headers.headers = self.headers;
        const res = fetchPost(self.io, self.allocator, full_url, opts_with_headers);
        self.allocator.free(full_url);
        return res;
    }
};
