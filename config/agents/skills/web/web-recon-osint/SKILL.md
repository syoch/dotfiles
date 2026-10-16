---
name: web-recon-osint
description: Use when performing web penetration-testing reconnaissance / OSINT enumeration against a target domain: subdomain enumeration, certificate transparency (crt.sh/certspotter), DNS records, TCP port scanning, HTTP fingerprinting, Cloudflare Access detection, WHOIS, and mining public GitHub infra repos (dotfiles/infrastructure) for service configs. Trigger keywords: web recon, OSINT, subdomain enumeration, CT logs, crt.sh, certspotter, port scan, Cloudflare Access bypass, CDN origin discovery, WHOIS, DNS enumeration, HTTP fingerprinting, GitHub infra repo mining.
---

# Web Recon / OSINT Enumeration

## When to use
Use for the passive/active reconnaissance phase of any web penetration test or target analysis. Applies to any domain, not just Cloudflare/NixOS targets. Do NOT use for trivial single-lookups (one whois or one curl); use it when you need a full host inventory and service mapping.

## Procedure

1. **DNS baseline** (`host`/`dig`): A/AAAA/MX/NS/TXT/CNAME/SOA at apex. Note registrar (IANA ID), DNSSEC status, SPF/DMARC/CAA, and attempt a zone transfer (`dig AXFR`) once (usually refused).
2. **WHOIS**: `whois <domain>` (wrap in `nix-shell -p whois` if the binary is missing). Record dates and privacy status.
3. **Subdomain discovery via THREE channels** (cross-check, each finds what others miss):
   - CT logs: query crt.sh and certspotter (wildcard certs often mask hostnames — note them).
   - Brute force: `for s in <wordlist>; do host -t A $s.$domain | grep -q 'has address' && echo FOUND; done`.
   - Public infra repos: list target's GitHub repos; grep raw `dotfiles`/`infrastructure`/cloudflared/TLS configs for `*.domain` strings; walk **commit history** (`/commits?path=`) — removed/decommissioned services (old vhosts, DDNS hostnames) survive in history.
4. **Port scan**: TCP connect probe `timeout 2 bash -c "echo > /dev/tcp/IP/PORT"` across a curated port list (22,53,80,443,445,3306,5432,3000,8000,8080,8443,...).
5. **HTTP probing**: `curl -k --max-time 12 -A 'Mozilla/5.0' -o /dev/null -w '%{http_code} %{redirect_url}'` per host + path. Grab `<title>`. Probe service-identifying paths (`/api/v1/version`, `/user/login`, `/status.php`, `/healthz`).
6. **Cloudflare Access detection**: probe `https://<cfaccount>.cloudflareaccess.com/cdn-cgi/access/login/<host>`; 302 → login page means Access-protected, `.well-known/cloudflare-access-protected-resource` confirms it.
7. **Origin discovery**: reverse DNS of every IP; test legacy/DDNS hostnames with `-H "Host: ..."` against raw IPs; TLS SNI probe with `openssl s_client -servername`.
8. **GitHub OSINT**: `api.github.com/users/<u>/repos`, gists, orgs, homepage URLs, search-code for the domain.

## Verification
- Every subdomain must be re-confirmed by HTTP probe (status + redirect target) before logging it.
- Map port → service name using probe responses, not just open/closed.
- Cross-source a finding (CT + brute force + repo) before reporting as fact.

## Pitfalls
- CDN (Cloudflare/Fastly) IPs only expose standard edge ports (80,443,8443,...); origin ports need legacy records or repo mining.
- CF Access: 302→login = protected; **530 = origin down but NOT protected** (info leak).
- Host-header probing against an IP can reveal hidden vhosts only if the tunnel/CNAME still points there.
- Brute-force wordlists miss non-intuitive hostnames; always mine public configs.
- Some probes are ad hoc one-offs — batch them in `for` loops with `-o /dev/null` to stay fast and low-noise.
- Check commit history even when the file no longer exists at HEAD; removed configs reveal old IPs/domains.
