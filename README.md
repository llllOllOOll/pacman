# Pacman HTTP Client

A lightweight HTTP client library for Zig built on `std.Io` with agnostic async/await support.

## Features

- **Agnostic Async/Await**: Built on Zig's `std.Io` interface, supporting both threaded and single-threaded backends
- **Simple API**: Clean, intuitive HTTP client interface
- **Concurrency Support**: Built-in support for parallel requests and batch processing
- **Full HTTP Support**: GET, POST, PUT, PATCH, DELETE methods
- **JSON & Form Support**: Built-in support for JSON payloads and URL-encoded forms
- **Header Management**: Easy header manipulation and parsing
- **Error Handling**: Robust error handling with proper resource cleanup

## Installation

Add this to your `build.zig.zon`:

```zig
.dependencies = .{
    .fetch = .{
        .url = "https://github.com/yourusername/pacman/archive/main.tar.gz",
        .hash = "...",
    },
},
```

And to your `build.zig`:

```zig
const fetch = b.dependency("fetch", .{});
exe.addModule("fetch", fetch.module("fetch"));
```

## Usage

### Basic GET Request

```zig
const fetch = @import("fetch");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var threaded: std.Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    // Simple GET request
    var res = try fetch.get(io, allocator, "https://httpbin.org/get", .{});
    defer res.deinit();

    std.debug.print("Status: {}\n", .{res.status});
    std.debug.print("Body: {s}\n", .{res.body_text});
}
```

### POST with JSON

```zig
var res = try fetch.post(io, allocator, "https://httpbin.org/post", .{
    .body = .{ .json = "{\"hello\": \"world\"}" },
});
defer res.deinit();
```

### Concurrent Requests

See `examples/concurrency_demo.zig` for advanced concurrency patterns including:
- Parallel URL fetching
- Batch processing with controlled concurrency
- Error handling in concurrent contexts

## Examples

Check out the `examples/` directory for complete working examples:

- `async_demo.zig` - Basic async/await patterns with `std.Io`
- `concurrency_demo.zig` - Advanced concurrency patterns with HTTP requests

## API Reference

### Core Functions

- `get(io, allocator, url, opts)` - GET request
- `post(io, allocator, url, opts)` - POST request  
- `put(io, allocator, url, opts)` - PUT request
- `patch(io, allocator, url, opts)` - PATCH request
- `delete(io, allocator, url, opts)` - DELETE request

### Options (`FetchOptions`)

```zig
.method = .GET,           // HTTP method
.headers = &.{},          // Additional headers
.body = null,            // Request body (raw, json, or form)
.query = &.{},           // Query parameters
.params = &.{},          // URL path parameters
timeout_ms = 0,          // Request timeout (0 = no timeout)
```

### Response (`Response`)

```zig
.status: std.http.Status, // HTTP status code
.headers: Headers,        // Response headers
.body_text: []const u8,   // Response body as text
```

## Concurrency Patterns

Pacman is designed to work seamlessly with Zig's `std.Io` concurrency model:

### Parallel Join Pattern

```zig
// Fetch multiple URLs simultaneously
var futures = [_]std.Io.Future(void){
    io.async(fetch.get, .{ io, allocator, url1, .{} }),
    io.async(fetch.get, .{ io, allocator, url2, .{} }),
    io.async(fetch.get, .{ io, allocator, url3, .{} }),
};

for (&futures) |*future| {
    future.await(io);
}
```

### Batch Processing Pattern

```zig
// Process many requests with controlled concurrency
const batch_size = 100;
const max_concurrent = 10;

var batch_start: usize = 0;
while (batch_start < batch_size) {
    const batch_end = @min(batch_start + max_concurrent, batch_size);
    
    // Start batch
    for (batch_start..batch_end) |i| {
        futures[i] = io.async(fetch.get, .{ io, allocator, url, .{} });
    }
    
    // Wait for batch
    for (batch_start..batch_end) |i| {
        futures[i].await(io);
    }
    
    batch_start = batch_end;
}
```

## Building

```bash
# Build the library
zig build

# Run examples
zig run examples/async_demo.zig
zig run examples/concurrency_demo.zig
```

## License

MIT License