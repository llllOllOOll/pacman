# Vendored patch — Zig stdlib

## What

A partial copy of the Zig stdlib (`std/`, `compiler/`, `compiler_rt/`, `c/`,
and the loose files at the root of `lib/` — **not** the whole `lib/`, which
is 227MB; this subset is ~26MB and was validated as sufficient to compile and
test this project natively against the system's libc).

One file changed inside it: `std/http/Client.zig`, function
`connectProxied()`.

## Why

Confirmed bug: **[ziglang/zig#19878](https://github.com/ziglang/zig/issues/19878)**
— "HTTP client fails to make HTTPS requests via a proxy". After
`connectProxied()` successfully establishes the `CONNECT` tunnel, it never
performs a TLS handshake over the tunneled connection — the returned
`Connection` stays tagged `.plain` (the *proxy's* protocol, not the target's),
so a real HTTPS request through an HTTP proxy ends up being sent in
cleartext, and the destination server rejects it with `400 Bad Request` /
"Client sent an HTTP request to an HTTPS server".

## The patch

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

## Upstream status

- Issue: [ziglang/zig#19878](https://github.com/ziglang/zig/issues/19878) (pre-existing, filed by a third party)
- Upstream PR: **not opened yet** — update this file with the link once submitted.

## When to remove this

Once Zig ships an official (non-dev) release that includes this fix:

1. Update this project's toolchain to that version.
2. Remove `vendor/zig-lib-patched/` entirely.
3. Remove the `zig_lib_dir` override from the `test_mod`/`tests` step in
   `build.zig` (the test step goes back to using the installed toolchain's
   standard stdlib).
4. Run `zig build test` and confirm the HTTPS-proxy test still passes (proof
   the official release already has the fix).

**Check this on every toolchain upgrade for this project.**
