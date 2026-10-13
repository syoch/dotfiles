---
name: session-archive-workflow
description: Use when exporting/archiving opencode sessions to a project archive directory and deleting them via opencode CLI. Trigger keywords: opencode session delete, opencode export, session archive, 会話記録 エクスポート, セッション削除, sessions-archive.
---

# opencode セッションのアーカイブ＆削除

opencode の過去セッションをエクスポートしてから CLI で削除する手順。トリガー例: 「不要な session を削除」「セッションを export しておいて」。

## 手順

1. **対象セッションの把握**:
   ```bash
   opencode db "SELECT id, title, datetime(time_created/1000,'unixepoch','localtime') FROM session WHERE directory='<cwd>'"
   opencode db "SELECT session_id, COUNT(*) FROM message WHERE session_id IN (...) GROUP BY session_id"
   ```
2. **現行セッションを特定して除外**（time_updated が「今」のもの。削除しない）。
   判定はスクリプト内で `KEEP_IDS` として ID を列挙すると確実（タイトル文字列マッチは衝突する）。
   親を delete すると子が連鎖削除されるので、削除前に子の有無を DB で確認する。
3. **エクスポート（必ずファイルリダイレクト）**:
   ```bash
   opencode export --pure <sessionID> > out.json
   gzip -9 -f out.json && gzip -t out.json.gz
   ```
4. **検証**: `python3 -c "import json,gzip; d=json.load(gzip.open('out.json.gz')); print(len(d['messages']))"` が DB のメッセージ数と一致すること。
   `gzip -t` は gzip ストリームの整合性しか見ないので、**JSON の構造が壊れていても通る**。
   必ず `json.load` でパースし直すこと。
5. **命名規約**（既存アーカイブに合わせる）: `<YYYYMMDD-HHMM>_<セッションID末尾8文字>_<タイトルスラッグ>.json.gz`
6. **index 更新**: アーカイブ dir の `index.md`（一覧表）と `index.json`（`{file,id,parent,title,created,messages,bytes_gz,bytes_raw}` の配列）に追記。
7. **削除**:
   ```bash
   opencode session delete <sessionID>
   ```
8. **最終確認**: `opencode db "SELECT id FROM session WHERE directory='<cwd>'"` で残存を確認。
   削除した ID について `session` / `message` / `part` が 0 件になったことも確認する。
9. **アーカイブを git 管理外に**: `.git/info/exclude`（または `.gitignore`）に `.agents/sessions-archive/` を追記する。

## 落とし穴

- **`opencode export` は `--pure` 無しで `Session not found` になる。**（2026-10-05 実測。プラグインがセッション解決を妨げる）。`--pure` を付ける。
- **`subprocess.run(capture_output=True)` / パイプ経路は 64KB で出力が切り詰められる**（rc=0 で黙る）。必ず `stdout=open(file,'wb')` やシェルリダイレクトで受け、JSON パースで検証する。
- **`gzip -f` は `.gz` 付きファイル名に `.gz` を足す。** `gzip -f out.json.gz` は `out.json.gz.gz` を作り、直後の `gzip -t out.json.gz` は `No such file or directory` で失敗する。**拡張子なしの名前**に入れてから gzip する。
- **タイトルが日本語だけだと slug が空になる。** `[^0-9A-Za-z]` に置換した結果が空なら `untitled` のような既定値を入れる。
- **既に同名ファイルがあるときは上書きせず SKIP する。** 別セッションの archive と衝突しうる。
- **`opencode db "PRAGMA ..."` は 1 ステートメントだけ実行する。** `page_count` / `freelist_count` / `page_size` を分けて呼ぶ。
- **`time_created` は你以为より古いことがある。** 別ディレクトリで作成されたセッションがこのディレクトリへ移った場合、`time_created` は元の日時を指す。命名は `time_created` に素直に従う。
- stderr に進捗 `Exporting session: ...` が出る（正常）。
- 削除後も DB ファイル容量は減らない。opencode 停止中に `opencode db "VACUUM;"` を推奨。
- 大量処理は dry-run モードを持つスクリプトにしておくと、件数・ファイル名・重複を削除前に確認できる。

## 検証

- 全ファイルの `gzip -t` 成功＋メッセージ数が DB 集計と一致。
- 復元テスト（`zcat <file>.json.gz | python -c "import json,sys; print(len(json.load(sys.stdin)['messages']))"`）で同じ件数が取れる。
- 削除対象以外（現行セッション等）が DB に残っていること。セッション総数が想定どおり減っていること。
- index.json の `messages` 合計が DB 集計と一致すること。
- 削除した ID の `session` / `message` / `part` が 0 件であること。

## 実績

### 2026-10-05 procon

過年度発表の解析で作った一時セッション **118 件 / 4,120 メッセージ**を退避（13.0 MB）。
セッション総数 298 → 180。同期処理スクリプトは `/tmp/opencode/archive-sessions.sh`。

### 2026-10-06 esp32-wifi-oss

PHY ドライバ再実装の **5 セッション / 6,445 メッセージ**を `.agents/sessions-archive/` に退避
（9.4 MB gz / 展開 67 MB）。スクリプトは `/tmp/opencode/archive-esp32-sessions.sh`（dry-run / run）。
全件 `gzip -t` と復元テスト通過、削除 5 ID の `session`/`message`/`part` が 0 件であることを確認。
現行セッションは `KEEP_IDS` で除外した。

## 文脈の引き継ぎ

アーカイブは削除の手段であり、目的ではない。「アーカイブして文脈を引き継いで」の後半を
省略してはいけない。手順:

1. `memory_get` / `agents_show` でプロジェクトメモリとスキルを読み込む
2. **実際に測り直す**。引き継いだセッションの申告値をそのまま信じない:
   - ビルド系プロジェクトの例: override 関数数、map からのセクション数、IRAM 関数数
3. 引き継いだセッションの最終メッセージを読み、**未コミットの変更**が残っていないか確認する
4. 陳腐化した `docs/*HANDOFF*.md` を実測値で訂正する（古い誤診が数か月残ることがある）
5. 実機（シリアル）が繋がっていないなら、その旨を明示する

## 復元

```bash
zcat <file>.json.gz | opencode import -
```
