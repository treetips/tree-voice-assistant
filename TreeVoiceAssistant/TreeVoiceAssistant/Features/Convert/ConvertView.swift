import AppKit
import SwiftUI

/// 音声変換画面。
/// 実行状態は共有の `ConvertJobStore` を参照するため、サイドナビ切替で
/// Viewが再生成されても進捗・結果が維持される。
struct ConvertView: View {
    @State private var viewModel: ConvertViewModel
    private let jobStore: ConvertJobStore
    @State private var isDropTargeted = false
    @Environment(\.locale) private var locale

    init(jobStore: ConvertJobStore) {
        self.jobStore = jobStore
        _viewModel = State(initialValue: ConvertViewModel(jobStore: jobStore))
    }

    private var lang: String { locale.language.languageCode?.identifier ?? "" }
    private func t(_ key: String) -> String { L10n.string(key, language: lang) }

    private func selectAudioFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.audio]
        if panel.runModal() == .OK {
            viewModel.acceptAudioURLs(panel.urls)
        }
    }

    private func selectOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            viewModel.outputFolderPath = url.path
        }
    }

    /// 直近の変換結果に応じたエリアの枠色。成功=緑、失敗=赤、未実行=グレー。
    private var dropBorderColor: Color {
        if isDropTargeted { return .accentColor }
        switch jobStore.lastRunSucceeded {
        case true: return .green
        case false: return .red
        case nil: return .secondary.opacity(0.4)
        }
    }

    /// 入力エリアの有効条件。実行中は受け付けない。
    private var inputEnabled: Bool {
        !jobStore.isRunning
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Color.clear
                    .frame(height: 1)
                GroupBox {
                    AudioDropView(
                        isEnabled: inputEnabled,
                        onDropURLs: { viewModel.acceptAudioURLs($0) },
                        onHighlightChanged: { isDropTargeted = $0 }
                    ) {
                        VStack(spacing: 8) {
                            if !viewModel.audioFileName.isEmpty {
                                Text(viewModel.audioFileName)
                                    .appFont(.body)
                            } else {
                                Text(t("v.dropHint"))
                                    .appFont(.body)
                                    .multilineTextAlignment(.center)
                                    .foregroundStyle(.secondary)
                            }
                            if !jobStore.resultMessage.isEmpty {
                                Text(jobStore.resultMessage)
                                    .appFont(.body)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 80)
                        .padding(.vertical, 4)
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                dropBorderColor,
                                lineWidth: isDropTargeted || jobStore.lastRunSucceeded != nil ? 2 : 1
                            )
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if inputEnabled {
                            selectAudioFile()
                        }
                    }
                    .onHover { hovering in
                        if hovering {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    .disabled(!inputEnabled)
                } label: {
                    Text(t("v.group.input")).appFont(.headline)
                }

                TranscriptionSection(viewModel: viewModel, jobStore: jobStore, text: t)

                GroupBox {
                    HStack {
                        Text(t("v.label.outputFolder")).appFont(.headline)
                        Button {
                            selectOutputFolder()
                        } label: {
                            Text(t("v.folderButton")).appFont(.body)
                        }
                        TextField(t("v.label.outputFolder"), text: $viewModel.outputFolderPath)
                            .appFont(.body)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(
                                        viewModel.outputFolderHasError ? Color.red : Color.clear,
                                        lineWidth: 2
                                    )
                            )
                        HelpPopover(text: t("v.help.outputFolder"))
                    }
                    .padding(.vertical, 4)
                } label: {
                    Text(t("v.group.output")).appFont(.headline)
                }

                TtsSection(viewModel: viewModel, jobStore: jobStore, text: t)
            }
            .padding(.horizontal)
            .padding(.bottom, 0)
        }
        .navigationTitle(t("nav.convert"))
    }
}

/// 実行ボタンと取り消しボタンの並び。実行中のみ取り消しを受け付ける。
private struct RunCancelButtons: View {
    var runTitle: String
    var runDisabled: Bool
    var runAction: () -> Void
    var cancelTitle: String
    var cancelDisabled: Bool
    var cancelAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            GlassCTAButton(title: runTitle, disabled: runDisabled, action: runAction)
            GlassCTAButton(title: cancelTitle, disabled: cancelDisabled, action: cancelAction)
        }
    }
}

/// 文字起こしの区分。モデル選択・実行・結果表示を持つ。
private struct TranscriptionSection: View {
    @Bindable var viewModel: ConvertViewModel
    var jobStore: ConvertJobStore
    var text: (String) -> String

    var body: some View {
        GroupBox {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text(text("v.label.model")).appFont(.headline)
                    HStack {
                        Picker(text("v.label.model"), selection: $viewModel.whisperModel) {
                            ForEach(WhisperModel.allCases) { model in
                                Text(model.rawValue).appFont(.body).tag(model.rawValue)
                            }
                        }
                        .labelsHidden()
                        Spacer()
                        HelpPopover(text: text("v.help.model"))
                    }
                }
                GridRow {
                    RunCancelButtons(
                        runTitle: jobStore.isTranscribing
                            ? text("v.transcribing") : text("v.label.transcribeRun"),
                        runDisabled: !viewModel.canRunTranscription,
                        runAction: { viewModel.runTranscription() },
                        cancelTitle: text("a.cancel"),
                        cancelDisabled: !jobStore.isTranscribing,
                        cancelAction: { viewModel.cancelTranscription() }
                    )
                    .gridCellColumns(2)
                }
                GridRow {
                    TextEditor(text: $viewModel.transcriptionText)
                        .appFont(.body)
                        .frame(minHeight: 100)
                        .overlay(
                            Group {
                                if viewModel.transcriptionText.isEmpty {
                                    Text(text("v.transcriptionPlaceholder"))
                                        .appFont(.body)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 8)
                                        .allowsHitTesting(false)
                                }
                            },
                            alignment: .topLeading
                        )
                        .gridCellColumns(2)
                }
            }
            .padding(.vertical, 4)
        } label: {
            HStack {
                Text(text("v.group.transcription")).appFont(.headline)
                HelpPopover(text: text("v.help.transcriptionTips"))
            }
        }
    }
}

/// 音声合成の区分。モデル選択・文章入力・実行・再生を持つ。
private struct TtsSection: View {
    @Bindable var viewModel: ConvertViewModel
    var jobStore: ConvertJobStore
    var text: (String) -> String

    var body: some View {
        GroupBox {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 8) {
                GridRow {
                    Text(text("v.label.model")).appFont(.headline)
                    HStack {
                        Picker(text("v.label.model"), selection: $viewModel.ttsModel) {
                            ForEach(TTSModel.allCases) { model in
                                Text(model.rawValue).appFont(.body).tag(model.rawValue)
                            }
                        }
                        .labelsHidden()
                        Spacer()
                        HelpPopover(text: text("v.help.ttsModel"))
                    }
                }
                GridRow {
                    TextEditor(text: $viewModel.speechText)
                        .appFont(.body)
                        .frame(minHeight: 100)
                        .disabled(jobStore.isSynthesizing)
                        .overlay(
                            Group {
                                if viewModel.speechText.isEmpty {
                                    Text(text("v.speechPlaceholder"))
                                        .appFont(.body)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 8)
                                        .allowsHitTesting(false)
                                }
                            },
                            alignment: .topLeading
                        )
                        .gridCellColumns(2)
                }
                GridRow {
                    HStack(spacing: 12) {
                        GlassCTAButton(
                            title: jobStore.isSynthesizing
                                ? text("v.synthesizing") : text("v.label.ttsRun"),
                            disabled: !viewModel.canRunSynthesis
                        ) {
                            viewModel.runSynthesis()
                        }
                        GlassCTAButton(
                            title: jobStore.isPlaying
                                ? text("v.playing") : text("v.label.play"),
                            disabled: !viewModel.canPlay
                        ) {
                            viewModel.playOutput()
                        }
                        GlassCTAButton(
                            title: text("a.cancel"),
                            disabled: !jobStore.isSynthesizing
                        ) {
                            viewModel.cancelSynthesis()
                        }
                    }
                    .gridCellColumns(2)
                }
            }
            .padding(.vertical, 4)
        } label: {
            Text(text("v.group.tts")).appFont(.headline)
        }
    }
}
