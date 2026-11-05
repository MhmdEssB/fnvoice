import SwiftUI

@main
struct FnVoiceApp: App {
    @StateObject private var appState = AppState()
    @ObservedObject private var meeting = MeetingRecorder.shared

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(appState)
        } label: {
            menuBarIcon
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appState)
        }
    }

    @ViewBuilder
    private var menuBarIcon: some View {
        if appState.isTranscribing {
            Image(systemName: "ellipsis.circle")
                .symbolEffect(.pulse)
        } else if appState.isRecording {
            Image(systemName: "waveform.circle.fill")
                .symbolEffect(.variableColor.iterative)
                .foregroundStyle(.red)
        } else if case .recording = meeting.phase {
            Image(systemName: "record.circle.fill")
                .symbolEffect(.pulse)
                .foregroundStyle(.red)
        } else {
            Image(systemName: "waveform.circle")
        }
    }
}
