import AppKit
import Combine
import SwiftUI

/// 背景画像切替のクロスフェード時間（秒）。
private let wallpaperCrossfadeSeconds: Double = 0.5

/// 左サイドナビ＋右コンテンツ。
/// 背景に設定画面で選んだ壁紙（不透明度・背景色付き）を表示し、選択言語を適用する。
/// 更新ダイアログは常時表示のここで出す（メニュー操作時も前面に表示するため）。
struct RootView: View {
    @State private var navigation: SidebarNavigation
    @State private var settings: SettingsViewModel
    @State private var updateCheck: UpdateCheckController
    @State private var convertJobStore: ConvertJobStore
    // クロスフェード中に前面の下へ置いておく直前の壁紙。フェード完了後に解放する。
    @State private var outgoingWallpaper: OutgoingWallpaper?
    // 直前に背景画像の切替が起きた時刻。フェードの中断判定に使う。
    @State private var lastWallpaperChangeDate = Date.distantPast
    @State private var showUsageConsent = false
    private let agreementStore = AgreementStore(paths: AppPaths())

    // @MainActorの状態は呼び出し側で生成して渡す。
    // 既定引数での生成は呼び出し元文脈の扱いになり、新しい toolchain で誤りになる。
    init(
        navigation: SidebarNavigation,
        settings: SettingsViewModel,
        updateCheck: UpdateCheckController,
        convertJobStore: ConvertJobStore
    ) {
        _navigation = State(initialValue: navigation)
        _settings = State(initialValue: settings)
        _updateCheck = State(initialValue: updateCheck)
        _convertJobStore = State(initialValue: convertJobStore)
    }

    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                List(SidebarSelection.allCases, selection: $navigation.selection) { item in
                    NavigationLink(value: item) {
                        HStack(spacing: 6) {
                            Label {
                                Text(item.title(language: settings.language))
                                    .font(AppTheme.font(.body, scale: fontScale))
                            } icon: {
                                if isItemRunning(item) {
                                    SidebarLoadingIcon()
                                } else {
                                    Image(systemName: item.systemImage)
                                }
                            }
                            if item == .convert, convertJobStore.isRunning {
                                Spacer()
                                Text(convertProgressLabel)
                                    .font(AppTheme.font(.caption, scale: fontScale))
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .padding(.vertical, 8)
                        .background(alignment: .bottom) {
                            VStack(spacing: 0) {
                                Spacer(minLength: 0)
                                if item == .convert, convertJobStore.isRunning {
                                    IndeterminateLinearBar()
                                }
                            }
                        }
                    }
                }
                .navigationSplitViewColumnWidth(min: 180, ideal: 220)
                if updateCheck.updateAvailableInfo != nil {
                    Divider()
                    Button {
                        updateCheck.checkForUpdate(language: settings.language)
                    } label: {
                        Label {
                            Text(L10n.string("nav.updateAvailable", language: settings.language))
                                .font(AppTheme.font(.body, scale: fontScale))
                        } icon: {
                            Image(systemName: "arrow.down.circle.fill")
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.accentColor)
                        )
                        .foregroundStyle(.white)
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
                }
            }
        } detail: {
            ZStack {
                backgroundColor
                backgroundImage
                switch navigation.selection {
                case .convert:
                    ConvertView(jobStore: convertJobStore)
                case .settings:
                    SettingsView(viewModel: settings)
                case .about:
                    AboutView(controller: updateCheck)
                }
            }
        }
        .environment(\.locale, settings.effectiveLocale)
        .preferredColorScheme(appearanceScheme)
        .environment(\.sizeCategory, AppTheme.sizeCategory(for: settings.fontSize))
        .environment(\.appFontScale, AppTheme.fontScale(for: settings.fontSize))
        .onAppear {
            updateCheck.refreshAvailability()
            if !agreementStore.isAgreed {
                showUsageConsent = true
            }
        }
        .sheet(isPresented: $showUsageConsent) {
            ConsentView(
                language: settings.language,
                requiresAgreement: true,
                onAgree: {
                    try? agreementStore.agree()
                    showUsageConsent = false
                },
                onClose: {}
            )
        }
        .onReceive(
            DistributedNotificationCenter.default().publisher(
                for: Notification.Name("AppleInterfaceThemeChangedNotification")
            )
        ) { _ in
            settings.refreshAutoBackgroundColor()
        }
        .alert(
            Text(L10n.string("a.latest", language: settings.language))
                .font(AppTheme.font(.headline, scale: fontScale)),
            isPresented: $updateCheck.latestDialog
        ) {
            Button {
            } label: {
                Text(L10n.string("a.ok", language: settings.language))
                    .font(AppTheme.font(.body, scale: fontScale))
            }
        } message: {
            Text(L10n.string("a.latestMsg", language: settings.language))
                .font(AppTheme.font(.body, scale: fontScale))
        }
        .alert(
            Text(L10n.string("a.confirmInstall", language: settings.language))
                .font(AppTheme.font(.headline, scale: fontScale)),
            isPresented: Binding(
                get: { updateCheck.availableInfo != nil },
                set: { if !$0 { updateCheck.availableInfo = nil } }
            )
        ) {
            Button(role: .cancel) {
            } label: {
                Text(L10n.string("a.cancel", language: settings.language))
                    .font(AppTheme.font(.body, scale: fontScale))
            }
            if let info = updateCheck.availableInfo {
                Button {
                    updateCheck.install(info, language: settings.language)
                } label: {
                    Text(L10n.string("a.install", language: settings.language))
                        .font(AppTheme.font(.body, scale: fontScale))
                }
            }
        } message: {
            if let info = updateCheck.availableInfo {
                Text(String(
                    format: L10n.string("a.confirmInstallMsg", language: lang),
                    info.version
                ))
                .font(AppTheme.font(.body, scale: fontScale))
            }
        }
        .alert(
            Text(L10n.string("a.checkFailed", language: settings.language))
                .font(AppTheme.font(.headline, scale: fontScale)),
            isPresented: Binding(
                get: { updateCheck.errorDialog != nil },
                set: { if !$0 { updateCheck.errorDialog = nil } }
            )
        ) {
            Button {
            } label: {
                Text(L10n.string("a.ok", language: settings.language))
                    .font(AppTheme.font(.body, scale: fontScale))
            }
        } message: {
            Text(updateCheck.errorDialog ?? "")
                .font(AppTheme.font(.body, scale: fontScale))
        }
    }

    private var lang: String {
        settings.language
    }

    /// 設定の外観モードを配色に反映する。自動はシステム設定を読み取って解決する。
    private var appearanceScheme: ColorScheme {
        switch settings.appearance {
        case AppearanceMode.light.rawValue: return .light
        case AppearanceMode.dark.rawValue: return .dark
        default: return systemScheme
        }
    }

    private var systemScheme: ColorScheme {
        SettingsViewModel.systemIsDark() ? .dark : .light
    }

    private var fontScale: CGFloat {
        AppTheme.fontScale(for: settings.fontSize)
    }

    /// 実行中メニューの右端に表示する汎用ラベル。
    private var convertProgressLabel: String {
        L10n.string("nav.running", language: settings.language)
    }

    /// 実行中のメニューはアイコンをローディング表示に切り替える。
    private func isItemRunning(_ item: SidebarSelection) -> Bool {
        switch item {
        case .convert: return convertJobStore.isRunning
        case .settings, .about: return false
        }
    }

    private var backgroundColor: Color {
        parseHex(settings.effectiveWallpaperBackgroundColorHex) ?? .white
    }

    /// 表示対象の壁紙URL。「背景無し」選択時はnil。
    private var wallpaperURL: URL? {
        settings.wallpaperFileURL()
    }

    /// 直近の切替から、フェードと裏面解放が静まるまでの期間内かどうか。
    /// 期間内の追加切替はフェードを打ち切り即時切替にする。
    private var isWallpaperFadeSuppressed: Bool {
        lastWallpaperChangeDate.addingTimeInterval(wallpaperCrossfadeSeconds * 2) > Date.now
    }

    @ViewBuilder
    private var backgroundImage: some View {
        ZStack {
            // 直前の壁紙。不透明のまま背面に置き、新壁紙をその上へフェードインさせる。
            // 旧画像だけをフェードアウトさせると中間点で新旧が半透明になり、
            // 背景色が透けて一瞬濁って見えるため、不透明の裏面で隙間を埋める。
            if let outgoing = outgoingWallpaper {
                wallpaperLayer(outgoing.image)
                    .opacity(settings.wallpaperOpacity)
                    .transition(.opacity)
                    .task(id: outgoing.url) {
                        // フェード完了後に背面レイヤを解放する。解放もフェードさせることで、
                        // 不透明度が1未満のときに透明度が一度跳ねるのを防ぐ。
                        do {
                            try await Task.sleep(for: .milliseconds(Int(wallpaperCrossfadeSeconds * 1000)))
                        } catch {
                            // 解放待ちの間に次の切り替えが始まった場合は何もしない。
                            return
                        }
                        withAnimation(.easeInOut(duration: wallpaperCrossfadeSeconds)) {
                            outgoingWallpaper = nil
                        }
                    }
            }
            if let url = wallpaperURL, let image = NSImage(contentsOf: url) {
                wallpaperLayer(image)
                    .opacity(settings.wallpaperOpacity)
                    .id(url)
                    .transition(.opacity)
            }
        }
        .animation(
            isWallpaperFadeSuppressed ? nil : .easeInOut(duration: wallpaperCrossfadeSeconds), value: wallpaperURL
        )
        .onChange(of: wallpaperURL) { oldURL, newURL in
            guard let oldURL, let newURL, oldURL != newURL else { return }
            let changeDate = Date.now
            defer { lastWallpaperChangeDate = changeDate }
            // フェード中の追加切替では裏面を張り替えない。
            // 裏面と進行中のフェードアウト残骸の内容が食い違い画像がガタつくため。
            // .animation 側がこの時刻でフェードを無効化し、即時切替になる。
            guard !isWallpaperFadeSuppressed else { return }
            // 「背景無し」への切り替えは新壁紙が無いため背面レイヤを張らず、
            // 旧壁紙のフェードアウトでそのまま背景色へ戻す。
            guard let outgoingImage = NSImage(contentsOf: oldURL) else { return }
            outgoingWallpaper = OutgoingWallpaper(url: oldURL, image: outgoingImage)
        }
    }

    /// 壁紙1枚のレイヤ。縦にピッタリ合わせ、アスペクト比は維持する。
    private func wallpaperLayer(_ image: NSImage) -> some View {
        GeometryReader { geometry in
            let aspect = image.size.width / max(image.size.height, 1)
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(
                    width: geometry.size.height * aspect,
                    height: geometry.size.height
                )
                .clipped()
                .position(
                    x: geometry.frame(in: .local).midX,
                    y: geometry.frame(in: .local).midY
                )
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
}

/// クロスフェード中に背面へ残しておく直前の壁紙。
private struct OutgoingWallpaper {
    let url: URL
    let image: NSImage
}

/// 実行中メニュー用のローディングアイコン。
private struct SidebarLoadingIcon: View {
    @State private var spinning = false

    var body: some View {
        Image(systemName: "arrow.triangle.2.circlepath")
            .foregroundStyle(Color.accentColor)
            .rotationEffect(.degrees(spinning ? 360 : 0))
            .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: spinning)
            .onAppear { spinning = true }
    }
}

/// 不確定の細いリニアバー。
private struct IndeterminateLinearBar: View {
    @State private var move = false

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let barWidth = max(width * 0.35, 24)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.accentColor.opacity(0.25))
                    .frame(height: 3)
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.accentColor)
                    .frame(width: barWidth, height: 3)
                    .offset(x: move ? width - barWidth : 0)
                    .animation(
                        .easeInOut(duration: 1).repeatForever(autoreverses: true),
                        value: move
                    )
                    .onAppear { move = true }
            }
        }
        .frame(height: 3)
    }
}

private extension SidebarSelection {
    func title(language: String) -> String {
        switch self {
        case .convert: return L10n.string("nav.convert", language: language)
        case .settings: return L10n.string("nav.settings", language: language)
        case .about: return L10n.string("nav.about", language: language)
        }
    }

    var systemImage: String {
        switch self {
        case .convert: return "waveform"
        case .settings: return "gearshape"
        case .about: return "info.circle"
        }
    }
}
