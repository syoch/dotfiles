# グローバル長期記憶 (Global Long-term Memory)

本ディレクトリは `~/.config/opencode/memory/`（opencode のグローバル長期記憶）の管理元。
Home Manager activation (`opencodeMemoryLink`) により `~/dotfiles/config/memory` → `~/.config/opencode/memory` へ symlink され、編集が即反映される。

## 使い方

`memory_*` ツール（`memory_save` / `memory_get` / `memory_list` / `memory_remove`）が保存・参照する。
- `memory_save(scope="global", topic="<トピック>", mode="save|overwrite|append")`
- トピックは `/` で名前空間化可（例: `decision/2026-08`）。ファイルは `<トピック>.md` として配置される。

## 役割分担

- `config/memory/`（本ディレクトリ・グローバルスコープ）: マシン横断の汎用文脈（ユーザー設定・運用方針等）
- `<プロジェクト>/.agents/memory/`（プロジェクトスコープ）: プロジェクト固有の文脈・設計記録（`design/<課題名>` 等）
- `config/agents/`（`.agents` カタログ）: 再利用可能な**手順・スキル**（参照資産）。メモリ（文脈）とは別物
