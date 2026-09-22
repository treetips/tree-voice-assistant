import SwiftUI

/// 実行・アップデート確認で共用するCTAボタン。
/// 横幅いっぱいにし、素通しのLiquid Glassでグラス感を出す。
struct GlassCTAButton: View {
    var title: String
    var disabled: Bool = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .appFont(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
                .glassEffect(
                    .regular.tint(Color.accentColor.opacity(0.5)).interactive(),
                    in: RoundedRectangle(cornerRadius: 14)
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }
}
