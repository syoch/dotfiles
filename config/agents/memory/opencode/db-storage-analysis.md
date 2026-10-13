opencode DB (`~/.local/share/opencode/opencode.db`) の容量解析で判明した事実（2026-10 時点、5GiB）。

- セッション系テーブルは 4 つ: `session`, `event`(aggregate_id=session id), `part`, `message`。event と part は**同じ内容を二重保持** (event 1.4GiB / part 470MiB)。session 削除で両方消えるので、event だけで容量推定すると低く出る。
- `session.parent_id` は Task/subagent が作る小セッションの親。126 session = 79 root + 47 child、深さ最大 1。
- `session.time_created` / `time_updated` は**ミリ秒** epoch。
- `session` 行が無い event aggregate (orphan) が 1 件。`opencode session delete` では回収されない。
- event の type は上位3つで 99%: `message.updated.1`, `message.part.updated.1`, `session.updated.1`。
- 全走査 `SUM(LENGTH(data)) GROUP BY aggregate_id` は 5GiB でも約 11 秒。dbstat 集計も同じオーダー。
- 論理バイト→ディスク実バイト比は dbstat から算出でき実測 ~1.17。
- 子孫集約は再帰 CTE。`HAVING SUM(is_root)=1` でルートだけ残す + `WHERE d.depth < N` ガード（循環 parent_id で無限ループ）。

実装: ~/work/opencode-inspector (opencode_inspector.py + subtree-sizes.sql)
