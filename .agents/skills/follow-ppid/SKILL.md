---
name: follow-ppid
description: Use when tracing a process's parent chain: walk up /proc/<pid>/stat field 4 (ppid) and print each ancestor with comm name. Trigger keywords: follow ppid, parent process chain, process ancestry, /proc stat.
args: <pid>
---

# follow-ppid

## いつ使うか

プロセスの親 PID チェーンを `/proc/<pid>/stat` 第4フィールド（ppid）から逆上って、各プロセス名（comm）とともに表示する。

## 手順

1. `scripts/follow-ppid <pid>` を実行する（PATH が通っていれば `follow-ppid <pid>` のみ）。
2. 引数は起点プロセスの PID。

## 検証方法

- `* <pid>` → `|-> <ppid>  <comm>` の形で親チェーンが表示され、ppid が 0 で停止することを確認する。

## 落とし穴

- 引数が未指定の場合は Usage を表示して終了する。PID が存在しない場合は読み取りに失敗し得る。スクリプト本体は `scripts/` を参照し、カタログは説明書きを担う。