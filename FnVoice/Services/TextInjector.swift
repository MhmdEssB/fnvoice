import AppKit
import Carbon.HIToolbox

final class TextInjector {
    static let shared = TextInjector()
    private init() {}

    /// The app that had focus when the recording started
    private var targetApp: NSRunningApplication?

    /// Captures the current frontmost app (call at the start of recording)
    func captureTargetApp() {
        targetApp = NSWorkspace.shared.frontmostApplication
    }

    /// Pastes the text at the cursor position.
    /// Without the Accessibility permission, the text stays on the clipboard and the function returns false.
    @discardableResult
    func inject(text: String) -> Bool {
        guard Self.hasAccessibilityPermission() else {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            targetApp = nil
            Self.requestAccessibilityPermission()
            return false
        }

        // Save the current clipboard content
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)

        // Put the transcribed text on the clipboard
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Make sure the target app has focus
        if let app = targetApp {
            app.activate(options: [.activateIgnoringOtherApps])
        }

        // Delay to make sure the app is really active
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            self.pasteViaCGEvent()

            // Restore the clipboard after a delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                if let previous = previousContents {
                    pasteboard.clearContents()
                    pasteboard.setString(previous, forType: .string)
                }
                self.targetApp = nil
            }
        }
        return true
    }

    private func pasteViaCGEvent() {
        // CGEvent does not work well on recent macOS, use AppleScript
        pasteViaAppleScript()
    }

    private func pasteViaAppleScript() {
        let script = """
        tell application "System Events"
            keystroke "v" using command down
        end tell
        """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
        }

        if error != nil {
            // Fallback: direct key strokes (does not depend on the Automation permission)
            pasteViaKeyEvents()
        }
    }

    private func pasteViaKeyEvents() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyV = CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: keyV, keyDown: false) else {
            pasteViaMenuClick()
            return
        }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func pasteViaMenuClick() {
        guard let appName = targetApp?.localizedName else { return }

        let script = """
        tell application "\(appName)"
            activate
        end tell
        delay 0.1
        tell application "System Events"
            tell process "\(appName)"
                click menu item "Paste" of menu "Edit" of menu bar 1
            end tell
        end tell
        """

        var error: NSDictionary?
        if let appleScript = NSAppleScript(source: script) {
            appleScript.executeAndReturnError(&error)
        }
    }

    /// Checks whether the app has the accessibility permissions
    static func hasAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: false]
        return AXIsProcessTrustedWithOptions(options as CFDictionary)
    }

    /// Opens the macOS Accessibility settings
    static func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Asks for the accessibility permissions
    static func requestAccessibilityPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true]
        _ = AXIsProcessTrustedWithOptions(options as CFDictionary)
    }
}
