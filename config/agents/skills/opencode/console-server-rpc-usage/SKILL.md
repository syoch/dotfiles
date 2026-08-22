---
name: console-server-rpc-usage
description: Use when querying the opencode.ai console's authoritative server-side usage data (Go/Zen usage, billing balance, per-request UsageTable records) via the `/_server` RPC endpoint with a browser session cookie — unlike the local SQLite DB, this survives session deletion. Trigger keywords: _server endpoint, opencode console RPC, queryBilling, getCosts, getUsageInfo, usage.list, seroval 1.3.2 serialization, X-Server-Id header, opencode Go quota, opencode.ai/_server, cookie auth usage stats.
---

# Query opencode.ai console usage via `/_server` RPC

Use when you need the **authoritative server-side** usage/billing data from opencode.ai (OpenCode Go/Zen usage, per-request `UsageTable` records, balance, subscription) that survives local session deletion — the local SQLite DB (`~/.local/share/opencode/opencode-*.db`) becomes inaccurate after `opencode session delete`.

## When to use
- Analyze actual Go plan quota consumption (5h/1w/1m windows, dollar value) when the local DB undercounts
- Get full per-request usage: model, provider, input/output/reasoning/cache tokens, cost, sessionID
- Compare cost-effectiveness of OpenCode Go vs OpenRouter using server-side truth
- Check balance, subscription/lite status, monthly limit server-side

## Procedure

1. **Get a browser session cookie** — the console authenticates via the `auth` cookie (SolidStart `useSession`, `Fe26.2*` prefix), NOT the API key. Dump it from browser DevTools → Application → Cookies → opencode.ai (`auth=...`). Save as `Cookie: oc_locale=ja; auth=...`.

2. **Verify cookie works**: `GET https://opencode.ai/auth/status` with the cookie returns `{"account":{...},"current":"acc_..."}` (200 = valid).

3. **Find the workspace ID** — call the workspaces RPC (no args). Must POST to `/_server` with headers:
   ```
   POST https://opencode.ai/_server
   X-Server-Id: def39973159c7f0483d8793a822b8dbb10d067e12c65455fcb4608459ba0234f
   X-Server-Instance: server-fn:1
   Content-Type: application/json
   Cookie: <auth cookie>
   Body: {"t":{"t":9,"i":0,"l":0,"a":[],"o":0},"f":31,"m":[]}
   ```
   Response is a seroval stream: `;0x...;$R=>$R[0]=[$R[1]={id:"wrk_..."}]`. Extract the workspace id.

4. **Discover RPC hashes** from the client JS bundles. The `_server` route ids are SHA-256 hashes wired via `createServerReference("hash")` in the built chunks at `https://opencode.ai/_build/assets/*.js`. Known useful hashes (may rotate with deploys):
   - `getWorkspaces` = `def39973159c7f0483d8793a822b8dbb10d067e12c65455fcb4608459ba0234f`
   - `getUsageInfo` (usage.list, per-request page) = `bfd684bfc2e4eed05cd0b518f5e4eafd3f3376e3938abb9e536e7c03df831e5c` (workspace home preview) — args `[workspaceID, page]`, 50/page
   - `getCosts` (daily per-model costs) = `15702f3a12ff8bff357f8c2aa154a17e65b746d5f6b96adc9002c86ee0c15205` — args `[workspaceID, year, month, tzOffset]`
   - `queryBillingInfo` (balance/sub/lite) — find hash in common chunk
   To rediscover: `curl -s <chunk-url> | grep -o 'createServerReference("hex64")'` and match against source at `github.com/anomalyco/opencode` (`packages/console/app/src/routes/...`).

5. **Serialize args with seroval 1.3.2** (critical!). The deployed console uses `seroval@1.3.2` format, NOT 1.6. The body is `{"t": <array-node>, "f": 31, "m": []}` where a plain array of args serializes as:
   ```json
   {"t":{"t":9,"i":0,"l":2,"a":[{"t":1,"s":"wrk_..."},{"t":0,"s":0}],"o":0},"f":31,"m":[]}
   ```
   - string → `{"t":1,"s":"..."}`
   - number → `{"t":0,"s":N}`
   - array → `{"t":9,"i":0,"l":len,"a":[...],"o":0}`
   With seroval@1.6.2 the `l` field is absent and `f:127` — the server rejects/misdecodes it. Generate bodies with `bun -e 'import {toJSON} from "seroval"; console.log(JSON.stringify(await toJSON(args)))'` from a dir with `seroval@1.3.2` installed.

6. **Parse the response stream**: response starts `;0xNNNN;` then `((self.$R=...)["server-fn:1"]=[],($R=>$R[0]=[...])(...))`. Records appear as `$R[N]={id:"usg_...",...,timeCreated:$R[M]=new Date("2026-08-22T..."),...}`. Resolve `$R[M]` date references, then split records on `},$R[N]={` boundaries.

7. **Interpret cost units**: `UsageTable.cost` and `getCosts.totalCost` are **micro-cents**; USD = value / 1e8. `plan:"lite"` = Go subscription usage; `null` = free/other.

## Verification
- `/auth/status` returns 200 with your account → cookie valid.
- A `getWorkspaces` call returns at least one `wrk_*` id (RPC plumbing works).
- `getCosts` for a month returns rows where `sum(totalCost)/1e8` matches the console's displayed monthly usage.
- Cross-check `getUsageInfo` page 0 raw count equals 50 (or fewer on last page).

## Pitfalls
- **Cloudflare bot block**: without a browser User-Agent you get HTTP 403 `error code: 1010`. Always send a full `User-Agent`.
- **API key does NOT work here**: the `opencode-go`/`opencode` API keys authenticate `/zen/go/v1/usage` (percentages only) and `/zen/v1/models`, but NOT `/_server`. `_server` needs the `auth` session cookie.
- **Wrong seroval version silently breaks args**: with seroval 1.6.2 format, args decode as `undefined` → functions like `getCosts` throw `RangeError: Invalid time value` and `getUsageInfo` returns "actor of type account is not associated with a workspace". Use 1.3.2 format.
- **Empty-args calls still work with 1.6.2 format** (e.g. `getWorkspaces` with `{"t":{"t":9,"i":0,"a":[],"o":0},"f":127}`) — this can mislead debugging.
- Workspace-scoped RPCs (`getUsageInfo`, `getCosts`, `queryBillingInfo`) need the workspace to be associated with the account; a brand-new "Default" workspace may fail with "actor of type account".
- The home page SSR HTML (`/workspace/<id>`) embeds the first 50 usage records as `$R[n]` — a quick lossless check without pagination.
- Handled `_server` responses come back as HTTP 200 even for errors — inspect the `$R[0]=Object.assign(new Error(...))` payload, not just the status code.
- Never write the session cookie into the workspace repo; keep it in `/tmp` and delete after use.
