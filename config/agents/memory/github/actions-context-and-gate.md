GitHub Actions のコンテキストは使える場所が決まっている。

- **ジョブレベルの `env:` では `runner` コンテキストが使えない**（使えるのは `github` / `inputs` / `matrix` / `needs` / `secrets` / `strategy` / `vars`）。`${{ runner.temp }}` を書くと「This run likely failed because of a workflow file issue.」で 0 秒失敗し、`pull_request` の run が作られない。
- 代わりは `${{ github.workspace }}`。`$RUNNER_TEMP` はランナーが設定する実環境変数なので、run スクリプト側（`$RUNNER_TEMP`）と job env 側（`${{ github.workspace }}`）で使い分ける。
- ワークフロー検証は `nix-shell -p actionlint --run "actionlint <file>"` でできる。パッケージの fetch に 1〜2 分かかるが、原因行を正確に指す。
  - shellcheck の SC2016（シングルクォート内の `$` やバッククォート）は info 扱いで GitHub は通す。`echo '```'` のような書き方は info になるだけ。
- 「計測はできたが判定が成立しない」状態（比較不成立）を 1 ジョブで表す時は、比較ステップに `id` と `continue-on-error: true` を付け、`set +e` の中で `code=${PIPESTATUS[0]}` を取り出してから `GITHUB_OUTPUT` に出す。
  ジョブの `if` で skipped にすると、計測を始める前に条件判断することになり、状態を 1 つのジョブでは表せない。
