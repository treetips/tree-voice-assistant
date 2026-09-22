import SwiftUI

/// 利用上の注意・同意事項のシート。
/// 初回起動時はチェック＋同意しないと閉じられ、Aboutからは閲覧のみで閉じられる。
struct ConsentView: View {
    var language: String
    /// true=初回の同意要求、false=Aboutからの再表示。
    var requiresAgreement: Bool
    var onAgree: () -> Void
    var onClose: () -> Void

    @State private var checked = false

    private func t(_ key: String) -> String { L10n.string(key, language: language) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(t("consent.title")).appFont(.title3)

            ScrollView {
                Text(t("consent.body"))
                    .appFont(.body)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if requiresAgreement {
                Toggle(isOn: $checked) {
                    Text(t("consent.check"))
                        .appFont(.body)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .toggleStyle(.checkbox)

                GlassCTAButton(title: t("consent.agree"), disabled: !checked) {
                    onAgree()
                }
            } else {
                GlassCTAButton(title: t("consent.close")) {
                    onClose()
                }
            }
        }
        .padding(24)
        .frame(width: 560, height: 520)
        .interactiveDismissDisabled(requiresAgreement)
    }
}
