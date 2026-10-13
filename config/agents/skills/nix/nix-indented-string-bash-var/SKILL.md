---
name: nix-indented-string-bash-var
description: Use when writing bash variable expansion inside a Nix indented string (''...''), writeShellScript, or writeText, or when a flake evaluation fails with "undefined variable" or "unexpected invalid token". Trigger keywords: nix indented string, bash variable in nix, writeShellScript, setup-script, undefined variable, 2つのシングルクォート, ''${...}, nix trap, nix 補間.
args: &lt;flake.nix のパス&gt;
---

## いつ使うか

Nix の indented string（`''...''`）や `writeShellScript` / `writeText` の中で
bash の変数展開を書こうとしたときに使う。`error: undefined variable '...'` で
flake の評価が失敗する原因と、書き方を 1 箇所にまとめている。

## 罠

Nix の indented string 内では `${...}` は **Nix の補間**として解釈される。
素の `${procon_head_hash}` と書くと、flake の評価が失敗する。

```
error: undefined variable 'procon_head_hash'
```

このときスクリプトの bash として正しい場合は、**Nix 側の書き方が間違っている**。

## 書き方

bash の変数展開を書きたい場合は `''${...}` と **2 つのシングルクォート**を付ける。

```nix
procon_head_hash=''${procon_head_hash}-dirty
```

生成される bash では通常の `${procon_head_hash}` になっている。

## 同じ制約が効く場所

| 場所 | 症状 | 対処 |
|---|---|---|
| コメント中の `${...}` | `syntax error, unexpected invalid token` | 波括弧を直接書かず「波括弧」と書く |
| 単独のバッククォート | indented string の終端と解釈される | コメントに使わない |

## 回避策（純 Nix 変数で完結させる）

eval 時に Nix 変数で env ファイルを作るなら bash 変数は要らない。

```nix
pkgs.writeText "file" ''PROCON_HEAD_HASH=${hash}''
```

この場合 `${hash}` は Nix 変数なので素の `${}` で書ける。

ハッシュを eval に渡すには `builtins.getEnv` が必要で、pure eval では空文字を返すため
`--impure` が要る（再現性と CI キャッシュを犠牲にする）。

この制約の対処は、**setup-script で bash に実行させる**側に寄せるか、
**eval 時点で閉じる**かの 2 通りから選ぶ。

## 検証

flake の評価が通ることを確認する。

```bash
nix flake check
nix build .#packages.$(nix eval --raw --impure --expr builtins.currentSystem)
```

生成されたスクリプトの中身は nix store を直接読む。

```bash
nix build --dry-run 2>&1 | grep setup
```

## 関連

- プロコンの setup-script の設計判断は `infra/README.md` の「ハッシュの生成」に置いてある。
  **構文の知識は置かない。** 運用者は読まない
