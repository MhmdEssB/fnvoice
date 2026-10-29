import SwiftUI

struct HistoryView: View {
    @ObservedObject var historyService = HistoryService.shared

    @State private var editing: TranscriptionEntry?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text(tr("History", "Historique"))
                    .font(.headline)
                Spacer()
                if !historyService.entries.isEmpty {
                    Button(tr("Clear all", "Tout effacer")) {
                        historyService.clearAll()
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .padding()

            Divider()

            if historyService.entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(tr("No transcriptions", "Aucune transcription"))
                        .foregroundStyle(.secondary)
                    Text(tr("Transcriptions are deleted after 24 hours", "Les transcriptions s'effacent après 24h"))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(historyService.entries) { entry in
                            HistoryEntryView(
                                entry: entry,
                                onEdit: { editing = entry },
                                onDelete: { historyService.delete(entry) }
                            )
                        }
                    }
                    .padding()
                }

                Divider()

                Label(tr("Fix a dictation with the pencil: FnVoice remembers the words you correct.", "Corrige une dictée avec le crayon : FnVoice retient les mots corrigés."), systemImage: "pencil")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(10)
            }
        }
        .frame(width: 380, height: 440)
        .sheet(item: $editing) { entry in
            CorrectionSheet(entry: entry) { corrected in
                VocabularyService.shared.learnCorrection(original: entry.text, corrected: corrected)
                historyService.update(entry, text: corrected)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(corrected, forType: .string)
            }
        }
    }
}

struct HistoryEntryView: View {
    let entry: TranscriptionEntry
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(timeAgo)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if isHovering {
                    Button {
                        // Copy to the clipboard
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(entry.text, forType: .string)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(tr("Copy", "Copier"))

                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .help(tr("Correct and learn", "Corriger et apprendre"))

                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    .help(tr("Delete", "Supprimer"))
                }
            }

            Text(entry.text)
                .font(.system(size: 12))
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(Color.primary.opacity(0.05))
        .cornerRadius(8)
        .onHover { isHovering = $0 }
    }

    private var timeAgo: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: entry.date, relativeTo: Date())
    }
}

/// Correction window: the edited words are learned by the vocabulary.
struct CorrectionSheet: View {
    let entry: TranscriptionEntry
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var text: String

    init(entry: TranscriptionEntry, onSave: @escaping (String) -> Void) {
        self.entry = entry
        self.onSave = onSave
        _text = State(initialValue: entry.text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(tr("Correct the transcription", "Corriger la transcription"))
                .font(.headline)
            Text(tr("Replace the words that were misheard. FnVoice will remember them for future dictations, and the corrected text is copied.", "Remplace les mots mal compris. FnVoice les retiendra pour les prochaines dictées, et le texte corrigé sera copié."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $text)
                .font(.system(size: 13))
                .frame(height: 160)
                .padding(4)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.primary.opacity(0.15), lineWidth: 1)
                )

            HStack {
                Spacer()
                Button(tr("Cancel", "Annuler")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(tr("Save and learn", "Enregistrer et apprendre")) {
                    let corrected = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !corrected.isEmpty, corrected != entry.text {
                        onSave(corrected)
                    }
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 340)
    }
}

#Preview {
    HistoryView()
}
