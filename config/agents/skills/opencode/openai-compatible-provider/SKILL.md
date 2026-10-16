---
name: openai-compatible-provider
description: Use when wiring a custom OpenAI-compatible endpoint (local router/proxy/mock) into opencode as a provider, when opencode silently returns nothing/"unauthorized", when reaching opencode.ai Console/Go inference endpoints, or when reasoning about how opencode treats free/stealth models. Covers the request contract (<baseURL>/chat/completions, no /v1 auto-add, no Authorization unless options.apiKey, x-opencode-client/x-opencode-session headers), correct base URLs (/inference/openai/v1, /inference/go/openai/v1), the client-side free-tier special-casing (apiKey sentinel "public", cost.input===0), and the unbypassable Zen free-tier 403 gate. Trigger keywords: opencode provider, @ai-sdk/openai-compatible, baseURL /v1, chat/completions 404, provider unauthorized, missing apiKey, x-opencode-client, x-opencode-session, FreeTierError, free_tier_limit, space-bunny-free, isFree cost.input, custom provider silent empty, OPENCODE_CONFIG.
---

# Add a custom OpenAI-compatible endpoint to opencode

## When to use
- Wiring a local router/proxy/mock (e.g. ocdesk) into opencode.
- opencode "works" but prints nothing, or errors `unauthorized` / parse errors.
- Calling opencode.ai Console/Go inference endpoints directly.
- Reasoning about opencode's free/stealth models.

## The contract (opencode 1.19.0, `@ai-sdk/openai-compatible`)
opencode sends `POST <baseURL>/chat/completions`. There is **no automatic `/v1`**.
The provider `baseURL` must include the version prefix exactly as the server mounts it:

| server serves | provider `options.baseURL` |
|---|---|
| `POST /v1/chat/completions` | `http://127.0.0.1:PORT/v1` |
| `POST /chat/completions` | `http://127.0.0.1:PORT` |

- **Auth**: with no `apiKey` (and no api-key env), opencode sends **no `Authorization`**.
  A server requiring a bearer token then returns 401. Set `options.apiKey`.
- Headers opencode adds to *every* provider request (`packages/core/src/session/model-request.ts`):
  `x-opencode-session-id`, `x-opencode-parent-session-id`, `x-session-affinity`,
  `X-Session-Id`, `x-parent-session-id`, `x-opencode-project`,
  `x-opencode-session` (= session affinity), `x-opencode-client` (= app name, `cli`),
  `User-Agent: App.useragent(app)`. Stateless calls add `x-opencode-session`
  (`packages/core/src/generate.ts`: "Gateways require session attribution even for a stateless call").

Minimal provider block:
```json
{ "provider": { "myrouter": {
  "npm": "@ai-sdk/openai-compatible",
  "name": "myrouter",
  "options": { "baseURL": "http://127.0.0.1:8787/v1", "apiKey": "LOCAL_TOKEN" },
  "models": { "any": { "name": "Any" } }
}}}
```
Run: `opencode run --model myrouter/any "hi"`.

## Capture what opencode actually sends
- **Custom provider**: point it at a local logger (logs `method/path/headers/body`
  to JSONL, replies with a minimal chat completion; SSE when `body.stream`).
  `$OPENCODE_CONFIG=/tmp/cfg.json opencode run --model logger/m "hi"`.
- **Built-in provider (opencode/opencode-go)**: override just the baseURL —
  `{ "provider": { "opencode": { "options": { "baseURL": "http://127.0.0.1:12999" } } } }` —
  then run `--model opencode/<id>`. Reveals the real auth + `x-opencode-*` headers.

## opencode.ai inference endpoints (Console / Go)
- Base URLs (`~/.cache/opencode/models.json`, keys `opencode` / `opencode-go`):
  - Console/Zen: `https://opencode.ai/inference/openai/v1`
  - Go: `https://opencode.ai/inference/go/openai/v1`
- Console service-account key `oc_sk_...` authenticates **paid** models.
- Free/stealth models (`*-free`) always `403 FreeTierError` for non-opencode clients,
  not bypassable by headers/keys — see below.

## How opencode treats free models (source, anomalyco/opencode dev)
- "Free" is **cost-based, no dedicated flag**:
  `packages/app/src/providers/models/unpaid.tsx` →
  `isFree = provider.id === "opencode" && (!cost || cost.input === 0)`.
  UI groups them under "Free models provided by OpenCode" + a `free` badge
  (i18n `dialog.model.unpaid.freeModels.title`, `model.tag.free`); display name strips "free".
- **No credentials ⇒ free tier via sentinel apiKey** (`plugin/provider/opencode.ts`):
  when there is no `OPENCODE_API_KEY` / Console connection / configured key, opencode
  sets `provider.settings.apiKey = "public"` and **disables every model with
  `cost.input > 0`**, leaving only the free ones enabled.
- Free-tier exhaustion has a dedicated upsell: `free_tier_limit` reason in
  `packages/app/src/session/usage-exceeded-dialogs.tsx`.
- Server-side (Console) enforcement: verified empirically that even with the exact
  `x-opencode-*` headers, UA, referer, and the opencode `sk-` account key, curl/bun
  still get `403 FreeTierError`, while opencode's own client passes (rate-limited).
  => gate is tied to the opencode client/account, **not** copyable by a proxy.
- **The official SDK does NOT bypass it** (tested `@opencode/sdk@2.0.30`, in-process
  host, npm): with `OPENCODE_API_KEY` set to the Console key, a *paid* model
  (`opencode/deepseek-v4.1-flash`) succeeded (`finish: stop`, text returned), but a
  *free* model (`opencode/space-bunny-free`) still failed with `403 FreeTierError`
  (`provider.auth`). So only the actual opencode app passes the free gate; SDK,
  raw HTTP, and proxies cannot. (SDK defaults to an in-memory DB; without
  `OPENCODE_API_KEY` the paid models are disabled and only free ones are enabled.)

## Pitfalls
- **Silent empty output** usually = wrong path returning HTML (SPA catch-all 200).
  Make the server return 404 JSON for unknown non-GET paths and accept both
  `/v1/chat/completions` and `/chat/completions`.
- A router/proxy **cannot** serve `*-free` opencode.ai models; route paid models.
- The opencode config may be a read-only Nix symlink; edit the source
  (home-manager module) and rebuild, or use `$OPENCODE_CONFIG` to test.
