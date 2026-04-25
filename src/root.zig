const std = @import("std");
const Io = std.Io;
const http = std.http;

pub const FetchOptions = struct {
    method: http.Method = .GET,
    headers: []const http.Header = &.{},
    body: ?Body = null,
    query: []const [2][]const u8 = &.{},
};

pub const Body = union(enum) {
    raw: []const u8,
    json: anyopaque,
    form: []const [2][]const u8,
};

pub const Headers = struct {
    items: []http.Header,
};

pub const Response = struct {
    status: http.Status,
    headers: Headers,
    arena: *std.heap.ArenaAllocator,
    body_text: []const u8,
    http_client: *http.Client,

    pub fn deinit(self: *Response) void {
        self.http_client.deinit();
        self.arena.child_allocator.destroy(self.http_client);
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

pub fn fetchGet(io: Io, allocator: std.mem.Allocator, url: []const u8, opts: FetchOptions) !Response {
    return request(io, allocator, url, opts);
}

pub fn fetchPost(io: Io, allocator: std.mem.Allocator, url: []const u8, opts: FetchOptions) !Response {
    var opts_copy = opts;
    opts_copy.method = .POST;
    return request(io, allocator, url, opts_copy);
}

fn request(io: Io, allocator: std.mem.Allocator, url: []const u8, opts: FetchOptions) !Response {
    var arena = try allocator.create(std.heap.ArenaAllocator);
    arena.* = .init(allocator);
    errdefer arena.deinit();

    const aa = arena.allocator();

    var http_client = try allocator.create(http.Client);
    http_client.* = .{
        .allocator = aa,
        .io = io,
    };
    errdefer {
        http_client.deinit();
        allocator.destroy(http_client);
    }

    var body_buf = try aa.alloc(u8, 8192);
    var response_writer = Io.Writer.fixed(body_buf);

    var json_payload: []const u8 = "";
    var extra_headers = opts.headers;
    
    if (opts.body) |body| {
        switch (body) {
            .raw => |raw| {
                json_payload = raw;
                extra_headers = try std.mem.concat(aa, http.Header, &.{
                    opts.headers,
                    &.{.{ .name = "Content-Type", .value = "application/octet-stream" }},
                });
            },
            .json => |_| {
                json_payload = try std.json.stringifyAlloc(aa, body, .{});
                extra_headers = try std.mem.concat(aa, http.Header, &.{
                    opts.headers,
                    &.{.{ .name = "Content-Type", .value = "application/json" }},
                });
            },
            .form => |form| {
                var form_str = try std.Uri.percentEncodeQuery(aa, form);
                json_payload = form_str;
                extra_headers = try std.mem.concat(aa, http.Header, &.{
                    opts.headers,
                    &.{.{ .name = "Content-Type", .value = "application/x-www-form-urlencoded" }},
                });
            },
        }
    }

    const uri = try std.Uri.parse(url);
    const result = http_client.fetch(.{
        .location = .{ .uri = uri },
        .method = opts.method,
        .extra_headers = extra_headers,
        .payload = if (json_payload.len > 0) json_payload else null,
        .response_writer = &response_writer,
    }) catch {
        return error.HttpRequestFailed;
    };

    return .{
        .status = result.status,
        .headers = .{ .items = &.{} },
        .arena = arena,
        .body_text = body_buf[0..response_writer.end],
        .http_client = http_client,
    };
}

pub const Client = struct {
    io: Io,
    allocator: std.mem.Allocator,
    base_url: []const u8,
    headers: []const http.Header,

    pub fn init(io: Io, allocator: std.mem.Allocator, options: struct {
        base_url: []const u8,
        headers: []const http.Header = &.{},
    }) Client {
        return .{
            .io = io,
            .allocator = allocator,
            .base_url = options.base_url,
            .headers = options.headers,
        };
    }

    pub fn get(self: *Client, path: []const u8, opts: FetchOptions) !Response {
        const full_url = try std.mem.concat(self.allocator, u8, &.{
            self.base_url, path
        });
        var opts_with_headers = opts;
        opts_with_headers.headers = self.headers;
        return fetchGet(self.io, self.allocator, full_url, opts_with_headers);
    }

    pub fn post(self: *Client, path: []const u8, opts: FetchOptions) !Response {
        const full_url = try std.mem.concat(self.allocator, u8, &.{
            self.base_url, path
        });
        var opts_with_headers = opts;
        opts_with_headers.headers = self.headers;
        return fetchPost(self.io, self.allocator, full_url, opts_with_headers);
    }
};

test "debug text content" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var res = try fetchGet(io, allocator, "https://httpbin.org/get", .{});
    defer res.deinit();

    std.debug.print("status: {d}\n", .{res.status});
    std.debug.print("body length: {d}\n", .{res.text().len});
    std.debug.print("body content: {s}\n", .{res.text()});
}

const HttpbinResponse = struct {
    url: []const u8,
    headers: std.json.Value,
    origin: []const u8,
    args: std.json.Value,
};

test "response.json()" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var res = try fetchGet(io, allocator, "https://httpbin.org/get", .{});
    defer res.deinit();

    const parsed = try res.json(HttpbinResponse);
    try std.testing.expectEqualStrings("https://httpbin.org/get", parsed.value.url);
}

test "Client.get()" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var client = Client.init(io, allocator, .{
        .base_url = "https://httpbin.org",
        .headers = &.{.{ .name = "X-Custom", .value = "pacman" }},
    });

    var res = try client.get("/get", .{});
    defer res.deinit();

    try std.testing.expect(res.status == .ok);

    const body = res.text();
    try std.testing.expect(std.mem.indexOf(u8, body, "pacman") != null);
}

test "Client.post() with json body" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var client = Client.init(io, allocator, .{
        .base_url = "https://httpbin.org",
    });

    const payload = .{
        .name = "pacman",
        .version = @as(u32, 1),
    };

    var res = try client.post("/post", .{
        .body = .{ .json = payload },
    });
    defer res.deinit();

    try std.testing.expect(res.status == .ok);
    const body = res.text();
    try std.testing.expect(std.mem.indexOf(u8, body, "pacman") != null);
}