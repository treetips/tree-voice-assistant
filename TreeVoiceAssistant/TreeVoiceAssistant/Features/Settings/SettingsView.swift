import AppKit
import SwiftUI

/// 設定画面。
struct SettingsView: View {
    @State private var viewModel: SettingsViewModel

    init(viewModel: SettingsViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    @Environment(\.locale) private var locale
    private var lang: String { locale.language.languageCode?.identifier ?? "" }
    private func t(_ key: String) -> String { L10n.string(key, language: lang) }

    @State private var bgHexDraft = ""
    @State private var bgHexInvalid = false
    @State private var bgHexFieldID = UUID()

    private var backgroundColorBinding: Binding<Color> {
        Binding(
            get: { parseHex(viewModel.effectiveWallpaperBackgroundColorHex) ?? .white },
            set: {
                viewModel.wallpaperBackgroundColorHex = hexString($0)
                bgHexDraft = viewModel.wallpaperBackgroundColorHex
                bgHexInvalid = false
            }
        )
    }

    /// Enter確定時にドラフトを検証・反映する。
    private func commitBgHex() {
        let input = bgHexDraft
        if viewModel.commitBackgroundHex(input) {
            bgHexInvalid = false
        } else {
            bgHexInvalid = true
            bgHexDraft = viewModel.wallpaperBackgroundColorHex
            bgHexFieldID = UUID()
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Toggle(isOn: $viewModel.showOsNotification) {
                                Text(t("s.showNotification")).appFont(.body)
                            }
                            .help(t("s.help.showNotification"))
                            .gridCellColumns(2)
                        }
                        GridRow {
                            Toggle(isOn: $viewModel.playSound) {
                                Text(t("s.playSound")).appFont(.body)
                            }
                            .gridCellColumns(2)
                        }
                        GridRow {
                            Text(t("s.successSound")).appFont(.body)
                            HStack {
                                soundPicker(
                                    titleKey: "s.successSound",
                                    selection: $viewModel.successSound,
                                    options: viewModel.successSounds,
                                    enabled: viewModel.playSound
                                )
                                Button {
                                    viewModel.playSuccessSound()
                                } label: {
                                    Image(systemName: "play.fill")
                                }
                                .help(t("s.help.playThis"))
                                .disabled(viewModel.successSound.isEmpty)
                                Spacer()
                                HelpPopover(text: t("s.help.successSound"))
                            }
                        }
                        GridRow {
                            Text(t("s.errorSound")).appFont(.body)
                            HStack {
                                soundPicker(
                                    titleKey: "s.errorSound",
                                    selection: $viewModel.errorSound,
                                    options: viewModel.errorSounds,
                                    enabled: viewModel.playSound
                                )
                                Button {
                                    viewModel.playErrorSound()
                                } label: {
                                    Image(systemName: "play.fill")
                                }
                                .help(t("s.help.playThis"))
                                .disabled(viewModel.errorSound.isEmpty)
                                Spacer()
                                HelpPopover(text: t("s.help.errorSound"))
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } label: {
                    Text(t("s.group.action")).appFont(.headline)
                }
                .frame(maxWidth: .infinity)

                GroupBox {
                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                        GridRow {
                            Text(t("s.appearance")).appFont(.body)
                            HStack(spacing: 8) {
                                radioButton(
                                    title: t("s.appearance.auto"),
                                    icon: "circle.lefthalf.filled",
                                    selected: viewModel.appearance == AppearanceMode.auto.rawValue
                                ) {
                                    viewModel.setAppearance(AppearanceMode.auto.rawValue)
                                }
                                radioButton(
                                    title: t("s.appearance.light"),
                                    icon: "sun.max",
                                    selected: viewModel.appearance == AppearanceMode.light.rawValue
                                ) {
                                    viewModel.setAppearance(AppearanceMode.light.rawValue)
                                }
                                radioButton(
                                    title: t("s.appearance.dark"),
                                    icon: "moon",
                                    selected: viewModel.appearance == AppearanceMode.dark.rawValue
                                ) {
                                    viewModel.setAppearance(AppearanceMode.dark.rawValue)
                                }
                                Spacer()
                            }
                        }
                        GridRow {
                            Text(t("s.language")).appFont(.body)
                            HStack {
                                Picker(t("s.language"), selection: $viewModel.language) {
                                    Text(t("s.language.auto")).appFont(.body).tag("")
                                    Text(t("s.language.ja")).appFont(.body).tag("ja-JP")
                                    Text(t("s.language.en")).appFont(.body).tag("en-US")
                                }
                                .labelsHidden()
                                Spacer()
                                HelpPopover(text: t("s.help.language"))
                            }
                        }
                        GridRow {
                            Text(t("s.fontSize")).appFont(.body)
                            HStack(spacing: 8) {
                                radioButton(
                                    title: t("s.fontSize.small"),
                                    icon: "textformat.size.smaller",
                                    selected: viewModel.fontSize == FontSizeOption.small.rawValue
                                ) {
                                    viewModel.fontSize = FontSizeOption.small.rawValue
                                }
                                radioButton(
                                    title: t("s.fontSize.standard"),
                                    icon: "textformat.size",
                                    selected: viewModel.fontSize == FontSizeOption.standard.rawValue
                                ) {
                                    viewModel.fontSize = FontSizeOption.standard.rawValue
                                }
                                radioButton(
                                    title: t("s.fontSize.large"),
                                    icon: "textformat.size.larger",
                                    selected: viewModel.fontSize == FontSizeOption.large.rawValue
                                ) {
                                    viewModel.fontSize = FontSizeOption.large.rawValue
                                }
                                Spacer()
                            }
                        }
                        GridRow {
                            Text(t("s.wallpaper")).appFont(.body)
                            HStack {
                                Picker(t("s.wallpaper"), selection: $viewModel.wallpaper) {
                                    ForEach(viewModel.wallpapers) { option in
                                        Text(option.label(language: lang)).appFont(.body)
                                            .tag(option.name)
                                    }
                                }
                                .labelsHidden()
                                Spacer()
                                HelpPopover(text: t("s.help.wallpaper"))
                            }
                        }
                        GridRow {
                            Text(t("s.wallpaperOpacity")).appFont(.body)
                            HStack {
                                Slider(value: $viewModel.wallpaperOpacity, in: 0...1)
                                Text(String(format: "%.1f", viewModel.wallpaperOpacity))
                                    .appFont(.body)
                                    .frame(width: 30)
                                Spacer()
                                HelpPopover(text: t("s.help.wallpaperOpacity"))
                            }
                        }
                        GridRow {
                            Text(t("s.wallpaperBackgroundColor")).appFont(.body)
                            HStack {
                                ColorPicker("", selection: backgroundColorBinding)
                                    .labelsHidden()
                                TextField(t("s.wallpaperBackgroundColor"), text: $bgHexDraft)
                                    .appFont(.body)
                                    .frame(width: 90)
                                    .id(bgHexFieldID)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(
                                                bgHexInvalid ? Color.red : Color.clear,
                                                lineWidth: 2
                                            )
                                    )
                                    .onSubmit { commitBgHex() }
                                    .onAppear { bgHexDraft = viewModel.wallpaperBackgroundColorHex }
                                Button(t("s.reset")) {
                                    viewModel.resetWallpaperBackgroundColor()
                                    bgHexDraft = viewModel.wallpaperBackgroundColorHex
                                    bgHexInvalid = false
                                }
                                .appFont(.body)
                                Spacer()
                                HelpPopover(text: t("s.help.wallpaperBackgroundColor"))
                            }
                        }
                    }
                    .padding(.vertical, 4)
                } label: {
                    Text(t("s.group.basic")).appFont(.headline)
                }
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal)
            .padding(.bottom, 0)
        }
        .navigationTitle(t("nav.settings"))
    }

    /// 枠で囲んだラジオ風ボタン。ラベルの左にアイコンを表示する。
    private func radioButton(
        title: String, icon: String, selected: Bool, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: selected ? "circle.inset.filled" : "circle")
                Image(systemName: icon)
                Text(title).appFont(.body)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(selected ? Color.accentColor : Color.secondary.opacity(0.4), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    /// サウンド選択プルダウン。一覧が空の場合はプレースホルダーを出す。
    @ViewBuilder
    private func soundPicker(
        titleKey: String, selection: Binding<String>, options: [SoundOption], enabled: Bool
    ) -> some View {
        if options.isEmpty {
            Text(t("s.noSound")).appFont(.body).foregroundStyle(.secondary)
        } else {
            Picker(t(titleKey), selection: selection) {
                ForEach(options) { option in
                    Text(option.label(language: lang)).appFont(.body).tag(option.name)
                }
            }
            .labelsHidden()
            .disabled(!enabled)
        }
    }

    private func parseHex(_ hex: String) -> Color? {
        var value = hex.trimmingCharacters(in: .whitespaces)
        if value.hasPrefix("#") { value.removeFirst() }
        if value.count == 6 { value = "FF" + value }
        guard value.count == 8, let number = UInt64(value, radix: 16) else { return nil }
        let alpha = Double((number >> 24) & 0xFF) / 255
        let red = Double((number >> 16) & 0xFF) / 255
        let green = Double((number >> 8) & 0xFF) / 255
        let blue = Double(number & 0xFF) / 255
        return Color(red: red, green: green, blue: blue, opacity: alpha)
    }

    private func hexString(_ color: Color) -> String {
        let resolved = NSColor(color).usingColorSpace(.sRGB) ?? NSColor(color)
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        resolved.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(
            format: "#%02X%02X%02X",
            Int(red * 255), Int(green * 255), Int(blue * 255)
        )
    }
}
