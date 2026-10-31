import AppKit
import SwiftUI

/// サイドナビ下部の更新カード。更新の有無で表示し分ける。
/// 更新ありはOSテーマ色（アクセント色）の背景でクリックでインストールダイアログを
/// 出す。更新なしは透明に近い背景でクリックで非表示化する
/// （10秒後の自動非表示はUpdateCheckController側）。
struct UpdateCardView: View {
    let controller: UpdateCheckController
    let language: String
    let fontScale: CGFloat
    /// 更新ありカードのテキスト色。ライト・ダークどちらのモードでも強調して見える色。
    let availableTextColor: Color

    var body: some View {
        if let card = controller.card {
            Divider()
            switch card {
            case .available:
                Button {
                    controller.showInstallDialog()
                } label: {
                    cardLabel(
                        text: L10n.string("nav.updateAvailable", language: language),
                        icon: "arrow.down.circle.fill"
                    )
                    // 更新カードはLiquid Glassで表示。背景色はOSのテーマカラー
                    // （アクセント色）。不透明な塗りはグラスを飽和させるため半透明で重ねる。
                    .glassEffect(
                        .regular
                            .tint(Color.accentColor.opacity(GlassStyle.updateCardTintOpacity))
                            .interactive(),
                        in: RoundedRectangle(cornerRadius: GlassStyle.updateCardCornerRadius)
                    )
                    .bold()
                    // ライト・ダークどちらのモードでも読める強調色。
                    // 半透明のアクセントtintの上で白一色だとライトモードで
                    // 埋もれるため、実効スキームに応じて色を選ぶ。
                    .foregroundStyle(availableTextColor)
                    // ホバー時はポインターカーソルにし、クリック可能と分かるようにする。
                    .onHover { hovering in
                        if hovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                .padding(.vertical, 8)
            case .noUpdate:
                Button {
                    controller.dismissCard()
                } label: {
                    cardLabel(
                        text: L10n.string("nav.updateNone", language: language),
                        icon: "checkmark.circle"
                    )
                    // 更新なしはLiquid Glassで透明に近い目立たない色にする。
                    .glassEffect(
                        .regular
                            .tint(Color.accentColor.opacity(GlassStyle.updateCardNoneTintOpacity))
                            .interactive(),
                        in: RoundedRectangle(cornerRadius: GlassStyle.updateCardCornerRadius)
                    )
                    // サイドナビのメニュー項目と同じテキスト色（標準のprimary）。
                    .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
        }
    }

    /// 両カードで見た目の共通部分を纏めるラベル。文言とアイコンだけを受け取る。
    private func cardLabel(text: String, icon: String) -> some View {
        Label {
            Text(text)
                .font(AppTheme.font(.body, scale: fontScale))
        } icon: {
            Image(systemName: icon)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}
