import AppKit
import SwiftUI

/// 音声ファイルのドラッグ＆ドロップ受け付けのAppKitラッパー。
/// `isEnabled` がfalseの間はAppKitレベルでも受け付けない。
struct AudioDropView<Content: View>: NSViewRepresentable {
    var isEnabled: Bool = true
    var onDropURLs: ([URL]) -> Void
    var onHighlightChanged: (Bool) -> Void
    @ViewBuilder var content: () -> Content

    func makeNSView(context: Context) -> AudioDropNSView {
        let view = AudioDropNSView()
        view.isEnabled = isEnabled
        view.onDropURLs = onDropURLs
        view.onHighlightChanged = onHighlightChanged
        let hosting = NSHostingView(rootView: content())
        hosting.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        return view
    }

    func updateNSView(_ nsView: AudioDropNSView, context: Context) {
        nsView.isEnabled = isEnabled
        nsView.onDropURLs = onDropURLs
        nsView.onHighlightChanged = onHighlightChanged
        if let hosting = nsView.subviews.first as? NSHostingView<Content> {
            hosting.rootView = content()
        }
    }
}

final class AudioDropNSView: NSView {
    var isEnabled: Bool = true
    var onDropURLs: ([URL]) -> Void = { _ in }
    var onHighlightChanged: (Bool) -> Void = { _ in }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard isEnabled else { return [] }
        guard let types = sender.draggingPasteboard.types, types.contains(.fileURL) else { return [] }
        onHighlightChanged(true)
        return .copy
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        onHighlightChanged(false)
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard isEnabled else { return false }
        let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? []
        onHighlightChanged(false)
        onDropURLs(urls)
        return true
    }
}
