const std = @import("std");
const http = std.http;

pub const Headers = struct {
    items: []http.Header,
};
