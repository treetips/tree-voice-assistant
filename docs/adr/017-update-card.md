# サイドナビ下部の更新カードを更新の有無で表示し分ける

- ステータス: Accepted
- 影響範囲: `Core/UpdateCheckController.swift`、`Core/GlassCard.swift`、`App/RootView.swift`、`Resources/Localizable.xcstrings`
- 関連: tree-image-optimizer ADR 0030（サイドナビ下部の更新カードを更新の有無で表示し分ける）

## 背景

起動時のサイレント確認（`refreshAvailability`）は「更新あり」のときだけサイドナビに
通知を出していたため、ユーザーは通知が出ないとき「確認したのか・更新が無いのか」が
分からなかった。更新カードは更新の有無の双方で出し、更新なしは一定時間で自動的に
消すことになった。

## 決定

- サイドナビ最下部に更新カード (`UpdateCard`) を表示する。
    - 更新あり (`available`): 背景色はOSテーマカラー（アクセント色）。テキスト色は
      ライト・ダークどちらのモードでも強調して見やすい色（実効スキームで白/標準
      テキスト色を選択）。クリックで
      インストール確認ダイアログを開く（サイレント確認結果を元にし、再確認しない）。
    - 更新なし (`noUpdate`): 背景色は透明に近い目立たない色。テキスト色はサイドナビの
      メニュー項目と同様の標準色。クリックでカードを
      非表示化する。
- 両カードともLiquid Glassで表示する。`.glassEffect` の tints は既存パターンに
  合わせ半透明アクセント色で重ねる（不透明な塗りはグラスを飽和させてベタ塗りに
  見えるため）。濃さ・角丸は `GlassStyle` に一元化する
  （`updateCardTintOpacity` / `updateCardNoneTintOpacity` / `updateCardCornerRadius`）。
- 更新なしカードは10秒後に自動で非表示化する。定数は
  `UpdateCheckController.noUpdateCardHideSeconds`。
- カード状態は `UpdateCheckController.card` に持ち、起動時のサイレント確認
  (`refreshAvailability`) で解決する。確認失敗も「更新なし」扱いで表示する。
  クリック非表示・10秒後の自動非表示・カード差し替えの間のタイマー競合は、
  状態の差し替え時に必ず旧タイマーをキャンセルして防ぐ。
- 旧通知用プロパティ `updateAvailableInfo` は `card` に統合して削除する。
- 更新確認結果→カード状態の解決は `UpdateCheckController.resolveCard(for:)` と
  いう純粋関数に切り出し、単体テストで検証する。

## 結果

- 更新カードが更新の有無で表示し分けられ、更新なしはクリック・10秒経過の
  どちらでも非表示化される。
- `UpdateLogicTests` で確認結果→カード状態の解決と、更新なしカードの文言を
  検証した。`GlassCardTests` にカードの濃さ・角丸の固定を追加した。
- 実装箇所:
  - `TreeVoiceAssistant/TreeVoiceAssistant/Core/UpdateCheckController.swift`
  - `TreeVoiceAssistant/TreeVoiceAssistant/Core/GlassCard.swift`
  - `TreeVoiceAssistant/TreeVoiceAssistant/App/RootView.swift`
  - `TreeVoiceAssistant/TreeVoiceAssistant/App/UpdateCardView.swift`
  - `TreeVoiceAssistant/TreeVoiceAssistant/Resources/Localizable.xcstrings`

### テキスト色（tree-image-optimizer ADR 0030 への追記分も含む）

- 更新ありカード: 白一色だとライトモードで半透明アクセントtintに埋もれるため、
  実効スキームに応じて白（ダーク） / 標準テキスト色（ライト）を選ぶ。
  実効スキームは `RootView.appearanceScheme`（自動モードはシステム設定に解決済み）。
- 更新なしカード: サイドナビのメニュー項目と同じ標準のprimary色にして
  目立ちすぎないようにする。
