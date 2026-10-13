NextCloud Talk の venue で、bot の投稿は bot を起動しない（`No bots for bots`）。

**送り先は送信元で決める。**

- **human** からの turn → `talk-post_post`（会話に投稿される）
- **role**（leader 含む）からの turn → **`talk-delegate`**（投稿 + 先の role の session に配送）

`talk-post_post` で role に返すと Posted は成功しても相手には届かない。相手は DB (`GET /ctl/sessions`) を直接読むしかなく、催促される。

実測: 2026-10-07 に `procon-osm` が `procon-lead` へ調査結果を `talk-post_post` で送ったが、`procon-lead` のセッションには届かず DB から回収した。`procon-review` も同じ指摘を受けた。

人間にも可见にしたい場合は `talk-delegate` の後に `talk-post_post` で 1 行残す。

skill `global/talk-venue-briefing` に手順として入れた。

2026-10-07 人が指摘した運用ルール。

**各ロールは、結果を lead に返すときに `talk-post` を使ってはいけない。**
`talk-delegate` を使い、`role` に `procon-lead` を指定すること。

`talk-post` で投稿したメッセージは bot 間に配送されないので、lead に届かない。
人が「talk-delegate ツールで bot 間通信しないと結果を lead に送れません」と指摘した。

** обязанность（各ロールの返事の方針）**

- 人に直接届ける最終回答は `talk-post_post`
- 別のロールに作業を依頼する、または結果を返すのは `talk-delegate`
- 回答が要るのに何もしない、という tacit な「終わったら連絡)是 不可
- 作業が 끝나면 proactively `talk-delegate` で `procon-lead` に送る

関連: `knowledge/talk-bot-to-bot-delivery`（bot 間配送の仕組み）、global `knowledge/talk-bot-to-bot-delivery`

# 人向け投稿はロールからは見えない（2026-10-08）

**ロールエージェント（lead 含む）は、人向けの `talk-post_post` を読めない。** 自分が受け取った `talk-delegate` しか見えない。

**事故**: `procon-infra` が swapfile の計画を `talk-post_post` で出し、人がそれに反応していた。
lead はそれを見られず「計画が未着です」と誤判定して再送を依頼した。

**運用ルール**

- **人向け投稿の有無を、自分の視界で判断しない。** 「私からは見えない」を前提にする
- 依頼が来ていないように見えても、既に出ている可能性がある。**先方に「出しましたか」と一度聞く**のはよいが、「未着」と断定しない
- 逆に、ロール間の依頼は `talk-delegate` なので見える。**見えない＝人向け、見える＝ロール向け**

関連: `knowledge/talk-bot-to-bot-delivery`（bot 間配送の仕組み）
