# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

`ichiproxy` is a **learning project**. The goals — in this order — are:

1. Use the [`rio`](https://hackage.haskell.org/package/rio) library as a replacement for `Prelude`.
2. Learn the **`ReaderT` pattern** via `rio`'s `RIO env a = ReaderT env IO a`.
3. As the first concrete milestone, build an **HTTPS pass-through proxy** — i.e. an HTTP proxy that handles the `CONNECT` method by opening a TCP tunnel between the client and the upstream host:port, and blindly copying bytes in both directions. No TLS termination, no MITM, no content inspection.

When in doubt, optimize for *learning the pattern* over shipping features. Prefer the idiomatic `rio` way (e.g. `RIO env`, `HasLogFunc`, `logInfo`) even where vanilla `IO` would be shorter.

## Repository state

`library ichiproxy` (exposed modules under `src/Ichiproxy/`) + thin `executable ichiproxy` (`app/Main.hs`) that depends on it. The executable parses `--host` / `--port` via `optparse-simple`, builds the `Env`, and calls `Ichiproxy.Net.acceptLoop`.

Current modules:

- `Ichiproxy.Env` — the shared `Env` record, the per-connection `ConnEnv` wrapper, `TraceId`, the `Has*` classes (`HasListener`, `HasConn`, `HasPeer`) and instances. `ConnEnv` embeds `Env` by value; `HasLogFunc ConnEnv` delegates via `outerL . logFuncL`. Per-connection trace IDs are prefixed by swapping the embedded `envLogFunc` for a `setLogFormat`-derived `LogFunc` built per-accept from the global `envLogOpts` (which is why `Env` carries `envLogOpts` alongside `envLogFunc`).
- `Ichiproxy.Net` — `openListenerIO` (binds via `getAddrInfo`, so `0.0.0.0` / `::` / hostnames all work), `acceptLoop :: RIO Env ()`, and the unexported `handleConn :: (HasLogFunc env, HasConn env, HasPeer env) => RIO env ()` — currently just logs `"got connection from <peer>"` and closes. Each accepted connection runs in a new `async` thread with its own per-conn `LogFunc` cleaned up via `finally`.

CONNECT parsing has **not** been written yet — that's the next milestone (see below). Test suite still absent.

## `rio` conventions (apply to every new module)

- Prelude is swapped via `NoImplicitPrelude` (set in `default-extensions` in `ichiproxy.cabal`) — every module starts with `import RIO`. Do *not* switch to the `mixins:` style; keep the swap explicit and visible per file.
- Other `default-extensions` already on: `NoFieldSelectors`, `OverloadedStrings`, `OverloadedLists`, `OverloadedRecordDot`, `LambdaCase`, `ViewPatterns`, `StrictData`. Don't re-declare these per module; do add module-local pragmas for anything narrower (`{-# LANGUAGE RecordWildCards #-}`, etc.).
- `StrictData` is on, so every record/data field is strict by default — don't add redundant `!` annotations. When you actually need a lazy field (recursive streams, knot-tying), opt out with `~`: `data Stream a = Stream { hd :: a, tl :: ~(Stream a) }`. The heavier `Strict` extension is intentionally **off** — function args and `let` bindings stay lazy.
- `OverloadedRecordDot` + `NoFieldSelectors`: prefer `env.logFunc` over `logFunc env`. Mind the whitespace — `a.b` is field access, `a . b` is function composition. Because `NoFieldSelectors` is on, the auto-generated selector function (`logFunc :: App -> LogFunc`) doesn't exist, so the standard `rio` lens recipe must be written with the dot getter: `logFuncL = lens (\x -> x.appLogFunc) (\x y -> x { appLogFunc = y })`. Record-update syntax is unaffected. `OverloadedRecordUpdate` is intentionally **off**.
- Pull submodules from `RIO.ByteString`, `RIO.Text`, `RIO.Map`, `RIO.Process`, etc. — *not* from the underlying `bytestring` / `text` packages directly. This is the whole point of using `rio`.
- The app type is `RIO Env a`. Define a single `Env` record holding shared resources (`logFunc`, config, connection pools, …) and write `HasFoo Env` instances so individual functions can declare narrow constraints (`(HasLogFunc env, HasProxyConfig env) => RIO env ()`) instead of demanding the whole `Env`.
- Bootstrap with `runRIO env action`. `app/Main.hs` already runs `logOptionsHandle stderr verbose >>= \opts -> withLogFunc opts $ \lf -> runRIO (Env lf …) acceptLoop` — that's the shape; don't regress to `runSimpleApp`, which lacks a custom `Env`.
- Don't reintroduce `String`/`Prelude.IO` helpers when `rio` exposes a `Text`/`ByteString` equivalent.

## HTTPS pass-through proxy notes (first milestone)

Status: listener + per-conn `async` + trace-id-prefixed `LogFunc` are done in `Ichiproxy.Net`. CONNECT parsing, upstream dial, and the byte splice are still TODO — `handleConn` currently just logs the peer and closes.

Scope for v0:

- Listen on a TCP port — done via raw `Network.Socket` in `openListenerIO`. (We didn't reach for `Network.Run.TCP`; if higher-level needs appear, `network-run` is fine.)
- Parse just enough of the HTTP request line to recognize `CONNECT host:port HTTP/1.1`.
- Reply with `HTTP/1.1 200 Connection established\r\n\r\n`.
- Open a TCP connection to `host:port` and splice bytes both ways until either side closes. Two `RIO env ()` workers racing under `concurrently_` / `race_` is the natural shape.
- Plain `GET`/`POST` forwarding is **out of scope** until the CONNECT tunnel works end-to-end (verify with `curl -x http://localhost:PORT https://example.com -v`).

Things to consciously *not* do yet: TLS termination, certificate generation, request rewriting, auth, caching. Those are later milestones — keep the first one boring.

## Build / run

Standard Cabal — no `stack.yaml`, no `cabal.project`.

```bash
cabal build
cabal run ichiproxy                          # defaults: --host 127.0.0.1 --port 8080
cabal run ichiproxy -- --host 0.0.0.0 -p 8080
cabal run ichiproxy -- --help                # show all flags
cabal repl lib:ichiproxy                     # ghci with the library loaded
cabal clean
```

No test suite exists yet. When adding one, prefer `hspec` (which `rio` already integrates with via `RIO.Orphans` / `runRIO` in test setup) and a `test-suite` stanza; run it with `cabal test --test-show-details=streaming`.

## Toolchain pins (from `ichiproxy.cabal`)

- `cabal-version: 3.4`
- `default-language: GHC2021` — assume those extensions are on; only list extras (e.g. `NoImplicitPrelude`, `OverloadedStrings`, `RecordWildCards`) when actually needed.
- `build-depends`: library uses `base ^>=4.18.3.0, rio, network`; executable adds `optparse-simple` and depends on the `ichiproxy` library itself. GHC 9.6.x; `rio` pulls in `bytestring`, `text`, `unliftio`, `async`, `vector`, `unordered-containers`, etc. transitively — don't re-add those to `build-depends` unless a module imports them directly.
- Two `common` stanzas: `warnings` (applies `-Wall`) and `lang` (holds `default-extensions` + `default-language`). New components should `import: warnings, lang` to inherit both.

## Conventions

- Library modules live under `src/Ichiproxy/` (listed in `exposed-modules`); `app/Main.hs` is the executable entry point and stays thin (arg parsing + `Env` construction + `runRIO env acceptLoop`). A future `test-suite` stanza just adds `build-depends: ichiproxy, hspec` and can `import Ichiproxy.Env` directly.
- New library modules go under the `Ichiproxy.*` namespace. Don't reach for the `Internal` suffix convention — that's a library-author signal for unstable public API, and this isn't a published library.
- Keep `CHANGELOG.md` in sync with `version:` (PVP).
