---
name: project-provision
description: Use when creating or tearing down a project venue for the agent stack (LDAP group and role users, Talk room, Deck board, /shared folder, opencode session, talk_bind). Trigger keywords: プロジェクト作成, venue 作成, project venue, 新しいロール, talk room 作成, Deck ボード作成, 共有フォルダ作成, project-provision, teardown, bind session.
---

# プロジェクト venue の作成

`scripts/project-provision` が agent 用 venue を 4 ステップで做成する。

## いつ使うか

新しいプロジェクト/venue を Talk + Deck + NextCloud に立ち上げるとき。
1 _roles を増やしたいとき(`add-role`)、セッションを後から紐付けたいとき(`bind`)、
テスト後に完全に取り下げたいとき(`teardown`)に使う。

## 手順

```bash
# 1. 作成(冪等)。4 ステップ: lead ユーザー+セッション / Talk room / Deck board / /shared
scripts/project-provision create <project> [--title T] [--dir ~/ghq/github.com/syoch/<group>]

# 2. ロールを追加(procon のように複数ロールが必要なとき)
scripts/project-provision add-role <project> <suffix>

# 3. 既存セッションを紐付け(セッションは後からしか作れないため)
scripts/project-provision bind <project>-<role> <session-id> [--leader]

# 確認
scripts/project-provision status <project>

# 全消去(テスト後)。--yes 必須
scripts/project-provision teardown <project> --yes
```

## 検証方法

- `status` で talk token / deck board / 各ロールの bound を確認
- レシーバーは 10 秒ごとに `talk_bind` を読むので、**再起動不要**で新しいロールを拾う。
  `journalctl --user -u talk-poll.service -n 20 | grep polling <group>` で確認
- 全消去後は LDAP に group が残らないこと(`ldapctl.py list-groups`)、
  `talk_bind` に該当行がないこと、`~/.config/talk-venue/` が空であることを確認する

## 落とし穴(すべて実際に踏んだもの)

- **LDAP を作ったら NextCloud の Redis を必ず flush する**。
  NextCloud は LDAP 照会を Redis にキャッシュし、**存在しなかった uid の
  負のキャッシュ**も持つ。用户 생성 직後に認証するとその stale エントリを読んで
  **401** になる。パスワード 잘못같아 보이지만 Lexical Cause はキャッシュ。
  スクリプトは `flush_nextcloud_ldap_cache()` で必ず行う。

- **app password の発行で ssh の環境変数を使ってはいけない**。
  ssh は既定でリモートへ環境変数を転送しない(`SendEnv` 未設定)ので、
  `NC_PASS` が空になり occ が**限定 token**を発行して 401 になる。
  パスワードは**スクリプト本文**(ssh の stdin、暗号化経路)へ埋め込む。
  argv には入れない(`ps` で見えるため)。

- **`ldapctl.py ensure-agent` は既存 uid では no-op**。必ず `set-password` を
  続けること。限定 token になる。

- **occ の token は出力パースしない**。`talk:room:create` のメッセージ形式に
  依存しないよう、`GET /ocs/v2.php/apps/spreed/api/v4/room` の一覧を名前で照合して
  トークンを解決する(v1 には room 一覧がない。404)。

- **`ldapctl.py list_groups()` の型注釈は `list[str]` だが実際は
  `(cn, gidNumber, members)` のタプルリスト**。delete-user で回すと
  `cn=(name, gid, [...])` という壊れた filter になって `malformed filter` になる。

- **Deck の非 ocs ルートには `OCS-APIRequest` ヘッダが必須**。
  無いとブラウザ呼び出しとみなされ **412 CSRF** で弾かれる。
  対象: `DELETE /index.php/apps/deck/boards/{id}`、`DELETE /index.php/apps/deck/cards/{id}`、
  `DELETE /index.php/apps/deck/boards/{id}/acl/{aclId}`。

- **`teardown` は失敗した run の孤児を消せない**。manifest に無い session や
  board は残る。手動で消すか、作成が成功するまで teardown しないこと。
  board の所有者が LDAP 削除済みだと認証できなくなるので、
  その場合は**一時的に LDAP user を復活させてから消す**。

## 前提

sv01 への passwordless sudo(`nextcloud-occ` と `ldapctl.py` を駆動するため)。
