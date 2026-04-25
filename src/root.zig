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
    json: []const u8,
    form: []const [2][]const u8,
};

pub fn jsonBody(allocator: std.mem.Allocator, value: anytype) !Body {
    const serialized = try std.json.Stringify.valueAlloc(allocator, value, .{});
    return .{ .json = serialized };
}

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

fn encodeQueryComponentLen(s: []const u8) usize {
    var escape_count: usize = 0;
    for (s) |c| {
        if (shouldEscape(c)) {
            escape_count += 1;
        }
    }
    return s.len + 2 * escape_count;
}

const UPPER_HEX = "0123456789ABCDEF";

fn encodeQueryComponent(s: []const u8, writer: anytype) !void {
    for (s) |c| {
        if (shouldEscape(c)) {
            try writer.writeByte('%');
            try writer.writeByte(UPPER_HEX[c >> 4]);
            try writer.writeByte(UPPER_HEX[c & 15]);
        } else {
            try writer.writeByte(c);
        }
    }
}

fn shouldEscape(c: u8) bool {
    // fast path for common cases
    if (std.ascii.isAlphanumeric(c)) {
        return false;
    }
    return c != '-' and c != '_' and c != '.' and c != '~';
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

    var payload_opt: ?[]const u8 = null;
    var payload_allocator: ?std.mem.Allocator = null;
    var extra_headers = opts.headers;

    if (opts.body) |b| {
        switch (b) {
            .raw => |raw| {
                payload_opt = raw;
                extra_headers = try std.mem.concat(aa, http.Header, &.{
                    opts.headers,
                    &.{.{ .name = "Content-Type", .value = "application/octet-stream" }},
                });
            },
            .json => |json_data| {
                // json_data is a []const u8 already containing JSON
                payload_opt = json_data;
                payload_allocator = allocator; // Store the original allocator
                extra_headers = try std.mem.concat(aa, http.Header, &.{
                    opts.headers,
                    &.{.{ .name = "Content-Type", .value = "application/json" }},
                });
            },
            .form => |form| {
                // Not required for current tests; ignore or implement later
                _ = form;
            },
        }
    }

    // Handle query parameters
    var final_url: []const u8 = url;
    if (opts.query.len > 0) {
        var query_buf = std.ArrayList(u8).initCapacity(aa, url.len + opts.query.len + 10) catch unreachable;

        try query_buf.appendSlice(aa, url);

        // Check if URL already has query parameters
        const has_query = std.mem.indexOfScalar(u8, url, '?') != null;
        if (has_query) {
            // URL already has query parameters, add with & separator
            try query_buf.append(aa, '&');
        } else {
            // URL has no query parameters, start with ?
            try query_buf.append(aa, '?');
        }

        // Add each query parameter
        for (opts.query, 0..) |param, i| {
            if (i > 0) {
                try query_buf.append(aa, '&');
            }

            const key = param[0];
            const value = param[1];

            // Encode key
            for (key) |c| {
                if (shouldEscape(c)) {
                    try query_buf.appendSlice(aa, "%");
                    try query_buf.append(aa, UPPER_HEX[c >> 4]);
                    try query_buf.append(aa, UPPER_HEX[c & 15]);
                } else {
                    try query_buf.append(aa, c);
                }
            }
            try query_buf.append(aa, '=');
            // Encode value
            for (value) |c| {
                if (shouldEscape(c)) {
                    try query_buf.appendSlice(aa, "%");
                    try query_buf.append(aa, UPPER_HEX[c >> 4]);
                    try query_buf.append(aa, UPPER_HEX[c & 15]);
                } else {
                    try query_buf.append(aa, c);
                }
            }
        }

        final_url = try query_buf.toOwnedSlice(aa);
    }

    const uri = try std.Uri.parse(final_url);
    const result = http_client.fetch(.{
        .location = .{ .uri = uri },
        .method = opts.method,
        .extra_headers = extra_headers,
        .payload = payload_opt,
        .response_writer = &response_writer,
    }) catch {
        return error.HttpRequestFailed;
    };

    // Free the JSON payload if it was allocated
    if (payload_allocator) |alloc| {
        if (payload_opt) |payload| {
            alloc.free(payload);
        }
    }

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
        .body = try jsonBody(allocator, payload),
    });
    defer res.deinit();

    try std.testing.expect(res.status == .ok);
    const body = res.text();
    try std.testing.expect(std.mem.indexOf(u8, body, "pacman") != null);
}

test "query params" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var res = try fetchGet(io, allocator, "https://httpbin.org/get", .{
        .query = &.{
            .{ "page", "1" },
            .{ "limit", "10" },
            .{ "search", "hello world" }, // must be URL-encoded
        },
    });
    defer res.deinit();

    try std.testing.expect(res.status == .ok);
    const body = res.text();
    // httpbin echoes query params back in "args"
    try std.testing.expect(std.mem.indexOf(u8, body, "page") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "limit") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "hello") != null);
}
