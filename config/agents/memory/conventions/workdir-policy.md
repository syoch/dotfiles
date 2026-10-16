# 作業場所の規律 (ユーザー指示 2026-08-21)

- ホームディレクトリ (~) を作業ディレクトリに使わない
- 一時作業は /tmp(/tmp/opencode)、継続的な成果物・検証はプロジェクトルートから派生したパス
  (例: /mnt/usbssd/<project>/Tools/... や <project>/build/)で行う

## /tmp/opencode 直下は使わない（2026-10-15 更新）
- `/tmp/opencode` 直下は全プロジェクト共有。一時作業は **プロジェクト別サブディレクトリ `/tmp/opencode/<project>/`**（例: `/tmp/opencode/iwara-rev/`）か、プロジェクト配下の適切な場所を使う。
- 長いコマンドを打つ際は必ず一時スクリプトを作成してから実行する（グローバル規範のインライン実行禁止と合わせて徹底）。

## /tmp/opencode は他エージェントと共有される（2026-10-01 確認）
- 同じ /tmp/opencode を別プロジェクトのエージェントが並行して使い、同時に整理（掃除）することがある。
  そのため mtime だけではファイルの由来を判定できない。削除時は次の手順で由来を確定する。

1. 削除候補を時刻範囲で絞り込み、ソートしたパスを作業窓の外（例: /tmp/<name>_deletelist.txt）に保存し、
   削除前に一覧を残す。
2. 各パスの中身を grep / head で確認し、自分自身のセッションの成果物だけを残す。
3. 削除はリストをそのまま渡して行う（rm -rf -- "$(cat list)"）。
4. 実行前後に du -sm を測り、解放量が削除対象の合計と一致するか検証する。
   一致しなければ、自分の操作以外（他エージェント）が同時に作用した証拠。
5. 他プロジェクトの資産が消失していた場合は、他エージェントの並行掃除と解釈してよい（2026-10-01 の運用実績）。

`conventions/workdir-policy.md` の /tmp/opencode 直下禁止: プロジェクト別サブディIR (`/tmp/opencode/<project>/`) を使う。長いコマンドは必ず一時スクリプト経由。
`conventions/readonly-mount-not-boundary.md`: `:ro` mount は secret/forbidden data を読ませないのに使えない。Read only shrinks writes, not reads. Mount only necessary paths.
