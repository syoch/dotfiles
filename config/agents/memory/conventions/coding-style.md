# コーディングスタイル規則（ユーザーのスタイルをルールとして適用・随時更新）

※ 本メモリはユーザーの一般的なコーディングスタイルをルール化したもの。cworks 固有の詳細はプロジェクトスコープを参照すること。

## Rust
- **コメントは最小限**。意味の区切りに必要な一行のみ。実行時トレースは log マクロ（trace/warn）で代用し、コメントで説明しない
- **エラー処理**: `map_or_else(Err側, Ok側)` の関数合成を好む。早期リターンは `?` または `let ... else`
- **match は大きな一塊で列挙**。各 arm は短く保ち、arm 間のコード重複は許容（抽象化より明示を優先）
- **enum**: `#[derive(Clone, Debug, Serialize, Deserialize, Default)]` + `#[default]` 明示。tuple variant と struct variant を目的で使い分け
- **Debug/Display は手書き**: derive でなく enum 全体を match する手書き実装。variant 追加時は全 arm を更新
- **メソッド粒度**: 小さめ。thin ラッパ + 内部ヘルパは末尾アンダースコア（`resolve_`）
- **可視性**: 構造体フィールドは `pub` を多めに。内部ヘルパのみ非 pub
- **命名**: snake_case。分野プレフィクス（`fs_` 等）
- **属性**: `#[must_use]` `#[unsafe(no_mangle)]` 等を積極使用
- **serde**: 内部参照フィールドは `#[serde(skip_serializing)]`

## Lua
- API はテーブルに 1 行関数で列挙。応答アンラップは統一ヘルパ関数に集約
- snake_case

## 設計ドキュメント/計画
- フェーズ + Gate 検証スタイル。挙動維持を最優先に明記
