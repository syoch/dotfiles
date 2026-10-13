# opencode plugin の落とし穴（実測 2026-10-06）

## 1. plugin はファイル内の「全 export」を plugin 関数として呼ぶ

`~/.config/opencode/plugins/x.ts` は named export を全部 plugin として呼ぶ。
`export const FOO = "bar"` を 1 個混ぜると **ファイル全体がロード失敗**する。

```
export const TALK_POST_TOOL = "talk-post_post"   ← これで全体が死んだ（無言で）
export default TalkPost                          ← 正しい形
```

**判別方法**: `/config` には並んでいるように見えるだけなので信用できない。
判別は hook のログを 1 本出してから確かめること。

## 2. tool 名は `<file>_<export>`、ハイフンは保持

```
tools/talk-post.ts の export const post  →  モデルは talk-post_post と呼ぶ
tools/agents.ts    の export const list  →  agents_list
```

plugin の `tool: {}` マップは**モデルに見えない**（実測）。
briefing に書く名前も実際の名前と一致させること。
「turn が投稿したか」は `tool.execute.after` を見て判定する。

## 3. plugin はサーバー起動時にロードされる

ファイルを増やしても再起動なしでは反映されない。ただし `/event?directory=` は
ディレクトリ指定が必須（無いと heartbeat しか来ない）。

## 4. `/tmp` に置いた plugin はロードされない

import は realpath から解決されるので、`node_modules` が無いと失敗する。
実 plugin は repo 内に置き、`node_modules` を symlink する。
