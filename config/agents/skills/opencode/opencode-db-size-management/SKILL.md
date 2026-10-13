---
name: opencode-db-size-management
description: Use when opencode's database grows unexpectedly large, or when a single session dominates storage. Trigger keywords: opencode db size, event.data large, session storage, db VACUUM, opencode.db 5GB, セッション削除しても容量が減らない, event table, message.updated.1, message.removed.1, aggregate_id, 子セッション parent_id.
---

## event.data は会話内容の約 40 倍に膨らむ

opencode は **イベント溯源**で動作する。`event.data` に
`message.updated.1` として**メッセージと全 part を丸ごと**保存する。

更新が起きるたびに保存されるので、**同じ内容が N 回分記録される。**

実測（2026-10-05、procon プロジェクト）

| セッション | メッセージ | msg+part | event.data | 乗数 | 1 イベント平均 |
|---|---|---|---|---|---|
| 長い実装セッション | 5,348 | 44 MB | **1,775 MB** | 40.3x | 83 KB |
| 短命的セッション | 78 | 372 KB | 2.10 MB | 5.6x | 4.4 KB |
| レビューセッション | 3,113 | 31.8 MB | 52.4 MB | 1.6x | 2.9 KB |

**乗数はセッションの種類で大きく変わる。** 実装・調査で大きなツール出力を
繰り返すセッションは 1 イベント 83 KB、最大 21 MB に達することがある。

## 容量を測る

```bash
# DB 全体
du -sh ~/.local/share/opencode/opencode.db

# セッション別（.Bytesort で大きい順に）
opencode db "
SELECT aggregate_id, COUNT(*) AS n, SUM(LENGTH(data))/1024/1024 AS mb
FROM event GROUP BY aggregate_id ORDER BY mb DESC LIMIT 20"

# 内訳
opencode db "
SELECT type, COUNT(*) AS n, SUM(LENGTH(data))/1024/1024 AS mb
FROM event WHERE aggregate_id='<sessionID>' GROUP BY type ORDER BY mb DESC"

# 会話内容の実体（event ではなく message + part）
opencode db "
SELECT
  (SELECT COUNT(*) FROM message WHERE session_id='<s>'),
  (SELECT SUM(LENGTH(data))/1024/1024 FROM message WHERE session_id='<s>'),
  (SELECT SUM(LENGTH(data))/1024/1024 FROM part   WHERE session_id='<s>')"
```

## 検証：テーブル

| 表 | 名前 | 型 |
|---|---|---|
| `session` | id, parent_id, directory, title, time_created, time_updated | |
| `message` | id, session_id, data | |
| `part` | id, message_id, session_id, data | |
| `event` | id, aggregate_id, seq, type, data | `aggregate_id` = session id |

**子セッションは `session.parent_id` で辿る**（再帰 CTE で）。
サブエージェント（`task` tool）や orchestration の参加者も子になる。

```sql
WITH RECURSIVE tree(id, title, parent_id, depth) AS (
    SELECT id, title, parent_id, 0 FROM session WHERE id='<root>'
    UNION ALL
    SELECT s.id, s.title, s.parent_id, t.depth+1
    FROM session s JOIN tree t ON s.parent_id = t.id
)
SELECT id, depth, title FROM tree ORDER BY depth, id;
```

## 削除しても容量は減らない

`opencode session delete` でレコードを消しても**ファイル容量は減らない**。
SQLite の空き空間が残るため。

```bash
# opencode を全部停止してから実行する（実行中は安全でない）
opencode db "VACUUM;"
```

## 落とし穴

- **`VACUUM` は opencode 実行中はしない。** DB を排他ロックしている。
  全セッションを閉じてから実行する。
- **ファイルサイズを OS キャッシュで測ると過小評価する。**
  `du -sh` を使う。
- **アーカイブしたセッションの `event.data` は復元できない。**
  `opencode export` は**最終状態**（message + part）しか取り出さない。
  そのためアーカイブ済みセッションの event 容量は**推定しかできない**。
  上の乗数（1.6x〜5.6x を内容規模ごとに当てて）で概算する。
- **1 セッションが DB の 6 割を占めることがある。**
  上の例では 1,775 MB / 2,866 MB = 62%。
  だから「消すセッションを選ぶ」前にセッション別容量を測る。
- **`opencode db "PRAGMA ..."` は 1 ステートメントだけ実行する。**
  `page_count` / `freelist_count` / `page_size` を分けて 3 回実行する。
- **引き継ぎ時の申告メッセージ数と実際の DB 件数がずれることがある。**
  2026-10-06 の procon では申告 5,348 に対し DB は 5,375 だった。
  必ず削除直前に `SELECT COUNT(*) FROM message` で数え直す。

## 事前対策

大きなツール出力を繰り返すセッションでは、`event.data` が急増する。
対策は次の通り。

- 大きな出力はファイルに書き、`head` / `grep` で必要な部分だけ読む
- `opencode export` のような大量出力を、そのままツール結果に返さない
- セッションが特定の作業（大きなデータ移行、多量の調査）を越えたら
  新しいセッションに分けて引き継ぐ

セッションを引き継ぐ場合も、引き継ぐ前に知識を memory と skill に書く。
セッション自体は廃棄できる。

## 実績（2026-10-06 procon）

`ses_<redacted>` を退避・削除した。
event.data 1,775 MB / 76,421 イベントが 0 件になり、freelist は 879,310 ページ（3.4 GB）に増えた。
DB ファイルは 5.1 GB のまま。
退避したセッションの export は 61.8 MB（生）から 19.1 MB（gzip）に縮む。
手順は `opencode/session-archive-workflow` を参照。

