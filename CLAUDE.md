# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

`ichiproxy` is a **learning project**. The goals — in this order — are:

1. Use the [`rio`](https://hackage.haskell.org/package/rio) library as a replacement for `Prelude`.
2. Learn the **`ReaderT` pattern** via `rio`'s `RIO env a = ReaderT env IO a`.
3. As the first concrete milestone, build an **HTTPS pass-through proxy** — i.e. an HTTP proxy that handles the `CONNECT` method by opening a TCP tunnel between the client and the upstream host:port, and blindly copying bytes in both directions. No TLS termination, no MITM, no content inspection.

When in doubt, optimize for *learning the pattern* over shipping features. Prefer the idiomatic `rio` way (e.g. `RIO env`, `HasLogFunc`, `logInfo`) even where vanilla `IO` would be shorter.

## Repository state

Currently a `cabal init` skeleton: one executable `ichiproxy` with `app/Main.hs` printing `"Hello, Haskell!"`. No library stanza, no tests, no `rio` dependency yet. When you add the first real modules, update this file with the actual module layout and env type.

## `rio` conventions (apply to every new module)

- Replace `Prelude` with `RIO`. Either flip on `NoImplicitPrelude` in `default-extensions` and `import RIO`, or use `mixins: base hiding (Prelude), rio (RIO as Prelude)` in the cabal file. Pick one approach and stay consistent.
- Pull submodules from `RIO.ByteString`, `RIO.Text`, `RIO.Map`, `RIO.Process`, etc. — *not* from the underlying `bytestring` / `text` packages directly. This is the whole point of using `rio`.
- The app type is `RIO Env a`. Define a single `Env` record holding shared resources (`logFunc`, config, connection pools, …) and write `HasFoo Env` instances so individual functions can declare narrow constraints (`(HasLogFunc env, HasProxyConfig env) => RIO env ()`) instead of demanding the whole `Env`.
- Bootstrap with `runRIO env action`. Build `logFunc` via `logOptionsHandle stderr verbose >>= \opts -> withLogFunc opts $ \lf -> runRIO (Env lf …) app`.
- Don't reintroduce `String`/`Prelude.IO` helpers when `rio` exposes a `Text`/`ByteString` equivalent.

## HTTPS pass-through proxy notes (first milestone)

Scope for v0:

- Listen on a TCP port (e.g. via `network`'s `Socket` API; `Network.Run.TCP` from `network-run` is fine).
- Parse just enough of the HTTP request line to recognize `CONNECT host:port HTTP/1.1`.
- Reply with `HTTP/1.1 200 Connection established\r\n\r\n`.
- Open a TCP connection to `host:port` and splice bytes both ways until either side closes. Two `RIO env ()` workers racing under `concurrently_` / `race_` is the natural shape.
- Plain `GET`/`POST` forwarding is **out of scope** until the CONNECT tunnel works end-to-end (verify with `curl -x http://localhost:PORT https://example.com -v`).

Things to consciously *not* do yet: TLS termination, certificate generation, request rewriting, auth, caching. Those are later milestones — keep the first one boring.

## Build / run

Standard Cabal — no `stack.yaml`, no `cabal.project`.

```bash
cabal build
cabal run ichiproxy           # build + run
cabal run ichiproxy -- --port 8080   # pass args after `--`
cabal repl                    # ghci with the project loaded
cabal clean
```

No test suite exists yet. When adding one, prefer `hspec` (which `rio` already integrates with via `RIO.Orphans` / `runRIO` in test setup) and a `test-suite` stanza; run it with `cabal test --test-show-details=streaming`.

## Toolchain pins (from `ichiproxy.cabal`)

- `cabal-version: 3.4`
- `default-language: GHC2021` — assume those extensions are on; only list extras (e.g. `NoImplicitPrelude`, `OverloadedStrings`, `RecordWildCards`) when actually needed.
- `build-depends: base ^>=4.18.3.0` — GHC 9.6.x. Adding `rio` will pull in `bytestring`, `text`, `unliftio`, etc. transitively; don't re-add them to `build-depends` unless a module uses them directly.
- `-Wall` is applied via the `warnings` common stanza; new components should `import: warnings` to inherit it.

## Conventions

- Source under `app/` today (per `hs-source-dirs: app`). Once non-trivial logic appears, move it into a `library` stanza under `src/` so it can be imported by both the executable and a future test suite; keep `app/Main.hs` as a thin entry point that builds `Env` and calls `runRIO env run`.
- Keep `CHANGELOG.md` in sync with `version:` (PVP).
