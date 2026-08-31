# syoch.org スプリットホライズン DNS 設計（確定 2026-08-25）

## 目的

1 ホスト名（サービス名）を、接続形態に応じて異なる経路で解決する。
- インターネット: Cloudflare DNS → CF Tunnel → sv01（無駄な tunnel を LAN/VPN では回避）
- VPN/LAN: dnsmasq → CNAME → 実ホスト → 接続形態別 IP（LAN=10.42.x / Tailnet=100.96.x）

## 確定事項

### 名前解決全体像

```
[LAN クライアント] ──→ sv01 dnsmasq (LAN inst, 10.42.0.1:53)
[VPN クライアント] ──→ sv01 dnsmasq (tailnet inst, 100.96.100.1:53)  ※Tailscale Split DNS で委譲
                          ├─ syoch.org 内部名: cname= で実ホストへ
                          └─ default → blocky (127.0.0.1:54) → Cloudflare DoH

[インターネット] ──→ Cloudflare DNS（サービスエントリのみ・ホストエントリは置かない）
                    → CF Tunnel → sv01

[desktop syoch-nix] ──→ systemd-resolved（復活）
                          ├─ nnctrobo.internal → NetBird resolver（ネイティブ自動登録）
                          └─ default → sv01 dnsmasq (10.42.0.1)
```

### レコード設計

- **公開ゾーン (Cloudflare)**: サービスエントリのみ（`nextcloud.syoch.org` 等、既存通り CF Tunnel へ）。ホスト解決エントリは**置かない**
- **内部ゾーン (dnsmasq, 両インスタンス共通)**:
  - `cname=<service>.syoch.org,<host>.syoch.org`（標準ディレクティブ。例: `cname=nextcloud.syoch.org,sv01.syoch.org`）
  - ホストは `address=/<host>.syoch.org/<IP>` で接続形態別に定義
    - LAN inst: `address=/sv01.syoch.org/10.42.0.1` 等
    - tailnet inst: `address=/sv01.syoch.org/100.96.100.1` 等
- **dnsmasq は 2 インスタンス**（LAN bind + tailscale0 bind）で実装。cname/address はインスタンス共通部を include
- CNAME ループ防止: dnsmasq に定義済みの名前は内部解決、未定義の syoch.org サブドメインは上流（blocky）へフォールスルー

### blocky（sv01 一括）

- 単一インスタンス 127.0.0.1:54、upstream = Cloudflare DoH
- clientGroupsBlock は **source IP** ベース（default=ads、kids-ipad=ads+adult 等）
- **動的化は A+C**:
  - A: グループ構成は Nix で静的管理（デバイス追加 = 設定 1 行 + リロード）
  - C: blocky HTTP API（apiPort）で一時解除・ブラックリスト更新等の運用時動的操作

### NetBird（部活 VPN 専用・syoch-nix のみ）

- sv01 には **NetBird を導入しない**（部活ネットワークへのアクセスは現状どおり Tailnet 経由）
- syoch-nix: systemd-resolved を復活させ、NetBird が自ドメイン（nnctrobo.internal）を resolved に自動登録 → ローカル dnsmasq（127.0.0.50）とローカル blocky は廃止
- systemd-resolved 無効化の理由は「dnsmasq との競合防止」だったため、dnsmasq 廃止後は復活可能

### Tailscale / NetBird 併用

- Tailscale: 家庭 mesh（sv01 / syoch-nix / p30t 等）
- NetBird: 部活 VPN 専用（syoch-nix が参加）
- 併用は確定。Tailscale 側の `--accept-dns` はスプリットホライズン導入に伴い見直し（Split DNS 委譲を受けるため true 化の検討）

## 未決論点（実装時に必要）

1. syoch-nix / p30t の LAN IP・tailnet IP の一覧（address= に必要）
2. 内部公開サービス名の最終リスト（nextcloud / portal / collabora / wb-nextcloud 想定、他に NAS 等を加えるか）
3. blocky API のポート・認証（Tailnet 内のみで晒す等）
4. desktop の `networking.nameservers` を resolved 経由（127.0.0.53 か systemd-resolved 管理）に変更する詳細
5. Tailscale Split DNS の委譲範囲（`syoch.org` 全体 or サービス名のみ）
6. sv01 の dnsmasq 2 インスタンスの NixOS 実装（`services.dnsmasq` を 2 unit 化 or 2 ポート）

## 関連

- cloudflared は sv01 に既存（nextcloud/portal/collabora/wb-nextcloud の ingress 設定済み）
- 現状 syoch-nix: dnsmasq(127.0.0.50) が /nnctrobo.internal→NetBird、/syoch.internal→10.42.0.1、default→blocky をマージ（新設計で解消）
