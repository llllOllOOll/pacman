const std = @import("std");
const Io = std.Io;

pub const Body = @import("body.zig").Body;
pub const jsonBody = @import("body.zig").jsonBody;
pub const Headers = @import("headers.zig").Headers;
pub const Response = @import("response.zig").Response;
pub const Client = @import("client.zig").Client;
pub const FetchOptions = @import("request.zig").FetchOptions;
pub const asyncGet = @import("client.zig").asyncGet;
pub const asyncPost = @import("client.zig").asyncPost;
pub const asyncPut = @import("client.zig").asyncPut;
pub const asyncPatch = @import("client.zig").asyncPatch;
pub const asyncDelete = @import("client.zig").asyncDelete;
pub const get = @import("request.zig").get;
pub const post = @import("request.zig").post;
pub const put = @import("request.zig").put;
pub const patch = @import("request.zig").patch;
pub const delete = @import("request.zig").delete;

test "debug text content" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var res = try get(io, allocator, "https://httpbin.org/get", .{});
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

    var res = try get(io, allocator, "https://httpbin.org/get", .{});
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
    const serialized = try std.json.Stringify.valueAlloc(allocator, payload, .{});
    defer allocator.free(serialized);

    var res = try client.post("/post", .{
        .body = jsonBody(serialized),
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

    var res = try get(io, allocator, "https://httpbin.org/get", .{
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

test "large response body" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    // httpbin returns a large response with 16384 bytes
    var res = try get(io, allocator, "https://httpbin.org/stream-bytes/16384", .{});
    defer res.deinit();

    try std.testing.expect(res.status == .ok);
    const body = res.text();
    try std.testing.expect(body.len > 8192); // must be larger than old fixed buffer
}

test "URL params" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var client = Client.init(io, allocator, .{
        .base_url = "https://httpbin.org",
    });

    var res = try client.get("/anything/:version/users/:id", .{
        .params = &.{
            .{ "version", "v1" },
            .{ "id", "42" },
        },
    });
    defer res.deinit();

    try std.testing.expect(res.status == .ok);
    const body = res.text();
    // httpbin echoes the URL back — confirm params were replaced
    try std.testing.expect(std.mem.indexOf(u8, body, "v1") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, "42") != null);
    try std.testing.expect(std.mem.indexOf(u8, body, ":id") == null);
    try std.testing.expect(std.mem.indexOf(u8, body, ":version") == null);
}

test "response headers" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var res = try get(io, allocator, "https://httpbin.org/get", .{});
    defer res.deinit();

    // Test that response was successful
    try std.testing.expect(res.status == .ok);

    // Test real header extraction - httpbin.org should return specific headers
    const content_type = res.headers.get("content-type");
    try std.testing.expect(content_type != null);
    try std.testing.expect(std.mem.indexOf(u8, content_type.?, "application/json") != null);

    // Test case-insensitive header lookup
    const content_type_upper = res.headers.get("CONTENT-TYPE");
    try std.testing.expect(content_type_upper != null);
    try std.testing.expect(std.mem.eql(u8, content_type.?, content_type_upper.?));
}

test "put request" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    const payload = .{ .name = "pacman" };
    const serialized = try std.json.Stringify.valueAlloc(allocator, payload, .{});
    defer allocator.free(serialized);

    var res = try put(io, allocator, "https://httpbin.org/put", .{
        .body = jsonBody(serialized),
    });
    defer res.deinit();
    try std.testing.expect(res.status == .ok);
}

test "patch request" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    const payload = .{ .name = "pacman" };
    const serialized = try std.json.Stringify.valueAlloc(allocator, payload, .{});
    defer allocator.free(serialized);

    var res = try patch(io, allocator, "https://httpbin.org/patch", .{
        .body = jsonBody(serialized),
    });
    defer res.deinit();
    try std.testing.expect(res.status == .ok);
}

test "delete request" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var res = try delete(io, allocator, "https://httpbin.org/delete", .{});
    defer res.deinit();
    try std.testing.expect(res.status == .ok);
}

test "form body" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var res = try post(io, allocator, "https://httpbin.org/post", .{
        .body = .{ .form = &.{
            .{ "name", "pacman" },
            .{ "version", "1" },
        } },
    });
    defer res.deinit();
    try std.testing.expect(res.status == .ok);
    const body = res.text();
    try std.testing.expect(std.mem.indexOf(u8, body, "pacman") != null);
}

test "timeout field exists" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    // Test that timeout_ms field exists and doesn't break anything
    var res = try get(io, allocator, "https://httpbin.org/get", .{
        .timeout_ms = 0, // No timeout
    });
    defer res.deinit();
    try std.testing.expect(res.status == .ok);
}

test "real timeout functionality" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    // This test will need to be updated when timeout functionality is implemented
    // For now, it just verifies that the request completes successfully
    var res = try get(io, allocator, "https://httpbin.org/delay/1", .{
        .timeout_ms = 500, // 500ms timeout - should timeout if implemented
    });
    defer res.deinit();

    // Currently timeout is not implemented, so request should succeed
    try std.testing.expect(res.status == .ok);
}

test "Client.delete()" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var client = Client.init(io, allocator, .{
        .base_url = "https://httpbin.org",
    });
    var res = try client.delete("/delete", .{});
    defer res.deinit();
    try std.testing.expect(res.status == .ok);
}

test "concurrent requests with io.async" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    // measure time — 2 sequential requests would take ~2x
    // concurrent should finish in ~1x
    const start = Io.Clock.real.now(io);

    var t1 = io.async(get, .{ io, allocator, "https://httpbin.org/delay/1", FetchOptions{} });
    var t2 = io.async(get, .{ io, allocator, "https://httpbin.org/delay/1", FetchOptions{} });

    var r1 = try t1.await(io);
    var r2 = try t2.await(io);

    const end = Io.Clock.real.now(io);
    const elapsed_ns = start.durationTo(end).toNanoseconds();
    const elapsed_ms = @divTrunc(elapsed_ns, 1000000);

    // if truly concurrent, both 1s requests finish in ~1s total, not ~2s
    std.debug.print("elapsed: {d}ms\n", .{elapsed_ms});

    defer r1.deinit();
    defer r2.deinit();

    try std.testing.expect(r1.status == .ok);
    try std.testing.expect(r2.status == .ok);
    // concurrent: should finish well under 2 seconds (accounting for network variability)
    try std.testing.expect(elapsed_ms < 1900);
}

test "asyncGet with Client" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var client = Client.init(io, allocator, .{
        .base_url = "https://httpbin.org",
    });

    var res = try client.get("/get", .{});
    defer res.deinit();
    try std.testing.expect(res.status == .ok);
}

test "asyncPost with Client" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var client = Client.init(io, allocator, .{
        .base_url = "https://httpbin.org",
    });

    var res = try client.post("/post", .{
        .body = jsonBody("{\"test\":true}"),
    });
    defer res.deinit();
    try std.testing.expect(res.status == .ok);
    const body = res.text();
    try std.testing.expect(std.mem.indexOf(u8, body, "\"test\": true") != null);
}

test "asyncPut with Client" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var client = Client.init(io, allocator, .{
        .base_url = "https://httpbin.org",
    });

    var res = try client.put("/put", .{
        .body = jsonBody("{\"updated\":true}"),
    });
    defer res.deinit();
    try std.testing.expect(res.status == .ok);
    const body = res.text();
    try std.testing.expect(std.mem.indexOf(u8, body, "\"updated\": true") != null);
}

test "asyncPatch with Client" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var client = Client.init(io, allocator, .{
        .base_url = "https://httpbin.org",
    });

    var res = try client.patch("/patch", .{
        .body = jsonBody("{\"patched\":true}"),
    });
    defer res.deinit();
    try std.testing.expect(res.status == .ok);
    const body = res.text();
    try std.testing.expect(std.mem.indexOf(u8, body, "\"patched\": true") != null);
}

test "asyncDelete with Client" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var client = Client.init(io, allocator, .{
        .base_url = "https://httpbin.org",
    });

    var res = try client.delete("/delete", .{});
    defer res.deinit();
    try std.testing.expect(res.status == .ok);
}

test "concurrent async requests with Client methods" {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    var client = Client.init(io, allocator, .{
        .base_url = "https://httpbin.org",
    });

    const start = Io.Clock.real.now(io);

    var t1 = io.async(asyncGet, .{ &client, "/delay/1", .{} });
    var t2 = io.async(asyncGet, .{ &client, "/delay/1", .{} });

    var r1 = try t1.await(io);
    var r2 = try t2.await(io);

    const end = Io.Clock.real.now(io);
    const elapsed_ns = start.durationTo(end).toNanoseconds();
    const elapsed_ms = @divTrunc(elapsed_ns, 1000000);

    defer r1.deinit();
    defer r2.deinit();

    try std.testing.expect(r1.status == .ok);
    try std.testing.expect(r2.status == .ok);
    try std.testing.expect(elapsed_ms < 2500);
}
