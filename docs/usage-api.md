# Usage API reference (`/api/oauth/usage`)

How the island usage bar gets real subscription usage. This endpoint is **undocumented
and unofficial** — reverse-engineered from the Claude Code bundle and confirmed against a
live call (2026-06-09, Claude Code 2.1.169). It can change without notice; if the bar
breaks, re-verify the facts below against a fresh bundle.

## Endpoint

```
GET https://api.anthropic.com/api/oauth/usage
```

Headers:

| Header | Value |
|---|---|
| `Authorization` | `Bearer <oauth_access_token>` |
| `anthropic-beta` | `oauth-2025-04-20` |
| `Content-Type` | `application/json` |

This is the exact call Claude Code's `/usage` makes. In the bundle it appears as
`fetchUtilization: GET /api/oauth/usage`, via an internal client with `refreshOAuth:true`
(it refreshes the token and retries once on 401).

## Auth token

The OAuth access token lives in the **macOS login keychain**, not in
`~/.claude/.credentials.json` (that file only holds MCP tokens).

- Keychain item: generic password, **service = `Claude Code-credentials`**.
- The secret is a JSON blob; the token is at `claudeAiOauth.accessToken`.
- Sibling fields: `claudeAiOauth.refreshToken`, `.expiresAt` (epoch ms),
  `.subscriptionType` (e.g. `max`), `.rateLimitTier`, `.scopes`.

Claude Code keeps this token fresh while it runs. The island app just re-reads the
keychain on each poll and uses whatever token is stored; on a 401 (expired token,
Claude Code not running to refresh it) the fetch fails and the bar keeps its last value.

**Keychain prompt:** the island app is signed separately from Claude Code, so the first
`SecItemCopyMatching` read triggers a macOS access prompt. "Always Allow" silences it.
Because the app is ad-hoc signed, the signing identity changes on every rebuild, so the
prompt can reappear after a fresh `Scripts/bundle.sh`. A stable self-signed certificate
would fix that.

## Response shape

```json
{
  "five_hour":        { "utilization": 16.0, "resets_at": "2026-06-09T12:00:00.180558+00:00" },
  "seven_day":        { "utilization": 11.0, "resets_at": "2026-06-13T21:00:00.180584+00:00" },
  "seven_day_opus":   null,
  "seven_day_sonnet": { "utilization": 2.0,  "resets_at": "2026-06-13T21:00:01.180593+00:00" },
  "seven_day_oauth_apps": null,
  "extra_usage": { "is_enabled": false, "monthly_limit": null, "used_credits": null,
                   "utilization": null, "currency": null, "disabled_reason": null }
}
```

- Each window: `utilization` (0–100 number) + `resets_at` (ISO-8601, fractional seconds + offset).
- Many windows are nullable (only present for relevant plans/models). Other keys seen in
  the bundle: `seven_day_cowork`, `seven_day_omelette`, `tangelo`, `iguana_necktie`,
  `omelette_promotional`, `cinder_cove`, plus overage fields (`overageResetsAt`,
  `overageDisabledReason`).

UI mapping in the bundle: `five_hour` → "session limit" (the `5h` segment),
`seven_day` → "weekly limit" (the `7d` segment), `seven_day_opus`/`seven_day_sonnet` →
per-model weekly limits.

## Where this is implemented

- `Sources/IslandCore/Usage.swift` — `Usage.decode`, `UsageWindow`, `UsageFormat`,
  `UsageTint` (pure, unit-tested in `Tests/IslandCoreTests/UsageTests.swift`).
- `Sources/island/UsageClient.swift` — `KeychainReader.claudeAccessToken()` and
  `UsageClient.fetch()`.
- `Sources/island/AppModel.swift` — 120s poll into `@Published usage`.
- `Sources/island/IslandView.swift` — `usageBar` / `usageSegment` rendering.

## Re-verifying after a breakage

```bash
# 1. Confirm the endpoint/headers still appear in the current bundle:
BIN=$(readlink -f "$(command -v claude)")        # resolve to the versioned binary
strings -n 6 "$BIN" | grep -o "/api/oauth/usage"
strings -n 6 "$BIN" | grep -oiE "oauth-[0-9]{4}-[0-9]{2}-[0-9]{2}"   # anthropic-beta value

# 2. Live call (reads keychain; prints usage JSON, not the token):
CREDS=$(security find-generic-password -s "Claude Code-credentials" -w)
TOKEN=$(printf '%s' "$CREDS" | python3 -c "import sys,json;print(json.load(sys.stdin)['claudeAiOauth']['accessToken'])")
curl -s https://api.anthropic.com/api/oauth/usage \
  -H "Authorization: Bearer $TOKEN" \
  -H "anthropic-beta: oauth-2025-04-20" \
  -H "Content-Type: application/json" | python3 -m json.tool
```
