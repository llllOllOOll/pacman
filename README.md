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
const Io = std.Io;
const pacman = @import("pacman");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;

    var res = try pacman.get(io, allocator, "https://spiderme.org/drivers", .{});
    defer res.deinit();

    std.debug.print("{s}\n", .{res.text()});
}
```

---

## Usage

### Standalone requests

```zig
const std = @import("std");
const pacman = @import("pacman");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;

    // Serialize — Zig struct → JSON string
    const payload = .{ .title = "seven", .body = "hello from pacman", .userId = 1 };
    const serialized = try std.json.Stringify.valueAlloc(allocator, payload, .{});
    defer allocator.free(serialized);

    // POST with serialized JSON body
    var created = try pacman.post(io, allocator, "https://jsonplaceholder.typicode.com/posts", .{
        .body = pacman.jsonBody(serialized),
    });
    defer created.deinit();

    std.debug.print("POST → {d}\n", .{created.status});

    // Deserialize — JSON string → Zig struct
    const Post = struct { id: u32, title: []const u8 };
    const parsed = try created.json(Post);
    std.debug.print("id: {d}, title: {s}\n", .{ parsed.value.id, parsed.value.title });
}
```

### Client with baseURL and global headers

```zig
const std = @import("std");
const pacman = @import("pacman");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;

    var api = pacman.Client.init(io, allocator, .{
        .base_url = "https://jsonplaceholder.typicode.com",
        .headers = &.{
            .{ .name = "Authorization", .value = "Bearer your-token" },
            .{ .name = "Accept", .value = "application/json" },
        },
    });

    // GET users
    var users = try api.get("/users", .{});
    defer users.deinit();
    std.debug.print("GET users → {d}\n", .{users.status});

    // Serialize payload
    const payload = .{ .name = "seven", .role = "admin" };
    const serialized = try std.json.Stringify.valueAlloc(allocator, payload, .{});
    defer allocator.free(serialized);

    // POST new user
    var created = try api.post("/users", .{
        .body = pacman.jsonBody(serialized),
    });
    defer created.deinit();
    std.debug.print("POST user → {d}\n", .{created.status});
}
```

### Query params

```zig
const std = @import("std");
const pacman = @import("pacman");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;

    var api = pacman.Client.init(io, allocator, .{
        .base_url = "https://jsonplaceholder.typicode.com",
        .headers = &.{
            .{ .name = "Authorization", .value = "Bearer your-token" },
            .{ .name = "Accept", .value = "application/json" },
        },
    });

    // GET users
    var users = try api.get("/users", .{});
    defer users.deinit();
    std.debug.print("GET users → {d}\n", .{users.status});

    // Serialize payload
    const payload = .{ .name = "seven", .role = "admin" };
    const serialized = try std.json.Stringify.valueAlloc(allocator, payload, .{});
    defer allocator.free(serialized);

    // POST new user
    var created = try api.post("/users", .{
        .body = pacman.jsonBody(serialized),
    });
    defer created.deinit();
    std.debug.print("POST user → {d}\n", .{created.status});
}
```

### URL path params

```zig
const std = @import("std");
const pacman = @import("pacman");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;

    var api = pacman.Client.init(io, allocator, .{
        .base_url = "https://jsonplaceholder.typicode.com",
    });

    // GET post comments using URL path params
    var res = try api.get("/posts/:id/comments", .{
        .params = &.{
            .{ "id", "1" },
        },
    });
    defer res.deinit();

    // → GET /posts/1/comments
    std.debug.print("GET comments → {d}\n", .{res.status});
    std.debug.print("{s}\n", .{res.text()});
}
```

### Reading the response

```zig
const std = @import("std");
const pacman = @import("pacman");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;

    var api = pacman.Client.init(io, allocator, .{
        .base_url = "https://jsonplaceholder.typicode.com",
    });

    // GET post comments using URL path params
    var res = try api.get("/posts/:id/comments", .{
        .params = &.{
            .{ "id", "1" },
        },
    });
    defer res.deinit();

    // → GET /posts/1/comments
    std.debug.print("GET comments → {d}\n", .{res.status});
    std.debug.print("{s}\n", .{res.text()});
}
```

### Form body

```zig
const std = @import("std");
const pacman = @import("pacman");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;

    var api = pacman.Client.init(io, allocator, .{
        .base_url = "https://jsonplaceholder.typicode.com",
    });

    var res = try api.get("/users/1", .{});
    defer res.deinit();

    // Status code
    std.debug.print("status: {d}\n", .{res.status});

    // Body as string
    const body = res.text();
    std.debug.print("body: {s}\n", .{body});

    // Body as JSON
    const User = struct { id: u32, name: []const u8 };
    const parsed = try res.json(User);
    std.debug.print("name: {s}\n", .{parsed.value.name});

    // Response header (case-insensitive)
    const ct = res.headers.get("content-type");
    std.debug.print("content-type: {s}\n", .{ct orelse "not found"});
}
```

---

## Async/Await

pacman is built on `std.Io` — the same interface that powers Zig's async I/O. You write your code once and the caller decides the concurrency model.

**Note:** Always add `defer { _ = task.cancel(io) catch {}; }` immediately after each `io.async` call. If any `await` fails, the remaining tasks are automatically cancelled without leaking memory. The `_ =` is required because `cancel` returns a `Response` that must be explicitly discarded.


```zi
const std = @import("std");
const pacman = @import("pacman");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;

    var client = pacman.Client.init(io, allocator, .{
        .base_url = "https://spiderme.org",
    });

    var task = io.async(pacman.asyncGet, .{ &client, "/drivers", .{} });
    defer { _ = task.cancel(io) catch {}; }

    var res = try task.await(io);
    defer res.deinit();

    const Driver = struct { id: u32, name: []const u8, team: []const u8, number: i32 };
    const parsed = try res.json([]Driver);

    for (parsed.value) |driver| {
        std.debug.print("name: {s}, team: {s}, number: {d}\n", .{
            driver.name,
            driver.team,
            driver.number,
        });
    }
}
```

### Two requests in parallel

```zig
const std = @import("std");
const pacman = @import("pacman");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;

    // POST form body — automatically URL-encoded
    var res = try pacman.post(io, allocator, "https://httpbin.org/post", .{
        .body = .{ .form = &.{
            .{ "username", "seven" },
            .{ "password", "secret" },
        } },
    });
    defer res.deinit();

    std.debug.print("POST form → {d}\n", .{res.status});
    std.debug.print("{s}\n", .{res.text()});
}
```

### Concurrent requests with Client

```zig
const std = @import("std");
const pacman = @import("pacman");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;

    var t1 = io.async(pacman.get, .{ io, allocator, "https://jsonplaceholder.typicode.com/users", .{} });
    defer {
        _ = t1.cancel(io) catch {};
    }

    var t2 = io.async(pacman.get, .{ io, allocator, "https://jsonplaceholder.typicode.com/posts", .{} });
    defer {
        _ = t2.cancel(io) catch {};
    }

    var r1 = try t1.await(io);
    defer r1.deinit();

    var r2 = try t2.await(io);
    defer r2.deinit();

    std.debug.print("GET users → {d}\n", .{r1.status});
    std.debug.print("GET posts → {d}\n", .{r2.status});
}
```

### Safe cancellation with defer

```zig
const std = @import("std");
const pacman = @import("pacman");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;

    var task = io.async(pacman.get, .{ io, allocator, "https://jsonplaceholder.typicode.com/posts/1", .{} });
    defer { _ = task.cancel(io) catch {}; }

    var res = try task.await(io);
    defer res.deinit();

    std.debug.print("GET post → {d}\n", .{res.status});
}
```
For more on `defer cancel`, Andrew Kelley explains it directly in
[Zig's New Async I/O — Example 6](https://andrewkelley.me/post/zig-new-async-io-text-version.html):

> `cancel` is your best friend, because it's going to prevent you from leaking the
> resource, and it's going to make your code run more optimally. Both `cancel` and
> `await` are idempotent with respect to themselves and each other.


### Switching backends — zero code changes

**Threaded** (stable, production-ready):
```zig
var threaded: std.Io.Threaded = .init(allocator);
defer threaded.deinit();
const io = threaded.io();

var res = try pacman.get(io, allocator, "https://jsonplaceholder.typicode.com/posts/1", .{});
defer res.deinit();
```

**Evented with io_uring** (experimental, Linux only):
```zig
var evented: std.Io.Evented = .init(allocator);
defer evented.deinit();
const io = evented.io();

var res = try pacman.get(io, allocator, "https://jsonplaceholder.typicode.com/posts/1", .{});
defer res.deinit();
```

> The `pacman.get()` call is identical in both cases — swap the backend, keep the rest.
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
| `res.status` | HTTP status code (`u10`) — e.g. `200`, `404` |
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
| `asyncGet(*client, path, opts)` | Async GET — pass `*Client`, not io/allocator |
| `asyncPost(*client, path, opts)` | Async POST |
| `asyncPut(*client, path, opts)` | Async PUT |
| `asyncPatch(*client, path, opts)` | Async PATCH |
| `asyncDelete(*client, path, opts)` | Async DELETE |

> All async functions receive a `*Client` pointer as first argument and are designed
> to be used with `io.async`: `io.async(pacman.asyncGet, .{ &client, "/path", .{} })`

---

## Relation to Spider

pacman was created by the [Spider](https://www.spiderme.org/) team to provide a native HTTP client with full support for Zig 0.17's async I/O model (`std.Io`). It is maintained as a standalone library so the wider Zig community can use it independently.

---

## License

MIT

---

## Contact

seven — [7b37b3@gmail.com](mailto:7b37b3@gmail.com)
