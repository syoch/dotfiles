# read-only mount は隔離境界にならない

**`:ro` は「書けない」だけで「読めない」ではない。**
機密データや作業ディレクトリを読ませない方針があるなら、
read-only mount で渡すのは方針違反に等しい。
渡さない Hardware が正解。

実測例（2026-10-05、procon の pr-review-bot）:

- `<repo>` を `:ro` にした結果、`AGENTS.md` が「`.private/` は共有しません」と
  定める `.private/`（context / references / ws / reports）が agent から全部読めた。
- `.git` への書き込みは `Read-only file system` で失敗するので破壊は防げた。
  だが読み取りは防げていない。

**判断の順序**:

1. そのパスを読ませてはいけないものか? → いけないなら mount しない
2. 読ませる必要最小限だけに絞って bind するか
3. それが read-only で足りるか

3 番で足りなければ深_paths を重ねる（Docker は深いパスを先に被せる）。

`git worktree prune` による管理情報全削除事故の教訓と併せて参照。
global skill `git/worktree-prune-hazard` を参照。

source: procon pr-review-bot の mount 再設計（2026-10-05）