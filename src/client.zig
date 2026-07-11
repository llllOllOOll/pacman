const std = @import("std");

const Io = std.Io;
const Response = @import("response.zig").Response;
const FetchOptions = @import("request.zig").FetchOptions;
const fetchGet = @import("request.zig").get;
const fetchPost = @import("request.zig").post;
const fetchPut = @import("request.zig").put;
const fetchPatch = @import("request.zig").patch;
const fetchDelete = @import("request.zig").delete;

pub const Client = struct {
    io: Io,
    allocator: std.mem.Allocator,
    base_url: []const u8,
    headers: []const std.http.Header,
    proxy_url: ?[]const u8,

    pub fn init(io: Io, allocator: std.mem.Allocator, opts: struct {
        base_url: []const u8,
        headers: []const std.http.Header = &.{},
        proxy_url: ?[]const u8 = null,
    }) Client {
        return .{
            .io = io,
            .allocator = allocator,
            .base_url = opts.base_url,
            .headers = opts.headers,
            .proxy_url = opts.proxy_url,
        };
    }

    pub fn get(self: *Client, path: []const u8, opts: FetchOptions) !Response {
        const full_url = try std.mem.concat(self.allocator, u8, &.{ self.base_url, path });
        var opts_with_headers = opts;
        opts_with_headers.headers = self.headers;
        if (opts_with_headers.proxy_url == null) opts_with_headers.proxy_url = self.proxy_url;
        const res = fetchGet(self.io, self.allocator, full_url, opts_with_headers);
        // free the URL string that was allocated for the request
        self.allocator.free(full_url);
        return res;
    }

    pub fn post(self: *Client, path: []const u8, opts: FetchOptions) !Response {
        const full_url = try std.mem.concat(self.allocator, u8, &.{ self.base_url, path });
        var opts_with_headers = opts;
        opts_with_headers.headers = self.headers;
        if (opts_with_headers.proxy_url == null) opts_with_headers.proxy_url = self.proxy_url;
        const res = fetchPost(self.io, self.allocator, full_url, opts_with_headers);
        self.allocator.free(full_url);
        return res;
    }

    pub fn put(self: *Client, path: []const u8, opts: FetchOptions) !Response {
        const full_url = try std.mem.concat(self.allocator, u8, &.{ self.base_url, path });
        var opts_with_headers = opts;
        opts_with_headers.headers = self.headers;
        if (opts_with_headers.proxy_url == null) opts_with_headers.proxy_url = self.proxy_url;
        const res = fetchPut(self.io, self.allocator, full_url, opts_with_headers);
        self.allocator.free(full_url);
        return res;
    }

    pub fn patch(self: *Client, path: []const u8, opts: FetchOptions) !Response {
        const full_url = try std.mem.concat(self.allocator, u8, &.{ self.base_url, path });
        var opts_with_headers = opts;
        opts_with_headers.headers = self.headers;
        if (opts_with_headers.proxy_url == null) opts_with_headers.proxy_url = self.proxy_url;
        const res = fetchPatch(self.io, self.allocator, full_url, opts_with_headers);
        self.allocator.free(full_url);
        return res;
    }

    pub fn delete(self: *Client, path: []const u8, opts: FetchOptions) !Response {
        const full_url = try std.mem.concat(self.allocator, u8, &.{ self.base_url, path });
        var opts_with_headers = opts;
        opts_with_headers.headers = self.headers;
        if (opts_with_headers.proxy_url == null) opts_with_headers.proxy_url = self.proxy_url;
        const res = fetchDelete(self.io, self.allocator, full_url, opts_with_headers);
        self.allocator.free(full_url);
        return res;
    }
};

pub fn asyncGet(client: *Client, path: []const u8, opts: FetchOptions) !Response {
    return client.get(path, opts);
}

pub fn asyncPost(client: *Client, path: []const u8, opts: FetchOptions) !Response {
    return client.post(path, opts);
}

pub fn asyncPut(client: *Client, path: []const u8, opts: FetchOptions) !Response {
    return client.put(path, opts);
}

pub fn asyncPatch(client: *Client, path: []const u8, opts: FetchOptions) !Response {
    return client.patch(path, opts);
}

pub fn asyncDelete(client: *Client, path: []const u8, opts: FetchOptions) !Response {
    return client.delete(path, opts);
}
