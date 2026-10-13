---

## NextCloud Office の豆腐は「サーバーのフォント不足」（2026-10-07 実測・修正済み）

- NextCloud の pptx/docx/xlsx は **Collabora Online（`coolwsd` / `services.collabora-online`）がサーバー側でレンダリング**してブラウザへストリームする。**クライアント側のフォントは無関係**なので、Firefox と Edge で同じ豆腐になる。
- 豆腐の原因は **サーバーホストに CJK フォントが無いこと**。sv01 は標準で**フォント 1 個・日本語対応 0**だったため、`Noto Sans CJK JP` を 1025 箇所で要求する pptx がすべて □ になっていた。
- 対処: `fonts.packages = [ pkgs.noto-fonts-cjk-sans ];`（`components/host/sv01/default.nix`）→ 再ビルド → **`coolwsd` を再起動**。起動時にフォントをキャッシュするので、再起動しないと反映されない。

### 判別の手順（次に同じ症状が出たら）
1. `fc-list :lang=ja | wc -l` が 0 ならフォント不足が確定。`fc-match "Noto Sans CJK JP"` で実際に解決するか確認。
2. NextCloud のプレビューキャッシュ（`<datadir>/appdata_*/preview/...`）を削除しても直らない場合、描画は Collabora 側。为核心的。
3. ファイル自体が壊れていると疑う前に PPTX を検証する: `zipfile.testzip()`（CRC）, 全パートの XML パース, `<a:t>` の抽出。**今回は 66 パート全部クリーンで、テキスト側の混入はゼロ**だった（`cp932`/`latin-1` での再デコード反而壊れる = 元のテキストが正しい証拠）。

### 教訓
- 「文字化け」と言われても**先に"Who が描いているか"を確定**する。NextCloud のプレビューと Collabora の Office 編集は別系統で、フォント前者では画出サーバー・後者もサーバーだが経路とキャッシュが違う。
- フォントが 1 個しかないホストはenvironment として壊れているので、豆腐以外の症状（PDF プレビュー、Excalidraw のフォント等）も疑う。
