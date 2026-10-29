import AppKit
import SwiftUI

/// Opens the secondary windows (history, vocabulary) and keeps them in memory.
@MainActor
final class WindowManager {
    static let shared = WindowManager()
    private init() {}

    private var windows: [String: NSWindow] = [:]

    func show<Content: View>(id: String, title: String, size: NSSize, @ViewBuilder content: () -> Content) {
        if let window = windows[id] {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: content())
        window.center()
        windows[id] = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showHistory() {
        show(id: "history", title: tr("FnVoice History", "Historique FnVoice"), size: NSSize(width: 380, height: 440)) {
            HistoryView()
        }
    }

    func showVocabulary() {
        show(id: "vocabulary", title: tr("FnVoice Vocabulary", "Vocabulaire FnVoice"), size: NSSize(width: 420, height: 520)) {
            VocabularyView()
        }
    }
}
