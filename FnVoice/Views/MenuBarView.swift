import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openSettings) private var openSettings
    @ObservedObject private var history = HistoryService.shared
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var catalog = ModelCatalog.shared
    @ObservedObject private var meeting = MeetingRecorder.shared

    @State private var copiedEntry: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if let warning {
                warningCard(warning)
            }

            meetingSection

            if !history.entries.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    sectionTitle(tr("LATEST DICTATIONS", "DERNIÈRES DICTÉES"))
                    ForEach(history.entries.prefix(3)) { entry in
                        MenuRow(
                            icon: copiedEntry == entry.id ? "checkmark" : "doc.on.doc",
                            title: copiedEntry == entry.id ? tr("Copied", "Copié") : entry.text,
                            isSecondary: true
                        ) {
                            copy(entry)
                        }
                        .help(tr("Copy this dictation", "Copier cette dictée"))
                    }
                }
            }

            Divider().padding(.horizontal, 12)

            VStack(alignment: .leading, spacing: 2) {
                MenuRow(icon: "clock.arrow.circlepath", title: tr("History", "Historique")) {
                    WindowManager.shared.showHistory()
                }
                MenuRow(icon: "character.book.closed", title: tr("Vocabulary", "Vocabulaire")) {
                    WindowManager.shared.showVocabulary()
                }
                MenuRow(icon: "gearshape", title: tr("Settings", "Préférences"), shortcut: "⌘,") {
                    openSettings()
                    NSApp.activate(ignoringOtherApps: true)
                }
                .keyboardShortcut(",", modifiers: .command)
                MenuRow(icon: "power", title: tr("Quit FnVoice", "Quitter FnVoice"), shortcut: "⌘Q") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        }
        .padding(.vertical, 10)
        .frame(width: 280)
        .onAppear {
            appState.needsAccessibility = !TextInjector.hasAccessibilityPermission()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            headerTitle
            headerInfo
        }
    }

    private var headerTitle: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text("FnVoice")
                    .font(.system(size: 14, weight: .semibold))
                HStack(spacing: 5) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 7, height: 7)
                    Text(statusText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(.horizontal, 14)
    }

    private var headerInfo: some View {
        VStack(alignment: .leading, spacing: 5) {
            infoLine(icon: "keyboard", text: tr("Hold Fn to talk", "Maintiens Fn pour parler"))
            infoLine(icon: "cpu", text: modelName)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 12)
    }

    private func infoLine(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .frame(width: 16)
            Text(text)
                .font(.system(size: 11))
                .lineLimit(1)
        }
        .foregroundStyle(.secondary)
    }

    private func sectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 9, weight: .bold))
            .kerning(0.5)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 14)
            .padding(.bottom, 2)
    }

    // MARK: - Warning

    private var warning: String? {
        if let error = appState.lastError { return error }
        if appState.needsAccessibility { return tr("macOS is blocking automatic pasting.", "Collage automatique non autorisé par macOS.") }
        return nil
    }

    private func warningCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .frame(width: 16)
                Text(message)
                    .font(.system(size: 11))
                    .fixedSize(horizontal: false, vertical: true)
            }

            if appState.needsAccessibility {
                Button(tr("Allow automatic pasting", "Autoriser le collage automatique")) {
                    TextInjector.openAccessibilitySettings()
                }
                .controlSize(.small)
                .padding(.leading, 24)
            }

            if appState.canRetry {
                Button(tr("Retry the last dictation", "Réessayer la dernière dictée")) {
                    appState.retryLastRecording()
                }
                .controlSize(.small)
                .padding(.leading, 24)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 12)
    }

    // MARK: - Meeting

    @ViewBuilder
    private var meetingSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            sectionTitle(tr("MEETING", "RÉUNION"))

            switch meeting.phase {
            case .idle:
                MenuRow(icon: "record.circle", title: tr("Record a meeting", "Enregistrer une réunion")) {
                    meeting.start()
                }
                MenuRow(icon: "folder", title: tr("Meetings folder", "Dossier des réunions"), isSecondary: true) {
                    meeting.openFolder()
                }

            case .recording(let start):
                recordingCard(since: start)

            case .processing(let done, let total, let step):
                processingCard(done: done, total: total, step: step)

            case .finished(let url):
                finishedCard(url: url)

            case .failed(let message):
                failedCard(message: message)
            }
        }
    }

    private func meetingCard<Content: View>(tint: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            content()

            if let warning = meeting.warning {
                Text(warning)
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .padding(.horizontal, 12)
    }

    private func recordingCard(since start: Date) -> some View {
        meetingCard(tint: .red) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                HStack(spacing: 8) {
                    Circle()
                        .fill(.red)
                        .frame(width: 8, height: 8)
                    Text(tr("Meeting in progress", "Réunion en cours"))
                        .font(.system(size: 12, weight: .semibold))
                    Spacer()
                    Text(elapsedText(since: start, now: context.date))
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }

            Text(meeting.capturesSystemAudio
                 ? tr("Microphone + computer sound", "Micro + son de l'ordinateur")
                 : tr("Microphone only", "Micro seulement"))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            Button(tr("Stop and transcribe", "Arrêter et transcrire")) {
                meeting.stop()
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.small)
        }
    }

    private func processingCard(done: Int, total: Int, step: String) -> some View {
        meetingCard(tint: .blue) {
            Text("\(step)… \(done)/\(total)")
                .font(.system(size: 12, weight: .semibold))
                .monospacedDigit()

            ProgressView(value: Double(done), total: Double(max(total, 1)))

            Text(tr("You can keep dictating meanwhile.", "Tu peux continuer à dicter pendant ce temps."))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
    }

    private func finishedCard(url: URL) -> some View {
        meetingCard(tint: .green) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text(tr("Transcript ready", "Transcription prête"))
                    .font(.system(size: 12, weight: .semibold))
            }

            HStack(spacing: 8) {
                Button(tr("Open", "Ouvrir")) {
                    meeting.openTranscript(url)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .controlSize(.small)

                Button(tr("OK", "OK")) {
                    meeting.dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }

    private func failedCard(message: String) -> some View {
        meetingCard(tint: .orange) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .frame(width: 16)
                Text(message)
                    .font(.system(size: 11))
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                if meeting.canRetry {
                    Button(tr("Retry", "Réessayer")) {
                        meeting.retry()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .controlSize(.small)
                }

                Button(meeting.canRetry ? tr("Later", "Plus tard") : tr("Close", "Fermer")) {
                    meeting.dismiss()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                if meeting.canRetry {
                    Button(tr("Delete", "Supprimer")) {
                        meeting.discardPending()
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .controlSize(.small)
                    .help(tr("Permanently delete this recording", "Supprimer définitivement cet enregistrement"))
                }
            }
        }
    }

    private func elapsedText(since start: Date, now: Date) -> String {
        let total = max(0, Int(now.timeIntervalSince(start)))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }

    // MARK: - Actions

    private func copy(_ entry: TranscriptionEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
        copiedEntry = entry.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            if copiedEntry == entry.id { copiedEntry = nil }
        }
    }

    private var modelName: String {
        catalog.model(for: settings.modelID)?.name ?? settings.modelID
    }

    private var statusColor: Color {
        if appState.isTranscribing {
            return .blue
        } else if appState.isRecording {
            return .red
        } else if case .recording = meeting.phase {
            return .red
        } else if !appState.hasAPIKey {
            return .orange
        } else {
            return .green
        }
    }

    private var statusText: String {
        if appState.isTranscribing {
            return tr("Transcribing...", "Transcription en cours...")
        } else if appState.isRecording {
            return tr("Recording...", "Enregistrement...")
        } else if case .recording = meeting.phase {
            return tr("Meeting being recorded", "Réunion en cours d'enregistrement")
        } else if !appState.hasAPIKey {
            return tr("OpenRouter key not set", "Clé OpenRouter non configurée")
        } else {
            return tr("Ready", "Prêt")
        }
    }
}

/// Clickable menu row, highlighted on hover.
private struct MenuRow: View {
    let icon: String
    let title: String
    var shortcut: String?
    var isSecondary = false
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: isSecondary ? 11 : 13))
                    .frame(width: 18)
                    .foregroundStyle(isSecondary ? .secondary : .primary)
                Text(title)
                    .font(.system(size: isSecondary ? 12 : 13))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 8)
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: isSecondary ? 24 : 28)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(isHovering ? 0.08 : 0))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .onHover { isHovering = $0 }
    }
}

#Preview {
    MenuBarView()
        .environmentObject(AppState())
}
