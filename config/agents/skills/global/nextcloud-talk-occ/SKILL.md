---
name: nextcloud-talk-occ
description: Use when calling NextCloud Talk occ commands (talk:room:create, talk:room:add, talk:bot:install, talk:bot:setup, talk:bot:list, talk:bot:uninstall) from a script or service, or when occ fails with unknown option, exit 1, or permission/directory errors. Covers exact argument shapes on spreed 25 / NextCloud 35, the nextcloud-occ wrapper permission model (User=nextcloud, sudoers matches env/php/occ not the wrapper), and the two required directories (configDatadir + dataDirectory). Trigger keywords: occ talk, talk:bot:install, talk:room:create, --url unknown option, nextcloud-occ wrapper, sudoers occ, ReadWritePaths, configDatadir, dataDirectory, talk:bot:uninstall, ID: N, spreed version.
---

# NextCloud Talk occ コマンドと権限モデル

実測に基づく（sv01: NextCloud 35.0.0 / spreed **v25.0.0**、ラッパー `nextcloud-occ`）。
**stable31 = Talk 21** なので、stable 系ドキュメントは鵜呑みにしない。

## いつ使うか

- `talk:room:create` / `talk:bot:install` / `talk:bot:setup` / `talk:bot:list` / `talk:bot:uninstall` を
  スクリプトや bridge から呼ぶとき
- occ が exit 1 で「パラメータ不明」と言われたとき（ほぼ `--url` / `--output` の付け過ぎ）
- occ の権限やディレクトリ要件で落ちたとき

## 手順

### 1. バージョンを先に確定する

```bash
occ app:list --enabled | grep -i spreed   # → spreed: 25.0.0
```

読解はバージョンを固定してから行う。stable31（Talk 21）の API 表を当てると誤る。

### 2. コマンドごとの正確な形

| command | 事実 |
|---|---|
| `talk:room:create <slug> --user <human> --listable 0` | `--public` は **VALUE_NONE**。**既定が既に TYPE_GROUP(2)**。`--user` は複数可。`--listable 0`=非掲載。出力は `Room token: <token>` |
| `talk:room:add <token> --user U` | **`token` が positional**。`--user` は option |
| `talk:bot:install <name> <secret> <url> --feature ...` | **`--output` は無い**が stdout 2 行目に `ID: N`。**id を出すので `talk:bot:list` 往復は不要** |
| `talk:bot:setup <bot-id> <token>...` | .setup は**その場で webhook を POST する**。registry 行が未登録なら 404 |
| `talk:bot:list -v --output json` | `writeTableInOutputFormat` なので `--output json` が使える。**`-v` が無いと `url` 列が除去される**（`-v` は secret も出す） |
| `talk:bot:uninstall [id] \| --url <url>` | **`--url` を宣言するのはこのコマンドだけ**。url 照合が確実（bot 名は衝突しうる） |

- secret は **40〜128 文字**（`validateBotParameters`）
- `talk:bot:install` の終了コード: **1**=パラメータ/排他違反、**2**=url 重複、**3**=secret 重複
- **`--url` / `--output` は許可リストで宣言する**。`OC\Core\Command\Base::configure()` は `--output` のみを宣言。
  `talk:room:create` は `parent::configure()` を呼びすら呼ばない。**未宣言オプションは Symfony が必ず失敗させる**
- token の取り出しは `/Room token:\s*(\S+)/` の行マッチ。
  緩い `/[a-z0-9]{8,64}/` だと会話名や説明文の単語を掴む

### 3. 権限モデル

`nextcloud-occ` ラッパーは **root 権限で走り、`nextcloud` ユーザーへ昇格する**。
しかも sudo されるのは wrapper ではなく `env` + `php` + `occ` なので、
**wrapper パスを sudoers に書いても一致しない** → 専用ユーザーでは全 occ が失敗する。

→ occ を呼ぶサービスは `User = nextcloud` で実行する。

### 4. 2 つのディレクトリ

occ は両方を検査し、**どちらかを写到ないと全滅**。書き込み可否は毎回チェックされる。

| 名前 | 内容 | sv01 の値 | 必要 |
|---|---|---|---|
| `configDatadir` | `config.php`。ラッパーが `NEXTCLOUD_CONFIG_DIR` に設定 | `/var/lib/nextcloud` | ReadWritePaths |
| `dataDirectory` | ユーザーファイル | `/srv/NAS/nextcloud` | ReadWritePaths |

`settings.datadirectory`（= dataDirectory）は module option ではないため
`services.nextcloud.settings.datadirectory` から読む。

### 5. パッケージ名

`pkgs.nextcloud` は**存在しない**（実体は `nextcloud35` 等）。
`environment.systemPackages` に入る **`nextcloud-occ` ラッパー**を使う
（php と extensions が設定済み。`php` を直接呼ばない）。

## 検証方法

- 1 コマンドずつ exit code + stdout + stderr をファイルに保存してから読む（`Promise.race` で throw した probe は捨てない）
- 作成系は必ず**後始末**を確認する: `talk:room:delete <token>` → exit 0
- 往復確認: `talk:bot:list -v --output json` で `features: webhook, response, reaction` と `url` を確認
- 権限確認: `systemctl show talk-bridge -p User` が `nextcloud`、
  `ReadWritePaths` に上記 2 ディレクトリがあること
- テストでは **stub の `ID: N` 出力行と exit code を実測どおりに再現**する

## 落とし穴

1. **`--url` を全部に付ける** → NC35 では `talk:bot:uninstall` だけが宣言している。許可リストは空にして uninstall だけ例外
2. **id を `talk:bot:list` で取りに行く** → `-v` が要ると secret が漏ける。`install` の stdout `ID: N` を直接パース
3. **`--output json` を Speak 共通の前提で使う** → 宣言しているコマンドのみ。`writeTableInOutputFormat` の継承次第
4. **`talk:bot:setup` の失敗を握り潰す** → setup は webhook を即 POST するため、registry 行が無い段階で 404。
   握り潰すと**壊れた venue が成功扱いで残る**
5. **root で走らせて専用ユーザーから occ を呼ぶ** → sudoers が一致しない。`User = nextcloud`
6. **`configDatadir` だけ、或いは `dataDirectory` だけ**許す → 全 occ が失敗する
7. **token を行，而非**，緩い正規表現で抜く → 説明文の単語を掴む
8. **stable31 の API 表を当てて読む** → Talk 21 であり `event` feature の排他制約自体が違う
