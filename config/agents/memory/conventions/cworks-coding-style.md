# cworks プロジェクトの Rust/Lua コーディングスタイル（随時更新）

ユーザー (syoch) の cworks リポジトリにおけるコーディングスタイル。新規コードはこれに合わせる。

## Rust 全般
- **コメントは最小限**。自明でない箇所のみ英語で記載。実行時の挙動説明は `log::trace!` / `log::info!` で代用する（コメント代わり）
- **エラー/Option 処理**:
  - 関数合成: `res.map_or_else(SyscallData::Fail, SyscallData::FSGet)` 形式
  - `let ... else` で早期リターン＋ `continue`
  - `?` オペレータも使用
  - 配信系: `self.processes.get_mut(&pid).map(|p| ...).unwrap_or_else(|| log::warn!(...))` 形式
- **`.unwrap()` / `.expect("...")` は気軽に使う**（panic 許容スタイル）
- **enum**: `#[derive(Clone, Debug, Serialize, Deserialize, Default)]` + `#[default]` を明示
- **属性を積極使用**: `#[must_use]`, `#[unsafe(no_mangle)]`, `#[serde(skip_serializing)]`, `const fn new`
- **命名**: snake_case、内部ヘルパは末尾アンダースコア（`resolve_`）、`fs_` 等のプレフィクス
- **メソッドは薄く**、構造体フィールドは実用的な範囲で `pub`
- **依存は最小限**、ステートレス設計・mechanism/policy 分離を好む
- kernel ループは inline の `self.processes.get_mut(pid).unwrap()` チェーンを直接書く（ヘルパ抽象化しない。旧 KernelAction 風の集約は廃止傾向）

## FFI (emscripten)
- `#[unsafe(no_mangle)] pub unsafe extern "C" fn`
- 冒頭で null チェック（`return u64::MAX` 等のセンチネル）
- 文字列: `CStr::from_ptr(x).to_string_lossy().into_owned()` で受ける
- 戻り値: `CString::new(s).unwrap().into_raw()`（意図的なリーク許容。ccall "string" が JS 側でコピー）
- ポインタ: `Box::into_raw` / `Box::from_raw`

## Lua (bootstrap.lua 等)
- テーブルリテラル内に 1 行関数: `list = function(path) return simple({ List = path }) end`
- syscall 応答は `simple()` でアンラップする統一パターン
- snake_case

## 検証文化
- 挙動変更は禁止に近い水準で維持し、変更時は Playwright E2E（debug シェルで ls ×2＋プロンプト復帰）で回帰確認
- diff は最小限に。コメントの書き直し等のノイズを入れない
