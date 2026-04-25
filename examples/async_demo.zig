const std = @import("std");
const Io = std.Io;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var threaded: Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    std.debug.print("=== Zig Async/Await Demo (Zig 0.17) ===\n\n", .{});

    // Example 1: Sequential execution (baseline)
    std.debug.print("Example 1: Sequential execution (baseline)\n", .{});
    std.debug.print("------------------------------------------\n", .{});
    {
        const start = Io.Clock.real.now(io);

        doWork(io, 1);
        doWork(io, 2);

        const end = Io.Clock.real.now(io);
        const elapsed_ns = start.durationTo(end).toNanoseconds();
        const elapsed_ms = @divTrunc(elapsed_ns, 1000000);
        std.debug.print("Total time: {d}ms (expected: ~2000ms)\n\n", .{elapsed_ms});
    }

    // Example 2: Async execution with io.async
    std.debug.print("Example 2: Async execution with io.async\n", .{});
    std.debug.print("------------------------------------------\n", .{});
    {
        const start = Io.Clock.real.now(io);

        var f1 = io.async(doWork, .{ io, 1 });
        var f2 = io.async(doWork, .{ io, 2 });

        f1.await(io);
        f2.await(io);

        const end = Io.Clock.real.now(io);
        const elapsed_ns = start.durationTo(end).toNanoseconds();
        const elapsed_ms = @divTrunc(elapsed_ns, 1000000);
        std.debug.print("Total time: {d}ms (expected: ~1000ms)\n\n", .{elapsed_ms});
    }

    // Example 3: Safe cancellation with defer
    std.debug.print("Example 3: Safe cancellation with defer\n", .{});
    std.debug.print("------------------------------------------\n", .{});
    {
        var f1 = io.async(doWork, .{ io, 1 });
        defer f1.cancel(io);

        var f2 = io.async(doWork, .{ io, 2 });
        defer f2.cancel(io);

        f1.await(io);
        f2.await(io);
        std.debug.print("Both tasks completed successfully\n\n", .{});
    }

    // Example 4: io.async vs io.concurrent
    std.debug.print("Example 4: io.async vs io.concurrent\n", .{});
    std.debug.print("------------------------------------------\n", .{});
    {
        // io.async - may or may not run in parallel
        var f1 = io.async(doWork, .{ io, 1 });
        defer f1.cancel(io);

        // io.concurrent - GUARANTEES a separate thread
        var f2 = io.concurrent(doWork, .{ io, 2 }) catch |err| {
            std.debug.print("io.concurrent failed: {}\n", .{err});
            std.debug.print("This is expected on single-threaded builds\n", .{});
            f1.cancel(io);
            return;
        };
        defer f2.cancel(io);

        f1.await(io);
        f2.await(io);
        std.debug.print("Both async and concurrent tasks completed\n\n", .{});
    }

    // Example 5: Producer/consumer with Io.Queue
    std.debug.print("Example 5: Producer/consumer with Io.Queue\n", .{});
    std.debug.print("------------------------------------------\n", .{});
    {
        var queue: Io.Queue([]const u8) = .init(&.{});

        var producer = io.concurrent(producerFn, .{ io, &queue }) catch |err| {
            std.debug.print("Producer creation failed: {}\n", .{err});
            return;
        };
        defer producer.cancel(io);

        var consumer = io.concurrent(consumerFn, .{ io, &queue }) catch |err| {
            std.debug.print("Consumer creation failed: {}\n", .{err});
            producer.cancel(io);
            return;
        };
        defer consumer.cancel(io);

        consumer.await(io);
        std.debug.print("Producer/consumer demo completed\n\n", .{});
    }

    std.debug.print("=== Demo completed successfully ===\n", .{});
}

fn doWork(io: std.Io, id: u8) void {
    std.debug.print("task {d} starting\n", .{id});
    io.sleep(.fromSeconds(1), .awake) catch {};
    std.debug.print("task {d} done\n", .{id});
}

fn producerFn(io: std.Io, queue: *Io.Queue([]const u8)) void {
    const messages = [_][]const u8{ "hello", "world", "async", "zig" };

    for (messages) |msg| {
        std.debug.print("Producer sending: {s}\n", .{msg});
        queue.*.putOne(io, msg) catch {
            std.debug.print("Producer failed to push message\n", .{});
            return;
        };
        io.sleep(.fromMilliseconds(500), .awake) catch {};
    }

    // Signal end of messages
    queue.*.putOne(io, "DONE") catch {};
    std.debug.print("Producer finished\n", .{});
}

fn consumerFn(io: std.Io, queue: *Io.Queue([]const u8)) void {
    std.debug.print("Consumer started\n", .{});

    while (true) {
        const msg = queue.*.getOne(io) catch {
            std.debug.print("Consumer failed to receive message\n", .{});
            return;
        };

        std.debug.print("Consumer received: {s}\n", .{msg});

        if (std.mem.eql(u8, msg, "DONE")) {
            std.debug.print("Consumer finished\n", .{});
            return;
        }

        io.sleep(.fromMilliseconds(200), .awake) catch {};
    }
}
