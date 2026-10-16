---
name: follow-link
description: Use when tracing a symbolic link chain: follow a symlink's target recursively and print each hop. Trigger keywords: follow symlink, readlink chain, symlink trace, link resolution.
---

# follow-link

## いつ使うか

シンボリックリンクのチェーンを `readlink` で辿り、各段階を表示する。

## 手順

1. `scripts/follow-link <link>` を実行する（PATH が通っていれば `follow-link <link>` のみ）。
2. 引数は辿りたいリンクのパス。

## 検証方法

- リンクが複数段に連なる場合、`* <link>` → `--> <target>` の形で全チェーンが表示されることを確認する。

## 落とし穴

- 引数が未指定の場合は Usage を表示して終了する。実在しないファイルは File not found を出す。スクリプト本体は `scripts/` を参照し、カタログは説明書きを担う。