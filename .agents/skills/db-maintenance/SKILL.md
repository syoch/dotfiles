---
name: db-maintenance
description: Use when compacting/reclaiming disk from the opencode SQLite DB (opencode-stable.db). opencode's event table grows without bound and deleted rows are not returned to the filesystem until a VACUUM; /home may be nearly full so use VACUUM INTO on a filesystem with room. Trigger keywords: opencode db, opencode-stable.db, VACUUM, vacuum into, wal_checkpoint, db shrink, disk full, session delete reclaim.
args: なし
---

# db-maintenance (scripts/db-maintenance)

## いつ使うか

opencode の `~/.local/share/opencode/opencode-stable.db` が肥大（例: `event` テーブルが GB 級）し、ディスクが逼迫したとき。行削除だけではファイルサイズは戻らないため、VACUUM による圧縮が必要。`/home` がほぼ満杯の場合、インプレース VACUUM は空き不足で失敗するため `VACUUM INTO` を別 FS で行う。

## 手順

1. opencode を全て停止する（`systemctl --user stop opencode` + TUI を全て終了）。
2. リポジトリルートから実行: `bash scripts/db-maintenance`
3. スクリプトが `VACUUM INTO`（既定 `/var/tmp`、必要なら `STAGE=...` で上書き）でコンパクト化 → 行数照合 → 旧 DB を `.bak` に退避して入れ替え。
4. 完了後 `ls -lh ~/.local/share/opencode/opencode-stable.db` で縮小を確認し、opencode を再起動。

## 検証方法

- Before/After のサイズ表示と、`VACUUM INTO` 後の行数（session/event）が事前と一致することをスクリプトが自動照合する。
- 確認後、不要なら `.bak` を削除。

## 落とし穴

- **opencode 稼働中は実行不可**（スクリプトが実行時ガードで拒否）。WAL の別接続があると VACUUM が競合し得る。
- `VACUUM INTO` の書き込み先 FS に DB 相当の空きが必要（`/` 側を推奨）。
- バックアップは捨てず、動作確認後に手動削除する。