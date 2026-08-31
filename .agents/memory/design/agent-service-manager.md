# Agent Service Manager 再設計（tasks ツール代替・実装完了 2026-08-25）

## 実装状態

`modules-hm/apps/opencode/tasks.ts` に実装済み。統合テスト 15/15 PASS（/tmp/opencode/tasks-integration.ts、bun 直 execute 呼び出し）+ `opencode run` エンドツーエンド確認済み。

## 確定設計（実装済み）

**固定セッション `oc-tasks` + 1 ウィンドウ 1 タスク方式**

```
起動: has-session 確認 → new-window -d -P -F '#{pane_id}' -t oc-tasks -n <name> '<script>'
      (セッション無ければ new-session -d -s oc-tasks ...)
停止: kill-pane（tracking は %N pane ID のまま）
```

- ユーザー自身の `oc-tasks` セッションがあっても混ぜて OK
- ユーザーのセッション/ウィンドウには一切触れない（テストで session 集合差分により検証）
- 最後の window が消えるとセッション自動消滅 → 次回 start で自動再作成

## 状態検証（新規）

- `isRunning()` = pane 存在 OR マーカー存在（起動直後の touch 前ギャップも running 扱い）
- `status()`:
  - pane 生 & マーカー有 → running
  - pane 死 & マーカー残 → **terminated**（stale マーカー自動削除。外部クローズ検出）
  - マーカー無 & log 有 → completed / json 無 → killed / log 無 → unknown

## ラッパースクリプトの変更（競合対策）

プロセス代替(`exec > >(tee)`)から**同期パイプライン**へ変更:

```bash
{ banner; touch marker; <command>; s=$?; echo completed-banner; printf %s "$s" > <id>.exit; } 2>&1 | tee -a <id>.log
rm -f marker   # tee 排水完了後に必ず走る
exit "$(cat exitfile)"
```

- ログフラッシュ前にマーカーが消える競合を構造的に解消
- 終了コードは `.exit` サイドファイル経由で正確に伝達（kill/cleanup 対象に `.exit` 追加）

## サービス定義

`.agents/services/<name>.sh`（実行可能スクリプトそのもの）。`tasks_start(name)` の command 省略時のみ参照、無ければ明示エラー。カタログ事前整備はしない（作業エージェントが必要時に各自定義する規約）。ctx.worktree/directory をルートに使用。

## launchWindow のリトライ

最後のタスク kill → セッション非同期 teardown の直後の start が競合し得るため、失敗時 150ms 間隔で 1 回リトライ + stderr をエラーメッセージに含める。

## 見送ったもの

systemd transient unit 方式（将来 cgroup レベル厳密さが必要なら再検討）、macOS launchd アダプタ（tmux 維持で不要）。
