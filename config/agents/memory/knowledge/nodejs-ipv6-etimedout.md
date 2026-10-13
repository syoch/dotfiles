# Node fetch が ETIMEDOUT になる（IPv6 有効でない環境）

IPv6 アドレスを持たない VPS 上で Node の `fetch` が固まる問題の診断と対処。

## 症状

`fetch failed` または `AggregateError [ETIMEDOUT]`。
同じホストに対して curl は成功するので、ネットワークや証明書の問題ではない。

## 原因

Node 20 以降の undici は `autoSelectFamily`（Happy Eyeballs）を既定で有効にしており、
解決した IPv6 アドレスを先に試す。有効な IPv6 経路が無い環境では接続が-establish されず、
タイムアウト까지待ち続ける。

## 判別のしかた

```bash
curl -4 https://example.com/            # 成功する
curl -6 https://example.com/            # 失敗する
```

`curl -4` が成功して Node の `fetch` がタイムアウトするなら、この問題である。

## 対処

### プロセス起動時のフラグ（最も簡単）

```bash
NODE_OPTIONS=--no-network-family-autoselection
```

systemd なら `EnvironmentFile` で渡して `systemctl restart` する。

**`--dns-result-order=ipv4first` では直らない。** これは DNS の回答順を変えるだけで、
接続先の自動選択を無効化する-effect はない。

### コードで指定する

```js
import { Agent, setGlobalDispatcher } from "undici";
setGlobalDispatcher(new Agent({ connect: { autoSelectFamily: false } }));
```

環境変数の方がACHED simple で、追加の依存も要らない。
