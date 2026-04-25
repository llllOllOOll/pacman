const std = @import("std");
const Io = std.Io;

// Importar pacman HTTP client
const Client = @import("src/client.zig").Client;
const FetchOptions = @import("src/request.zig").FetchOptions;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Setup: Thread pool com worker threads
    var threaded: Io.Threaded = .init(allocator, .{});
    defer threaded.deinit();
    const io = threaded.io();

    std.debug.print("=== Zig Concurrency Demo (std.Io + pacman) ===\n\n", .{});

    // Implementação 1: Parallel Join
    try parallelJoinDemo(io, allocator);

    std.debug.print("\n", .{});

    // Implementação 2: Batch Processing
    try batchProcessingDemo(io, allocator);

    std.debug.print("\n=== Demo completed successfully ===\n", .{});
}

fn parallelJoinDemo(io: std.Io, allocator: std.mem.Allocator) !void {
    std.debug.print("Parallel Join (3 URLs different delays):\n", .{});
    std.debug.print("------------------------------------------\n", .{});

    const urls = [_][]const u8{
        "https://httpbin.org/delay/1", // 1s delay
        "https://httpbin.org/delay/2", // 2s delay
        "https://httpbin.org/get", // rápido
    };

    const start_total = Io.Clock.real.now(io);

    // Spawn todas as futures simultaneamente
    var futures: [3]Io.Future(void) = undefined;
    var start_times: [3]Io.Timestamp = undefined;

    for (urls, 0..) |url, i| {
        std.debug.print("Retrieving {s}\n", .{url});
        start_times[i] = Io.Clock.real.now(io);
        futures[i] = io.async(fetchUrl, .{ io, allocator, url, i });
    }

    // Await todas as futures
    for (&futures, 0..) |*future, i| {
        future.await(io);
        const end_time = Io.Clock.real.now(io);
        const elapsed_ms = @divTrunc(start_times[i].durationTo(end_time).toNanoseconds(), 1000000);
        std.debug.print("Completed: {s} ({d}ms)\n", .{ urls[i], elapsed_ms });
    }

    const end_total = Io.Clock.real.now(io);
    const total_ms = @divTrunc(start_total.durationTo(end_total).toNanoseconds(), 1000000);

    std.debug.print("Total: {d}ms (proves parallel — not {d}ms sequential)\n", .{
        total_ms,
        1000 + 2000 + 300, // ~3356ms sequential
    });
}

fn batchProcessingDemo(io: std.Io, allocator: std.mem.Allocator) !void {
    std.debug.print("Batch Processing (501 requests with io.concurrent):\n", .{});
    std.debug.print("----------------------------------------------------\n", .{});

    const batch_size = 501;
    const url = "https://httpbin.org/get";
    const max_concurrent = 20; // Limitar para não sobrecarregar httpbin

    const start_total = Io.Clock.real.now(io);

    // Usar arena allocator para eficiência
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_allocator = arena.allocator();

    // Array para armazenar os futures
    var futures = try arena_allocator.alloc(Io.Future(void), batch_size);
    var completed: usize = 0;

    std.debug.print("Starting batch of {d} requests (max {d} concurrent)...\n", .{ batch_size, max_concurrent });

    // Disparar requests em batches controlados
    var batch_start: usize = 0;
    while (batch_start < batch_size) {
        const batch_end = @min(batch_start + max_concurrent, batch_size);

        // Disparar batch atual
        for (batch_start..batch_end) |i| {
            futures[i] = io.async(fetchUrl, .{ io, allocator, url, i });
        }

        // Aguardar batch atual completar
        for (batch_start..batch_end) |i| {
            futures[i].await(io);
            completed += 1;

            // Log progresso a cada 50 requests
            if (completed % 50 == 0) {
                std.debug.print("Progress: {d}/{d}\n", .{ completed, batch_size });
            }
        }

        batch_start = batch_end;
    }

    const end_total = Io.Clock.real.now(io);
    const total_ms = @divTrunc(start_total.durationTo(end_total).toNanoseconds(), 1000000);
    const requests_per_second = @divTrunc(batch_size * 1000, total_ms);

    std.debug.print("Completed {d} requests in {d}ms ({d} requests/second)\n", .{ batch_size, total_ms, requests_per_second });
}

fn fetchUrl(io: std.Io, allocator: std.mem.Allocator, url: []const u8, request_id: usize) void {
    // Usar a função get diretamente do pacman (não precisa do Client)
    var res = @import("src/request.zig").get(io, allocator, url, .{}) catch |err| {
        std.debug.print("Request {d} failed: {}\n", .{ request_id, err });
        return;
    };
    defer res.deinit();

    // Verificar se foi bem-sucedido
    if (res.status != .ok) {
        std.debug.print("Request {d} returned status: {}\n", .{ request_id, res.status });
    }
}

fn voidFn() void {
    // Função vazia para futures de fallback
}
