import AppKit
import Foundation

final class KeyboardService: ObservableObject {
    @Published private(set) var isMonitoring = false

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var fnIsPressed = false

    /// Called when Fn is pressed (recording starts)
    var onFnPressed: (() -> Void)?
    /// Called when Fn is released (recording ends)
    var onFnReleased: (() -> Void)?

    func startMonitoring() {
        guard !isMonitoring else { return }

        // Global monitor (when the app is not in the foreground)
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
        }

        // Local monitor (when the app is in the foreground)
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handleFlagsChanged(event)
            return event
        }

        isMonitoring = true
    }

    func stopMonitoring() {
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
            globalMonitor = nil
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
        isMonitoring = false
    }

    private func handleFlagsChanged(_ event: NSEvent) {
        let fnKeyPressed = event.modifierFlags.contains(.function)

        // Fn has just been pressed
        if fnKeyPressed && !fnIsPressed {
            fnIsPressed = true
            DispatchQueue.main.async { [weak self] in
                self?.onFnPressed?()
            }
        }
        // Fn has just been released
        else if !fnKeyPressed && fnIsPressed {
            fnIsPressed = false
            DispatchQueue.main.async { [weak self] in
                self?.onFnReleased?()
            }
        }
    }

    deinit {
        stopMonitoring()
    }
}
