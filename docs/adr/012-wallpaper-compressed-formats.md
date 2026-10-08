# 壁紙一覧で圧縮フォーマットを扱えるようにする

- ステータス: Accepted
- 影響範囲: `Services/WallpaperService.swift`、設定画面の背景画像
- 関連: tree-image-optimizer ADR 0023（壁紙表示の圧縮フォーマット対応）

## 背景

ユーザーが用意する背景画像は、画像変換アプリ (tree-image-optimizer) で
jxl / avif / webp に高速化・圧縮したものをそのまま使いたい要望がある。
従来は `WallpaperService.listWallpaperFiles` の拡張子フィルタが
jpg / jpeg / png のみを受け付けていたため、圧縮フォーマットのファイルは
一覧に出ず選択できなかった。

macOS 標準の ImageIO は jxl / avif / webp のデコードに対応しており、
壁紙表示に用いる `NSImage(contentsOf:)`（`RootView`）は ImageIO 経由で
読むため、表示側の変更は不要。一覧を絞っていた拡張子フィルタだけが
対象になる。

## 決定

- `WallpaperService.listWallpaperFiles` の拡張子フィルタに
  `jxl`, `avif`, `webp` を追加する。
- アニメーション用途の拡張子 (`avifs` など、動画壁紙) はスコープ外とする
  (静止画のみ)。
- デコードは macOS 標準の ImageIO に任せ、デコーダーやライブラリは
  追加しない。

## 代替案

- 独自に libjxl / libavif をリンクしてデコードする
  - 却下: ImageIO が同等のデコードを提供しており、依存とバンドルの複雑さを増やすだけのため。
- 使用前に png へ再変換して壁紙にする
  - 却下: ユーザーが「圧縮画像をそのまま使う」要件に反するため。

## 結果

- ユーザー配置フォルダ (`~/.config/tree-voice-assistant/wallpaper/`) に
  `.jxl` / `.avif` / `.webp` を置くだけで背景画像として選択できる。
- 実装箇所: `WallpaperService.listWallpaperFiles`
- テスト: `MediaServicesTests.wallpapers`（既存テストに圧縮フォーマットの
  期待を追加し、`.avifs` が除外されることをあわせて確認する）

## 適合確認

- 既存テストは削除せず、期待値を新仕様に合わせて更新する。
- デプロイメントターゲット macOS 26.0 を維持する。
