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

    var api = try pacman.Client.init(io, allocator, .{
        .base_url = "https://jsonplaceholder.typicode.com",
        .headers = &.{
            .{ .name = "Authorization", .value = "Bearer your-token" },
            .{ .name = "Accept", .value = "application/json" },
        },
    });
    defer api.deinit();

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

> Using `Client` (instead of repeated standalone calls) also reuses TCP/TLS
> connections across requests to the same host — each `.get()/.post()/etc`
> call goes through the same persistent connection pool instead of dialing
> fresh every time. This is the recommended way to make several requests to
> the same host.

### Query params

```zig
const std = @import("std");
const pacman = @import("pacman");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;

    var api = try pacman.Client.init(io, allocator, .{
        .base_url = "https://jsonplaceholder.typicode.com",
        .headers = &.{
            .{ .name = "Authorization", .value = "Bearer your-token" },
            .{ .name = "Accept", .value = "application/json" },
        },
    });
    defer api.deinit();

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

    var api = try pacman.Client.init(io, allocator, .{
        .base_url = "https://jsonplaceholder.typicode.com",
    });
    defer api.deinit();

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

    var api = try pacman.Client.init(io, allocator, .{
        .base_url = "https://jsonplaceholder.typicode.com",
    });
    defer api.deinit();

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

    var api = try pacman.Client.init(io, allocator, .{
        .base_url = "https://jsonplaceholder.typicode.com",
    });
    defer api.deinit();

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

    var client = try pacman.Client.init(io, allocator, .{
        .base_url = "https://spiderme.org",
    });
    defer client.deinit();

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
| `proxy_url` | `?[]const u8` | `null` | Explicit proxy URL (`http://`, `https://`, `socks5://`, `socks5h://`) — overrides env vars for this request |

### Using a proxy

Requests go through a proxy in one of two ways, checked in this order:

1. **Explicit**, via `FetchOptions.proxy_url`:

   ```zig
   var res = try pacman.get(io, allocator, "https://httpbin.org/get", .{
       .proxy_url = "http://user:pass@proxy.example.com:8080",
   });
   ```

   With `pacman.Client`, the proxy is fixed once at `Client.init()` time (via
   its own `proxy_url` option, same env-var fallback as below) — it isn't
   re-evaluated per call. A per-call `opts.proxy_url` that differs from what
   the Client was initialized with is a usage error
   (`error.ProxyMismatch`), not silently ignored: the underlying
   `http.Client` is a persistent, shared connection pool, and its proxy
   fields can't be safely reconfigured on every request without racing
   concurrent in-flight requests through the same client. For per-call
   proxy control, use the standalone functions instead.

   SOCKS5(h) works the same way — just change the scheme:

   ```zig
   var res = try pacman.get(io, allocator, "https://httpbin.org/get", .{
       .proxy_url = "socks5h://127.0.0.1:1080",
   });
   ```

   `socks5h://` resolves the target hostname on the proxy side (never locally) — this is
   almost always what you want. Plain `socks5://` is also accepted for compatibility,
   with the same behavior.

2. **Environment variables**, if `proxy_url` is omitted: `http_proxy`/`HTTP_PROXY` and
   `https_proxy`/`HTTPS_PROXY` for HTTP(S) proxies, `all_proxy`/`ALL_PROXY` for either
   HTTP(S) or SOCKS5(h) (scheme-dependent), and `no_proxy`/`NO_PROXY` to exclude specific
   hosts. With nothing set, no proxy is used — this is fully opt-in.

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
| `Client.init(io, allocator, opts)` | Create configured client (fallible: `try Client.init(...)`) |
| `client.deinit()` | Close the persistent connection pool |
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

## Vendored Zig Stdlib Patch

`vendor/zig-lib-patched/` is a local copy of the Zig standard library (specifically
`lib/std/http/Client.zig`) with three patches applied, documented in full in
`vendor/zig-lib-patched/PATCH_NOTES.md`. It exists because pacman needs behavior the
official stdlib doesn't have — or hasn't fixed — yet, in the exact Zig version this
project targets.

> **⚠️ Not currently wired into the build.** `build.zig`'s `test` step no longer
> overrides `zig_lib_dir` to point at this vendor copy — `zig build test` (and any
> other build step) uses whatever stdlib ships with your own `zig` toolchain. This
> vendor directory is now a **reference/patch source**, not something the build
> applies for you.
>
> `src/proxy.zig` calls `adoptTunneledStream()` (Change 2 below) directly, which only
> exists on a stdlib that has these patches. **If your `zig` toolchain's own stdlib
> doesn't already have them, pacman will fail to compile** (missing
> `adoptTunneledStream`) — or, if you stub that part out, will silently reintroduce
> the bugs Changes 1 and 3 fix (cleartext HTTPS-through-proxy requests, and a
> use-after-free on a failed TLS handshake over a proxy tunnel). Until Zig core fixes
> [ziglang/zig#19878](https://github.com/ziglang/zig/issues/19878) and ships some way
> to adopt an externally-tunneled stream, if you want to build/test pacman yourself
> you need to apply this patch to your own local stdlib — see "Applying the patch
> locally" below.

### Change 1 — HTTPS-through-HTTP-proxy bugfix

`connectProxied()` establishes a `CONNECT` tunnel through an HTTP proxy but never
performs a TLS handshake over it, even when the real target is HTTPS — the connection
stays tagged `.plain`, so the request goes out in cleartext and the destination server
rejects it. This is a known upstream bug, open since 2024 and still unfixed in the Zig
version this project uses: [ziglang/zig#19878](https://github.com/ziglang/zig/issues/19878).

This is a straight bugfix, not new functionality. When an official Zig release ships
the fix, this specific change can be removed from the vendor copy.

### Change 2 — `adoptTunneledStream()`

A new function, not a bugfix: it adopts a stream that's already been tunneled by
external code (used by this project's SOCKS5(h) support) and wires it into
`http.Client`'s connection/TLS machinery. There's no upstream issue for this because
there's no upstream behavior to fix — `std.http.Client` simply has no concept of
non-HTTP tunneling protocols.

Because it's an addition rather than a correction, this change will likely still be
needed even after Change 1 is fixed officially, unless it's separately proposed and
accepted upstream as public API.

### Change 3 — `connectProxied()` use-after-free fix on TLS-handshake failure

A use-after-free introduced by Change 1's own TLS-upgrade code: once the `CONNECT`
tunnel is confirmed, the tunneled `.plain` `Connection` is destroyed and rebuilt as
`.tls` so a real TLS handshake can happen over it. If that handshake then fails (e.g.
the proxy hangs up right after confirming the tunnel), a stale `errdefer` used to
write into the now-freed `Connection` — reproduced locally, segfaults. Fixed by
guarding the `errdefer` with a `connection_freed` flag and explicitly closing the raw
stream on the TLS-create failure path. Covered by a regression test in `src/root.zig`
(`"HTTP(S) proxy: tunnel closed before TLS handshake does not crash (UAF regression)"`)
that spins up a local fake-proxy TCP listener — no real proxy or network access
needed to reproduce or verify this one.

### Applying the patch locally

To build or test pacman against a stock/official Zig toolchain (one that doesn't
already carry these three changes):

1. Find your `zig` toolchain's stdlib directory — next to the `zig` binary itself, or
   check `zig env` for `std_dir`.
2. Copy `vendor/zig-lib-patched/std/http/Client.zig` over that toolchain's
   `lib/std/http/Client.zig` (if your Zig version differs from the one this vendor
   copy was cut against, diff the two `Client.zig` files first — this is not a
   version-pinned patch file, it's a full copy of an already-patched version).
3. Run `zig build test` — it should now compile and pass against your toolchain's
   (now-patched) stdlib.

If you'd rather not touch an existing install, build your own Zig toolchain from
source with these changes applied directly to `lib/std/http/Client.zig`, and point
`zig` at that build instead.

### Disclosure

This patch was developed with AI assistance and reviewed personally before
being applied — including isolated validation via `--zig-lib-dir` against a scratch
copy of the stdlib, automated tests, and a line-by-line review of the SOCKS5 protocol
parsing code before any real network execution.

### Intent

The long-term goal is to upstream Changes 1 and 3 together as one PR to
`ziglang/zig` (referencing issue #19878 — Change 3 only exists because of Change 1's
own code, so they should land together) and drop both from this vendor copy once/if
accepted. Until then, vendoring solves the practical problem now, without depending
on the Zig project's timeline for reviewing external contributions.

---

## License

MIT

---

## Contact

seven — [7b37b3@gmail.com](mailto:7b37b3@gmail.com)
