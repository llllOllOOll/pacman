const std = @import("std");
const pacman = @import("pacman");

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var api = try pacman.Client.init(init.io, init.gpa, .{
        .base_url = "https://jsonplaceholder.typicode.com",
    });
    defer api.deinit();

    var task1 = io.async(pacman.asyncGet, .{ &api, "/posts/1", .{} });
    defer task1.cancel(io) catch {};

    var task2 = io.async(pacman.asyncPost, .{ &api, "/posts", .{} });
    defer task2.cancel(io) catch {};

    var task3 = io.async(pacman.asyncPut, .{ &api, "/posts/1", .{} });
    defer task3.cancel(io) catch {};

    var task4 = io.async(pacman.asyncPatch, .{ &api, "/posts/1", .{} });
    defer task4.cancel(io) catch {};

    var task5 = io.async(pacman.asyncDelete, .{ &api, "/posts/1", .{} });
    defer task5.cancel(io) catch {};

    var r1 = try task1.await(io);
    defer r1.deinit();

    var r2 = try task2.await(io);
    defer r2.deinit();

    var r3 = try task3.await(io);
    defer r3.deinit();

    var r4 = try task4.await(io);
    defer r4.deinit();

    var r5 = try task5.await(io);
    defer r5.deinit();

    std.debug.print("GET    /posts/1  → {d}\n", .{r1.status});
    std.debug.print("POST   /posts    → {d}\n", .{r2.status});
    std.debug.print("PUT    /posts/1  → {d}\n", .{r3.status});
    std.debug.print("PATCH  /posts/1  → {d}\n", .{r4.status});
    std.debug.print("DELETE /posts/1  → {d}\n", .{r5.status});
}
