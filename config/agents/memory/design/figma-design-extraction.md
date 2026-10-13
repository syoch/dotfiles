# Figma デザイン資産の解析方法: REST API 制限と .fig ローカル解析

Figma のデザインから値を抽出时被る 2 つの方法と、その制限の回避策。

## 方法 1: REST API（ネットワークが必要・レート制限がある）

`GET /v1/files/{file_key}` や `/v1/images/{file_key}` を使う。

**starter プランはレート制限が厳しく、`retry-after` で約 88 時間ブロックされることがある。**
ブロック中は API が使えないので、別の方法に切り替える。

## 方法 2: .fig ファイルのローカル解析（制限を受けない・推奨）

Figma のデスクトップアプリ / ブラウザのメインメニュー →
「ファイル」 → **「ローカルコピーを保存...」** で `~/Downloads/*.fig` を落とす。

Node の **`openfig-core`** の `parseFig(bytes)` で解析できる。
UI の自動操作が不要で安定している。

### ノードのフィールド

| フィールド | 内容 |
|---|---|
| `fillPaints` / `strokePaints` | 塗り・線 |
| `effects` | 影・ぼかしなど |
| バリアント（コンポーネントのプロパティ） |
| `prototypeInteractions` | プロトタイプ遷移 |

`nodeMap` / `childrenMap` のキーは `"sessionID:localID"` 形式で、`guid` から生成できる。

### インスタンス特有

- `symbolData.symbolID` で master 側のノードを引ける
- `symbolData.symbolOverrides[].prototypeInteractions` で
  インスタンス単位の上書きされたプロトタイプ遷移を読める

## 使い分け

| 状況 | 方法 |
|---|---|
| レート制限にかかっていない、少量なら | REST API |
| 大量のノード・アニメーション仕様を取りたい | `.fig` ローカル解析 |
| API がブロックされた | `.fig` ローカル解析 |

ブラウザの UI を自動操作してエクスポートする手段もあるが、
`.fig` の解析の方が不安定な要素が少ない。
