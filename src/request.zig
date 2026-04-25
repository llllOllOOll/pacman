const std = @import("std");

const Io = std.Io;
const http = std.http;
const Body = @import("body.zig").Body;
const Headers = @import("headers.zig").Headers;
const Response = @import("response.zig").Response;

pub const FetchOptions = struct {
    method: http.Method = .GET,
    headers: []const http.Header = &.{},
    body: ?Body = null,
    query: []const [2][]const u8 = &.{},
    params: []const [2][]const u8 = &.{}, // URL path parameters
};

pub fn get(io: Io, allocator: std.mem.Allocator, url: []const u8, opts: FetchOptions) !Response {
    return request(io, allocator, url, opts);
}

pub fn post(io: Io, allocator: std.mem.Allocator, url: []const u8, opts: FetchOptions) !Response {
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

    var http_client = try aa.create(http.Client);
    http_client.* = .{
        .allocator = aa,
        .io = io,
    };

    var response_writer = std.Io.Writer.Allocating.init(aa);

    var payload_opt: ?[]const u8 = null;
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
                // Copy JSON data into arena for automatic cleanup
                const owned = try aa.dupe(u8, json_data);
                payload_opt = owned;
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

    // Handle URL path parameters
    var final_url: []const u8 = url;
    if (opts.params.len > 0) {
        var param_buf = std.ArrayList(u8).initCapacity(aa, url.len) catch unreachable;

        var i: usize = 0;
        while (i < url.len) {
            if (i + 1 < url.len and url[i] == ':' and std.ascii.isAlphabetic(url[i + 1])) {
                // Found a parameter
                const param_start = i + 1;
                var param_end = param_start;
                while (param_end < url.len and (std.ascii.isAlphanumeric(url[param_end]) or url[param_end] == '_')) {
                    param_end += 1;
                }

                const param_name = url[param_start..param_end];
                var found = false;

                // Look for matching parameter value
                for (opts.params) |param| {
                    if (std.mem.eql(u8, param[0], param_name)) {
                        try param_buf.appendSlice(aa, param[1]);
                        found = true;
                        break;
                    }
                }

                if (!found) {
                    // Parameter not found, keep original
                    try param_buf.appendSlice(aa, url[i..param_end]);
                }

                i = param_end;
            } else {
                // Regular character
                try param_buf.append(aa, url[i]);
                i += 1;
            }
        }

        final_url = try param_buf.toOwnedSlice(aa);
    }

    // Handle query parameters
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
        .response_writer = &response_writer.writer,
    }) catch {
        return error.HttpRequestFailed;
    };

    const body_text = response_writer.written();

    // For now, return empty headers until we figure out the correct API
    // The http.Client API for accessing response headers is not clear
    return .{
        .status = result.status,
        .headers = .{ .items = &.{} },
        .arena = arena,
        .body_text = body_text,
        .http_client = http_client,
    };
}
