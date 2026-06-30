# CLAUDE.md

Guidance for working in this repo. See also `docs/superpowers/ENVIRONMENT.md`
for the toolchain quirks (use Homebrew Swift, tests use Swift Testing).

## Build & bundle

- This machine's default Swift toolchains are broken — use Homebrew Swift.
  `Scripts/bundle.sh` already hardcodes `/opt/homebrew/opt/swift/bin/swift`
  (override with `$SWIFT`).
- Build the app bundle: `./Scripts/bundle.sh` → produces `build/island.app`.
- Version/build numbers come from `git describe`; a clean tag checkout gives a
  bare `X.Y.Z`, a dev checkout gives `X.Y.Z-N-gHASH[-dirty]`.

## Running & restarting locally

- Rebuild **and** restart in one step: `./Scripts/restart.sh`.
- The app may run under a launchd LaunchAgent labelled `app.island.local`,
  installed at `~/Library/LaunchAgents/app.island.local.plist`. That plist is
  **local to the machine and intentionally not in this repo** — it points at
  `build/island.app` with `RunAtLoad` + `KeepAlive` (auto-start on login,
  auto-relaunch on crash).
- Because of `KeepAlive`, **do not `pkill` the process** to restart it —
  launchd will immediately relaunch the *old* binary. Instead kick it:
  ```bash
  launchctl kickstart -k gui/$(id -u)/app.island.local
  ```
  `Scripts/restart.sh` does this automatically (and falls back to `open` when
  the LaunchAgent isn't loaded).
- Logs (when run under launchd): `/tmp/island.out.log`, `/tmp/island.err.log`.

## Versioning & releases

- Releases are automated via **release-please** (`.github/workflows/release.yml`,
  `release-please-config.json`). Conventional-commit messages drive the version
  bump and CHANGELOG.
- **Don't hand-create a release PR.** release-please maintains a
  `chore(main): release X.Y.Z` PR automatically; merging it tags `vX.Y.Z`,
  publishes the GitHub Release, and updates `CHANGELOG.md` +
  `.release-please-manifest.json`.
- Feature work flows through a `feat/...` branch → PR → merge to `main`; the
  release PR then refreshes on its own.
