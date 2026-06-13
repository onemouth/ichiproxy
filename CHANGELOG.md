# Revision history for ichiproxy

## 0.1.0.0 -- 2026-06-13

* Initial release.
* HTTPS pass-through proxy via HTTP `CONNECT`.
* CLI flags `--host` / `--port` (defaults: `127.0.0.1` / `8080`).
* Per-connection trace IDs in log output.
* Returns `400 Bad Request` for non-CONNECT requests,
  `502 Bad Gateway` on upstream dial failure.
