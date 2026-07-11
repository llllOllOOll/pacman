# Vendored patch — Zig stdlib

## What

A partial copy of the Zig stdlib (`std/`, `compiler/`, `compiler_rt/`, `c/`,
and the loose files at the root of `lib/` — **not** the whole `lib/`, which
is 227MB; this subset is ~26MB and was validated as sufficient to compile and
test this project natively against the system's libc).

One file changed inside it: `std/http/Client.zig` — two changes, described
separately below since they have different motivations and different
upstream fates.

## Change 1 — `connectProxied()` TLS-upgrade fix

### Why

Confirmed bug: **[ziglang/zig#19878](https://github.com/ziglang/zig/issues/19878)**
— "HTTP client fails to make HTTPS requests via a proxy". After
`connectProxied()` successfully establishes the `CONNECT` tunnel, it never
performs a TLS handshake over the tunneled connection — the returned
`Connection` stays tagged `.plain` (the *proxy's* protocol, not the target's),
so a real HTTPS request through an HTTP proxy ends up being sent in
cleartext, and the destination server rejects it with `400 Bad Request` /
"Client sent an HTTP request to an HTTPS server".

### The patch

- `connectProxied()` gained a `protocol: Protocol` parameter (the real
  target's protocol, which previously only existed in `connect()` and was
  never passed through).
- After the `CONNECT` tunnel is confirmed (`200 OK`), if `protocol == .tls`,
  the freshly tunneled `.plain` connection is destroyed (only the Zig-side
  wrapper — the underlying TCP stream stays open) and rebuilt as
  `Connection.Tls`, performing a real TLS handshake over the same socket.
- `connect()` (the caller) now passes `protocol` through to
  `connectProxied()`.

Known, unresolved limitation: if the proxy server sends extra bytes right
after the `200 Connection Established` response in the same network read
(rare pipelining), those bytes would be lost (they sit in the destroyed
`Plain` connection's buffer). Not observed in practice with well-behaved
proxies.

### Upstream status

- Issue: [ziglang/zig#19878](https://github.com/ziglang/zig/issues/19878) (pre-existing, filed by a third party)
- Upstream PR: **not opened yet** — update this file with the link once submitted.

### When to remove this specific change

Once Zig ships an official (non-dev) release that includes this fix:

1. Confirm this change (only) is no longer needed — see step 4 below.
2. See the combined removal checklist at the bottom of this file, since
   Change 2 (below) affects whether the whole vendor directory can go away.

## Change 2 — `adoptTunneledStream()` (new capability, not a bugfix)

### Why

Added to support SOCKS5(h) proxying (`src/socks5.zig`,
[pacman#1](https://github.com/llllOllOOll/pacman/issues/1)). SOCKS5 isn't
HTTP, so `http.Client` has no notion of it at all — there is no
`http_proxy`/`https_proxy`-style field or environment variable it
understands for SOCKS5, and no upstream issue tracking this (unlike Change
1, which is a genuine bug in existing behavior). `src/socks5.zig` in this
project dials the proxy and does the SOCKS5 handshake itself using only
already-public APIs (`Io.net.Stream`, `HostName.connect`) — no vendoring
needed for that part. The one piece that *does* require vendoring is wiring
the resulting tunneled stream into `http.Client`'s connection/pool
machinery, because `Connection.Plain.create()`/`Connection.Tls.create()` are
private to `Client.zig`.

### The patch

- New `pub fn adoptTunneledStream(client, stream, remote_host, port, protocol) !*Connection`
  in `Client.zig`. Given a stream that some external code (here,
  `src/socks5.zig`) has already fully tunneled to `remote_host:port`, this
  wraps it as `Connection.Tls` (performing the TLS handshake) or
  `Connection.Plain` depending on `protocol`, marks it `.proxied = true`, and
  registers it in `client.connection_pool` — the same Connection/pool
  machinery every other connect path in `Client.zig` uses. It does not speak
  any tunneling protocol itself and does not check the pool for reuse before
  adopting (callers should call `connection_pool.findConnection` themselves
  before dialing, to avoid handshaking a connection that ends up discarded —
  `proxy.connectSocks5()` in this project's `src/proxy.zig` does exactly
  that).

Known, unresolved limitation, same class as Change 1's: `src/socks5.zig`'s
`connect()` (the code that feeds the stream into `adoptTunneledStream`) reads
the SOCKS5 handshake replies through a buffered `stream.reader()`. That
reader's underlying fill can pull more bytes from the socket than the exact
handshake size in a single `recv()` — e.g. if the proxy sends the CONNECT
reply and the very first tunneled bytes close together. Any such extra bytes
end up sitting in `connect()`'s local read buffer and are lost once it
returns (only the raw `stream`, not the reader or its buffer, reaches
`adoptTunneledStream`). Not observed in practice with well-behaved SOCKS5
proxies, which don't pipeline tunnel data ahead of the handshake completing.

### Upstream status

- Not proposed upstream. This is a generically useful capability (adopting
  an externally-tunneled stream — the same shape of problem would apply to
  any non-HTTP tunneling protocol, not just SOCKS5), so it could plausibly be
  proposed as a small stdlib addition on its own merits, independent of
  whether Change 1 is accepted. Not done yet — update this section if it is.

### When to remove this specific change

**This one likely does NOT go away just because Zig ships a new release** —
unless `adoptTunneledStream` (or an equivalent) is separately proposed and
accepted upstream. Don't assume removing `vendor/zig-lib-patched/` is safe
just because Change 1's bug got fixed officially; check both changes
independently.

## Combined removal checklist

Before deleting `vendor/zig-lib-patched/` entirely, confirm **both**:

1. Change 1: an official (non-dev) Zig release fixes
   [ziglang/zig#19878](https://github.com/ziglang/zig/issues/19878) — verify
   by running the HTTPS-through-HTTP-proxy test against that toolchain.
2. Change 2: that same release (or a later one) exposes some way to adopt an
   externally-tunneled stream as an `http.Client` `Connection` — verify by
   porting `adoptTunneledStream`'s call site in `src/proxy.zig` to whatever
   the new API is, and running the HTTPS-through-SOCKS5 test.

If only one of the two is available upstream, keep vendoring — just shrink
the diff in this file to whichever change is still needed.

1. Update this project's toolchain to the version that has both.
2. Remove `vendor/zig-lib-patched/` entirely.
3. Remove the `zig_lib_dir` override from the `test_mod`/`tests` step in
   `build.zig` (the test step goes back to using the installed toolchain's
   standard stdlib).
4. Run `zig build test` with both `PACMAN_TEST_HTTP_PROXY` and
   `PACMAN_TEST_SOCKS5_PROXY` set and confirm both proxy tests still pass.

**Check this on every toolchain upgrade for this project.**
