---
name: agents-skillify-script
description: Use when adding a new shell script to the dotfiles repo or registering an existing script in the .agents catalog: wrap scripts/<name> into .agents/<name>/SKILL.md with frontmatter (name/description/args), the four body sections (いつ使うか/手順/検証方法/落とし穴), args convention (なし or <arg>), and chmod +x. Trigger keywords: agents catalog, SKILL.md wrapper, scripts directory, skillify script, .agents entry, agents_add, MANIFEST deprecated.
---

---
name: agents-skillify-script
description: Use when adding a new shell script to the dotfiles repo or registering an existing script in the .agents catalog: wrap scripts/<name> into .agents/<name>/SKILL.md with frontmatter (name/description/args), the four body sections (いつ使うか/手順/検証方法/落とし穴), args convention (なし or <arg>), and chmod +x. Trigger keywords: agents catalog, SKILL.md wrapper, scripts directory, skillify script, .agents entry, agents_add, MANIFEST deprecated.
---

# agents-skillify-script

## いつ使うか

dotfiles リポジトリの `scripts/` に新しいシェルスクリプトを追加したとき、または既存スクリプトを `.agents` カタログに登録するとき。カタログの唯一の基準はディレクトリ構造と SKILL.md frontmatter（MANIFEST.md は廃止済み）。

## 手順

1. スクリプト本体を `scripts/<name>` に配置し `chmod +x scripts/<name>` する。スクリプトは `set -e`（または `set -eu`）で失敗を検出する。
2. 保存先を決める: リポジトリ固有なら `./.agents/<name>/SKILL.md`（プロジェクトスコープ）、汎用・技術カテゴリなら `config/agents/<category>/<name>/SKILL.md`（ユーザースコープ）。
3. frontmatter を作成する:
   - `name`（ディレクトリ名と一致させる）
   - `description`（`Use when` で開始、トリガーキーワードを先頭に、1-2文）
   - `args`（引数不要なら `なし`、あるなら `<arg>` の形式）
4. 本文は「いつ使うか」「手順（コマンド・ステップ）」「検証方法」「落とし穴」の4節で書く。手順には `scripts/<name>`（PATH が通っていれば `<name>` のみ）の実行方法と引数の渡し方を明記する。
5. 落とし穴には「実行には実行権限が必要（`chmod +x scripts/<name>`）。スクリプト本体は `scripts/` を参照し、カタログは説明書きを担う。」を必ず含める。
6. `agents_show` または Read で内容を確認し、手順が再実行可能であることを検証する。

## 検証方法

- `scripts/<name>` を単体実行して期待出力が得られること（引数省略時は Usage 表示、存在しない対象はエラー出力）。
- 新規エントリが `agents_list` に現れ、agents-bridge のシステムプロンプト注入ブロックに `category/name (args): desc` 形式で含まれること。

## 落とし穴

- 直接 Write/Shell で編集する前に `agents_add` / `agents_update` の利用を検討する（frontmatter の name とディレクトリ名の一致を強制、未知カテゴリは拒否）。
- MANIFEST.md はメンテしない（廃止済み）。
- 単純すぎる指示（1コマンドや自明な操作）はスキルにせず、カタログ1行に留める。
