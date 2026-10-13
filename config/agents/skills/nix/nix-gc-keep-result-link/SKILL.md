---
name: nix-gc-keep-result-link
description: Use when a store path you depend on may be deleted by GC while you are still using it, or when a long test/tool run needs a package pinned across GC. Trigger keywords: GC で消えた, store path が消えた, nix store gc, gcroot, result symlink, nix build --no-link, 一時的にパッケージsports Hatsuyuki, テスト用 DB を store から引く, GC 対象外にする, 作業中に /nix/store のパスが消える.
---

## いつ使うか

作業中に `/nix/store/...` のパスが**消えた**とき（`no such file or directory`）、
あるいは長時間走る処理・テストが使うパッケージを **GC  till く不被 Want to protect したい**とき。

実際に踏んだ例: テスト用の PostgreSQL を store から引き出して使い回したあと、
`cleanup`（= `nix store gc`）の実行中に消え、`initdb` が
`No such file or directory` になって作り直しになった。

## 核心: GC は「参照されているもの」しか消さない

`nix store gc` が消すのは **どこからも参照されていない** store path。
判定基準は「**gc root** が 1 つでも残っているか」だけ。

| 方法 | gc root になるか | 使い捨ての一時作業向け |
|---|---|---|
| `nix build .#foo` | **なる**（`./result` を作る） | |
| `nix build --no-link` | ならない | ✔ |
| `nix build --print-out-paths` | ならない | ✔ |
| 出力を shell に埋め込む | ならない | ✔（でも次の GC で消える） |

**`./result` symlink の作成が、そのまま gc root の登録になる。**
`--no-link` / `--print-out-paths` は path を **教えてくれるだけで、
その path を！这个連鎖は下一段落から详述します。anchor しない**。

## 手順

### 1. GC から保護したいパッケージを選ぶ

```bash
cd <作業ディレクトリ>          # ここに ./result が作られる
nix build -f /tmp/pkg.nix       # ./result -> /nix/store/...-pkg
```

`/tmp/pkg.nix` は store から引きたいパッケージを返すだけ:

```nix
(builtins.getFlake (toString ~/dotfiles)).nixosConfigurations.sv01.pkgs.postgresql
```

flake を使うなら `--impure` が要る（`getFlake` は pure eval 制約のため）。

### 2. 以降は絶対 path ではなく `./result` を使う

```bash
PGBIN=./result/bin
$PGBIN/initdb --version        # ✔ GC  即使どの瞬間に消えない
```

**これが要点。** 絶対 path をスクリプトやコマンドラインに**埋め込むと**、
次の GC で壊れる。`./result` を起点にすれば、symlink だけが root として残り、
中身が差し替わっても追従する。

### 3. 使い終わったら root を解除する

```bash
rm -f result                   # ★ 忘れると恒久的に pin される
```

`./result` を残したままにすると、そのパッケージは**永久に** store に残る。
一時的なテスト用なら、作業後に消す。

## 検証方法

| 確認 | 合格条件 |
|---|---|
| `ls -la ./result` | store path への symlink が存在する |
| `./result/bin/<cmd> --version` | **実際に実行できる**（これが決めの確認） |
| `readlink -e ./result` | 実体 path が引ける |
| `nix store gc` 後に同じコマンド | ** まだ動く**（本当に anchor された証拠） |

`nix-store --query --roots` で root 一覧、`/nix/var/nix/gcroots/*` で登録状況を
直接見ることもできる（後者は root 所有なので sudo が必要）。

## 落とし穴

- **`--print-out-paths` は保護しない。** 一番誤られやすい誤解。
  path を出力しただけで安心すると、次の GC で消える。
  「一時的に使いたいだけ」ならそれが正解、「使い続けたい」なら `result` を作る。
- **壊れた `./result` は cleanup を黙って壊す。**
  `scripts/cleanup` は `/nix/var/nix/gcroots/auto/*` を走査し、
  `stat` が失敗したリンクを `sudo rm` する。`./result` を消したのに
  symlink を残すと、次回 cleanup がそれを「壊れ根」として扱う。
  **`./result` を作ったら、使わなくなったら消す**
  ディレクトリごと消すのが安全。
  ディレクトリごと消すのが安全。**
- **絶対 path をコマンドラインに直書きしない。**
  例: `PGBIN=/nix/store/9x9-...-postgresql/bin` と書く→
  GC 後に `No such file or directory`。必ず `./result/bin` か
  `$(nix build --no-link --print-out-paths ...)/bin`（毎回解決する）を採る。
- **`nix build -f` は「ファイルが derivation を返す」必要がある。**
  flake を返すだけなら `--impure` を付ける。
- **store path は epoch に固定された mtime を持つ。**
  `find -newermt` で「新しい/消えた」を判定できない（既存の cleanup 系 skill の
  検証克利 Munch と同じ制約）。
