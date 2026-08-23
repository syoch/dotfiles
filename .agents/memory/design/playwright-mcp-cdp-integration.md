# Playwright MCP + CDP 統合 (実装済み・検証済み 2026-08-23)

## 最終アーキテクチャ (modules-hm/apps/opencode.nix)

```
systemd user services:
  chromium-cdp.service   pkgs.chromium --headless --remote-debugging-port=9222
                         --user-data-dir=~/.cache/chromium-cdp, Restart=on-failure
  playwright-mcp.service node <store> ~/.local/share/opencode-mcp/node_modules/@playwright/mcp/cli.js
                         --port 8931 --cdp-endpoint http://localhost:9222
                         (Requires+After chromium-cdp)
  opencode.service       (Requires+After playwright-mcp + chromium-cdp)

opencode: mcp.playwright = { type="remote"; url="http://localhost:8931/mcp"; enabled=true; }
Python:   p.chromium.connect_over_cdp("http://localhost:9222") — context/page のみ close
```

- headless↔headed: `systemctl --user set-environment CHROMIUM_HEADED=1 && systemctl --user restart chromium-cdp`
- MCP サーバーは HTTP transport 常駐 → opencode セッションは即時アタッチ
- Python 側は CDP 直結 (venv: /tmp/opencode/pw-venv, playwright 済)

## 採用判定 (ユーザー確定 2026-08-23)

レイテンシは概ね同等 (launch 中央値 2.22s vs cdp 2.40s、ブラウザ取得 0.19s vs 0.32s)。
**採用の優位性は「デスクトップが一瞬カクつかないこと」= Chromium spawn によるリソーススパイクの排除**として確定。
補足: launch の速さは常駐 chromium-cdp によるページキャッシュ温暖化の恩恵 (majfft 実測: 初回104→2回目以降0)。

## 決定的な落とし穴 (再発防止)

1. **opencode は ~/.config/opencode/package.json を起動時に自己書き換し、未知の依存を削除する**
   → @playwright/mcp は独立プレフィックス ~/.local/share/opencode-mcp に置く (opencodeMcp activation)
2. **Nix 文字列内ヒアドク禁止**: インデントされた `EOF` はターミネータにならず、以降のスクリプト全体がファイル内容に吸われる。package.json 生成は `node -e 'writeFileSync(...)'` を使う (opencodePlugins/opencodeMcp 両方で修正済み)
3. **systemd user service の PATH に node/npx が無い**: MCP コマンドは store node の絶対パスで cli.js を直接起動
4. **cworks Vite dev server**: `server.fs.allow` 外 (`wasm/`) への import は 403→500。アプリ側 WIP 由来の問題は dotfiles 側と切り分けること

## 関連スキル (CDP 接続に更新済み)

- nix/nix-playwright-e2e-setup, python/nginx-mock-ab-diff, python/playwright-ab-dom-equality
