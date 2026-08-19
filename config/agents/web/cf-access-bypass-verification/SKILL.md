---
name: cf-access-bypass-verification
description: Use when verifying Cloudflare Access (CF Access) protection coverage during web penetration testing: detect bypassed /api/* or service paths via HTTP status differential (302=protected login vs 530=origin-direct bypass), probe path traversal / sensitive file exposure, check GitHub public-repo leaks, and verify DNS/cert hardening. Trigger keywords: cloudflare access bypass, CF Access, 530, 302 login redirect, protection coverage, status code differential, origin-direct, api/control unprotected, sensitive file exposure, .git .env probe, github repo leak, DNSSEC CAA wildcard cert.
---

# Cloudflare Access Protection Verification

## When to use
During web pentesting against a site fronted by Cloudflare Access (or another reverse-proxy auth layer), to confirm which paths are actually protected and which leak straight to the origin. Use after subdomain enumeration / OSINT when you have candidate findings to verify and a report to write up.

## Key concept: HTTP status differential
CF Access intercepts requests to protected paths with **302 to the login page** (`/cdn-cgi/access/`). Paths NOT covered by an Access application pass straight through to the origin.

When the origin is DOWN (tunnel stopped), a bypassed path returns **530** (Cloudflare's origin-connection-error page) while protected paths still return 302. So 530 is a reliable marker of an Access bypass **even when the origin is offline**.

Mapping:
- `302` → CF Access protected (behind login)
- `530` → Access NOT protecting this path (origin-direct / bypassed)
- `200/401/403/404` → origin up; check app-level auth separately

## Procedure
1. Enumerate candidate endpoints (report, source code, robots.txt, subdomain list). Probe each with:
   `curl -s -k -A "Mozilla/5.0" -o /dev/null -w "%{http_code}" https://TARGET/<path>`
   Compare 302 vs 530 across `/api/*`, per-service subdomains, and root paths.
2. Locate the Access bypass boundary. The classic finding is a misconfigured path prefix: e.g. `/api/control/*` returns 530 while `/api/backup`, `/api/apps` return 302 — one prefix left out of the Access app. Probe variants too (`ws`, `download`, `status.php`, `sign_up`).
3. Sensitive-file exposure: probe `.git/HEAD`, `.env`, `config.json`, `backup.tar.gz`, `server-status`, `_app/immutable`, `.well-known`, `favicon.ico` on every host; record sizes via `-w "%{http_code} %{size_download}"`.
4. If app source is public (GitHub), pull the FastAPI/Nginx code and grep for route registrations (`Depends(get_db)`, `@router`, `def setup_*_routes`) and any bearer/admin dependency to confirm which routes lack auth.
5. GitHub leak check: walk repo trees via `GET /repos/{owner}/{repo}/git/trees/main?recursive=1`, list filenames matching `secret|key|password|token|cred|env|.pem|id_rsa|.age|.asc`, and grep configs for internal IPs (10.x, 192.168.x, 100.64-127 CGNAT), internal hostnames, VPN ranges (tailscale/netbird), service ports.
6. DNS checks: `dig +dnssec`, `dig +short CAA`, `dig +short TXT`, wildcard-cert impact via `openssl s_client -connect <ip>:443 -servername random-<x>.domain` and `openssl x509 -noout -subject -issuer -dates`.
7. Re-confirm the top findings once more right before writing the report.

## Verification
- Re-run the differential on key paths immediately before reporting (origin/tunnel state changes over time).
- Cross-check every 530 finding against source: does the app itself require a Bearer/admin token? If yes, record it as a mitigation factor (defense-in-depth loss, not anonymous RCE).

## Pitfalls
- 530 requires the origin to be unreachable; if the origin comes up you will see the app's real status code instead — interpret per-run.
- Always use `-k` and a browser UA; CF 403s empty UAs.
- Distinguish 'bypassed but app-level auth enforced' (lower severity) from 'completely unauthenticated backup/restore' (high).
- On other proxies (nginx/another WAF) the marker code differs; first establish the baseline on a known-protected path.
- nix-shell may be needed to get `dig`/`openssl` if not preinstalled.
