---
name: youtube-live-auto-caption-summary
description: Use when summarizing a long YouTube live stream (conference talk, presentation session) from captions, especially Japanese. Auto captions must be fetched separately from manual ones, and presentation numbering/titles should be verified against an official source rather than trusted from ASR. Trigger keywords: YouTube live summary, 字幕, 自動字幕, ASR, 配信まとめ, live_chat, ja-orig, procon.
---

# YouTube ライブ配信の字幕から要約を作る

## いつ使う
- 長時間（1時間超）の YouTube ライブ配信（カンファレンス、発表セッション、質疑応答つき発表）を要約・解析したい時。
- 音声を聞く代わりに字幕を一次情報として使いたい時。

## 前提: 字幕の入手
- `yt-dlp --list-subs` で**手動字幕（manual）と自動字幕（automatic）を分けて確認**する。
- ライブ配信では手動字幕が `live_chat` だけ、というケースが多い。これは「本文字幕が無い」ことを意味しない。**自動字幕側に本文が別言語で存在する**。
- 日本語配信は `--sub-langs "ja-orig"` が原话语焉，`ja` は翻訳調なので避ける。
- プレイヤーの字幕ボタンに言語が並んでいるなら自動字幕が存在する。「字幕なし」と判断しない。

## 手順
1. 字幕を取得（動画本体は不要）
   ```bash
   nix run nixpkgs#yt-dlp -- --skip-download \
     --write-auto-subs --write-subs --sub-langs "ja-orig,ja" \
     --sub-format vtt -o "<name>.%(ext)s" "<url>"
   ```
2. VTT → 逐語録へ変換。隣接する `<00:00:01.000>` ブロックは更新行なので、直前の時刻を保持しつつ本文だけを連結する。本文が空の行はスキップ。
3. 区間特定。ASRテキスト中の「発表番号 N 番」「N 番目」「質疑に移ります」「ご発表ありがとうございました」で発表/質疑の境界を取る。質疑は発表開始 +9 分前后开始，+12〜13 分で終了する。
4. メタデータで裏取り（重要）。ASR だけでは固有名詞・順序が崩れる。大会・カンファレンスなら**公式の資料 PDF** を必ず取得し、発表順・所属と突き合わせる。
5. 要約は「要約」で書く。逐語の引用はしない。

## 検証方法
- 抽出した各発表について、司会のアナウンス（発表番号 N 番）と逐語録の時刻が整合しているか確認する。
- メタデータ PDF と突き合わせた後、不一致だった箇所は推測で埋めずに「要確認」と書く。

## 落とし穴
- **ASR の二重化**。逐語をそのまま貼り付けて要約すると、ASR誤り＋自分の解釈の誤りが重なって判読不能になる。補修は文脈で行い、確実に読めない箇所は〔不明〕として除外する。
- **手動字幕しか無く見えると誤判断**して「字幕なし」と結論する。実際の自動字幕に本文が入っているケースが最多。
- **ライブチャットリプレイは壊れていることが多い**。`live_chat` 手動字幕が取れる程度。チャットを情報源に依存しない。
- `nix run nixpkgs#poppler-utils` は失敗する（poppler_utils から poppler-utils へ rename 済）。`nix shell nixpkgs#poppler-utils -c <cmd>` を使う。
- PDF 内リンクのラベルはリンク要素の直後にある場合がある。「リンク→直後のテキスト」対応で取得できる。
