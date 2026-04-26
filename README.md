# pacman

> Idiomatic Zig HTTP client inspired by the Fetch API.

**pacman** is a Zig HTTP client library built on top of `std.http.Client`, providing a Fetch API-inspired interface with native `std.Io` support for Zig 0.17+.

If you already know the Fetch API from the browser or Node.js, you already know how to use pacman — no new mental model to learn.

---

## Features

- `GET`, `POST`, `PUT`, `PATCH`, `DELETE`
- JSON body — auto-serialized, zero boilerplate
- Form body with URL encoding
- Query params and URL path params (`:id` → `42`)
- Response headers with case-insensitive lookup
- `Client` with `baseURL` and global headers
- Native `std.Io` — works with `Threaded`, `Evented`, or any backend
- Async/await ready — pass `io` and let the caller decide concurrency
- Arena-based memory — one `res.deinit()` cleans everything

---

## Installation

Run in your project root:

```sh
zig fetch --save git+https://github.com/llllOllOOll/pacman
```

Then in `build.zig`:

```zig
const pacman_dep = b.dependency("pacman", .{});

const exe = b.addExecutable(.{
    .name = "myapp",
    .root_module = b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "myapp", .module = mod },
            .{ .name = "pacman", .module = pacman_dep.module("pacman") },
        },
    }),
});
```

---

## Quick Start

```zig
const std = @import("std");
const pacman = @import("pacman");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa.allocator();

    var res = try pacman.get(io, allocator, "https://api.example.com/users", .{});
    defer res.deinit();

    std.debug.print("{s}\n", .{res.text()});
}
```

---

## Usage

### Standalone requests

```zig
pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa.allocator();

    // GET
    var res = try pacman.get(io, allocator, "https://api.example.com/users", .{});
    defer res.deinit();

    // POST with JSON body
    const payload = .{ .name = "seven", .role = "admin" };
    const serialized = try std.json.Stringify.valueAlloc(allocator, payload, .{});
    defer allocator.free(serialized);

    var res = try pacman.post(io, allocator, "https://api.example.com/users", .{
        .body = pacman.jsonBody(serialized),
    });
    defer res.deinit();

    // PUT, PATCH, DELETE follow the same pattern
    var res = try pacman.delete(io, allocator, "https://api.example.com/users/42", .{});
    defer res.deinit();
}
```

### Client with baseURL and global headers

```zig
pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa.allocator();

    var api = pacman.Client.init(io, allocator, .{
        .base_url = "https://api.example.com",
        .headers = &.{
            .{ .name = "Authorization", .value = "Bearer your-token" },
            .{ .name = "Accept", .value = "application/json" },
        },
    });

    var res = try api.get("/users", .{});
    defer res.deinit();

    var res = try api.post("/users", .{
        .body = pacman.jsonBody(serialized),
    });
    defer res.deinit();
}
```

### Query params

```zig
pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa.allocator();

    var res = try pacman.get(io, allocator, "https://api.example.com/users", .{
        .query = &.{
            .{ "page", "1" },
            .{ "limit", "20" },
            .{ "search", "hello world" }, // automatically URL-encoded
        },
    });
    defer res.deinit();
    // → GET /users?page=1&limit=20&search=hello%20world
}
```

### URL path params

```zig
pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa.allocator();

    var api = pacman.Client.init(io, allocator, .{
        .base_url = "https://api.example.com",
    });

    var res = try api.get("/users/:id/posts/:post_id", .{
        .params = &.{
            .{ "id", "42" },
            .{ "post_id", "7" },
        },
    });
    defer res.deinit();
    // → GET /users/42/posts/7
}
```

### Reading the response

```zig
pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa.allocator();

    var api = pacman.Client.init(io, allocator, .{
        .base_url = "https://api.example.com",
    });

    var res = try api.get("/users/42", .{});
    defer res.deinit();

    // status code
    std.debug.print("status: {d}\n", .{res.status});

    // body as string
    const body = res.text();

    // body as JSON
    const User = struct { id: u32, name: []const u8 };
    const parsed = try res.json(User);
    std.debug.print("name: {s}\n", .{parsed.value.name});

    // response headers (case-insensitive)
    const ct = res.headers.get("content-type");
}
```

### Form body

```zig
pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa.allocator();

    var res = try pacman.post(io, allocator, "https://api.example.com/login", .{
        .body = .{ .form = &.{
            .{ "username", "seven" },
            .{ "password", "secret" },
        }},
    });
    defer res.deinit();
}
```

---

## Async/Await

pacman is built on `std.Io` — the same interface that powers Zig's async I/O. You write your code once and the caller decides the concurrency model.

**Note:** Always add `defer { _ = task.cancel(io) catch {}; }` immediately after each `io.async` call. If any `await` fails, the remaining tasks are automatically cancelled without leaking memory. The `_ =` is required because `cancel` returns a `Response` that must be explicitly discarded.

### Two requests in parallel

```zig
pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa.allocator();

    var t1 = io.async(pacman.get, .{ io, allocator, "https://api.example.com/users", .{} });
    defer { _ = t1.cancel(io) catch {}; }

    var t2 = io.async(pacman.get, .{ io, allocator, "https://api.example.com/posts", .{} });
    defer { _ = t2.cancel(io) catch {}; }

    var r1 = try t1.await(io);
    defer r1.deinit();

    var r2 = try t2.await(io);
    defer r2.deinit();
}
```

### Concurrent requests with Client

```zig
pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa.allocator();

    var client = pacman.Client.init(io, allocator, .{
        .base_url = "https://api.example.com",
    });

    // Fire 3 requests concurrently — cleaner than passing io and allocator every time
    var t1 = io.async(pacman.asyncGet,  .{ &client, "/users", .{} });
    defer { _ = t1.cancel(io) catch {}; }

    var t2 = io.async(pacman.asyncPost, .{ &client, "/users", .{} });
    defer { _ = t2.cancel(io) catch {}; }

    var t3 = io.async(pacman.asyncGet,  .{ &client, "/posts", .{} });
    defer { _ = t3.cancel(io) catch {}; }

    var r1 = try t1.await(io);
    defer r1.deinit();

    var r2 = try t2.await(io);
    defer r2.deinit();

    var r3 = try t3.await(io);
    defer r3.deinit();
}
```

### Safe cancellation with defer

```zig
pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa.allocator();

    var task = io.async(pacman.get, .{ io, allocator, url, pacman.FetchOptions{} });
    defer { _ = task.cancel(io) catch {}; }

    var res = try task.await(io);
    defer res.deinit();
}
```

### Batch processing with controlled concurrency

```zig
pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa.allocator();

    // 20 concurrent requests at a time
    var task = try io.concurrent(pacman.get, .{ io, allocator, url, pacman.FetchOptions{} });
    defer { _ = task.cancel(io) catch {}; }

    var res = try task.await(io);
    defer res.deinit();
}
```

### Switching backends — zero code changes

```zig
pub fn main(init: std.process.Init) !void {
    const allocator = init.gpa.allocator();

    // Threaded (stable, production-ready)
    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    // Evented with io_uring (experimental, Linux only)
    var evented: std.Io.Evented = .init(allocator, .{});
    defer evented.deinit();
    const io = evented.io();

    // pacman.get() call is identical in both cases
    var res = try pacman.get(io, allocator, url, .{});
    defer res.deinit();
}
```

---

## API Reference

### Standalone functions

| Function | Description |
|---|---|
| `get(io, allocator, url, opts)` | HTTP GET |
| `post(io, allocator, url, opts)` | HTTP POST |
| `put(io, allocator, url, opts)` | HTTP PUT |
| `patch(io, allocator, url, opts)` | HTTP PATCH |
| `delete(io, allocator, url, opts)` | HTTP DELETE |
| `jsonBody(serialized)` | Wraps a serialized JSON string as a `Body` |

### FetchOptions

| Field | Type | Default | Description |
|---|---|---|---|
| `headers` | `[]const http.Header` | `&.{}` | Request headers |
| `body` | `?Body` | `null` | Request body |
| `query` | `[]const [2][]const u8` | `&.{}` | Query params |
| `params` | `[]const [2][]const u8` | `&.{}` | URL path params |
| `timeout_ms` | `u32` | `0` | Timeout in ms (0 = none) |

### Response

| Method | Description |
|---|---|
| `res.status` | HTTP status (`.ok`, `.not_found`, etc.) |
| `res.text()` | Body as `[]const u8` |
| `res.json(T)` | Body parsed as `std.json.Parsed(T)` |
| `res.headers.get(name)` | Header value by name (case-insensitive) |
| `res.deinit()` | Frees all memory — arena-based |

### Client

| Method | Description |
|---|---|
| `Client.init(io, allocator, opts)` | Create configured client |
| `client.get(path, opts)` | GET with baseURL prepended |
| `client.post(path, opts)` | POST with baseURL prepended |
| `client.put(path, opts)` | PUT with baseURL prepended |
| `client.patch(path, opts)` | PATCH with baseURL prepended |
| `client.delete(path, opts)` | DELETE with baseURL prepended |

### Async functions (for use with `io.async`)

| Function | Description |
|---|---|
| `asyncGet(client, path, opts)` | Async GET — pass client, not io/allocator |
| `asyncPost(client, path, opts)` | Async POST |
| `asyncPut(client, path, opts)` | Async PUT |
| `asyncPatch(client, path, opts)` | Async PATCH |
| `asyncDelete(client, path, opts)` | Async DELETE |

---

## Relation to Spider

pacman was created by the [Spider](https://www.spiderme.org/) team to provide a native HTTP client with full support for Zig 0.17's async I/O model (`std.Io`). It is maintained as a standalone library so the wider Zig community can use it independently.

---

## License

MIT

---

## Contact

seven — [7b37b3@gmail.com](mailto:7b37b3@gmail.com)