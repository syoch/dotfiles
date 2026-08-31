# 制約: opencode plan mode のツール非対称

plan mode では edit ツールがブロックされ、write は新規ファイル作成のみ許可（既存ファイルの上書き編集不可、
`.opencode/plans/` 配下のみ例外）。plan 中に既存ドキュメントを修正したくなったら:
(a) 内容を応答に保持して build モード移行後に反映、(b) plans/ 配下に退避——のどちらか。
bash 経由の回避は規律違反なのでしない。

source: sessions-archive jIe11su9 msg#151
