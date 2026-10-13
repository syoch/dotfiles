# Playwright venv on Nix で libstdc++ が見つからない（2026-10-08）

`nix shell nixpkgs#python3` の中で venv を作って playwright を入れても、実行時に greenlet が落ちる。

```
ImportError: libstdc++.so.6: cannot open shared object file: No such file or directory
```

**`nix shell nixpkgs#stdenv.cc.cc.lib` を足しても直らない。** nix shell の LD_LIBRARY_PATH が python に伝播しないため。

**qk solution は LD_LIBRARY_PATH を直接指定すること。**

```bash
ls -d /nix/store/*gcc*-lib/lib/libstdc++.so.6 | head -1
LD_LIBRARY_PATH=/nix/store/<gcc-lib のパス>/lib /tmp/opencode/pw-venv/bin/python script.py
```

これで greenlet の import が通る。ブラウザは attach 先の chromium-cdp を使うのでローカルの Chromium は不要。

**他の注意点**

- `nix shell <pkg> -c 'a && b'` は動かない。`-c` は 1 つのプログラムを取るだけ。`nix shell ... -c bash -c 'a && b'` とする
- venv は `nix shell nixpkgs#python3 -c bash -c 'python3 -m venv <dir> && <dir>/bin/pip -q install playwright'`
- `nixpkgs#libstdcxx` という属性は存在しない（`libsigcxx` をcheduler される）

関連: global skill `nix-playwright-e2e-setup`（CDP に接続する手順は正しい。venv の libstdc++ だけが抜けている）
