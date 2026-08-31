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
3. **エクスポート（必ずファイルリダイレクト）**:
   ```bash
   opencode export <sessionID> > out.json
   gzip -f out.json && gzip -t out.json.gz
   ```
4. **検証**: `python3 -c "import json,gzip; d=json.load(gzip.open('out.json.gz')); print(len(d['messages']))"` が DB のメッセージ数と一致すること。
5. **命名規約**（既存アーカイブに合わせる）: `<YYYYMMDD-HHMM>_<セッションID末尾8文字>_<タイトルスラッグ>.json.gz`
6. **index 更新**: アーカイブ dir の `index.md`（一覧表）と `index.json`（`{file,id,parent,title,created,messages,bytes_gz,bytes_raw}` の配列）に追記。
7. **削除**:
   ```bash
   opencode session delete <sessionID>
   ```
8. **最終確認**: `opencode db "SELECT id FROM session WHERE directory='<cwd>'"` で残存を確認。

## 落とし穴

- **`subprocess.run(capture_output=True)` / パイプ経路は 64KB で出力が切り詰められる**（rc=0 で黙る）。必ず `stdout=open(file,'wb')` やシェルリダイレクトで受け、JSON パースで検証する。
- stderr に進捗 `Exporting session: ...` が出る（正常）。
- 削除後も DB ファイル容量は減らない。opencode 停止中に `opencode db "VACUUM;"` を推奨。

## 検証

- 全ファイルの `gzip -t` 成功＋メッセージ数が DB 集計と一致。
- 削除対象以外（現行セッション等）が DB に残っていること。

## 復元

```bash
zcat <file>.json.gz | opencode import -
```
