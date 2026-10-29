import SwiftUI

struct VocabularyView: View {
    @ObservedObject var vocabulary = VocabularyService.shared

    private enum Tab: String, CaseIterable {
        case terms = "Termes"
        case replacements = "Corrections automatiques"
    }

    @State private var tab: Tab = .terms
    @State private var input = ""
    @State private var replaceFrom = ""
    @State private var replaceTo = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding()

            Divider()

            switch tab {
            case .terms: termsTab
            case .replacements: replacementsTab
            }
        }
        .frame(width: 420, height: 520)
    }

    // MARK: - Terms

    private var termsTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                TextField(tr("Search or add a term", "Chercher ou ajouter un terme"), text: $input)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addTerm)
                Button(tr("Add", "Ajouter"), action: addTerm)
                    .disabled(trimmedInput.count < 2 || isKnown)
            }
            .padding()

            Text(tr("FnVoice passes these terms to the model so it recognises them. The list grows by itself as you dictate.", "FnVoice transmet ces termes au modèle pour qu'il les reconnaisse. La liste s'enrichit toute seule au fil de tes dictées."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.bottom, 10)

            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filteredTerms) { term in
                        TermRow(term: term) { vocabulary.remove(term) }
                        Divider().opacity(0.4)
                    }
                }
            }

            Divider()

            Text(tr("\(vocabulary.terms.count) terms, \(vocabulary.personalTermCount) learned or added by you", "\(vocabulary.terms.count) termes, dont \(vocabulary.personalTermCount) appris ou ajoutés par toi"))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(10)
        }
    }

    private var trimmedInput: String {
        input.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isKnown: Bool {
        vocabulary.terms.contains { $0.id == trimmedInput.lowercased() }
    }

    private var filteredTerms: [VocabularyTerm] {
        let query = trimmedInput.lowercased()
        return vocabulary.terms
            .filter { query.isEmpty || $0.id.contains(query) }
            .sorted { a, b in
                let pa = a.source == .seed ? 1 : 0, pb = b.source == .seed ? 1 : 0
                if pa != pb { return pa < pb }
                return a.term.localizedCaseInsensitiveCompare(b.term) == .orderedAscending
            }
    }

    private func addTerm() {
        guard trimmedInput.count >= 2, !isKnown else { return }
        vocabulary.add(trimmedInput)
        input = ""
    }

    // MARK: - Automatic corrections

    private var replacementsTab: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                TextField(tr("Heard as", "Texte entendu"), text: $replaceFrom)
                    .textFieldStyle(.roundedBorder)
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                TextField(tr("Replace with", "Texte voulu"), text: $replaceTo)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addReplacement)
                Button(tr("Add", "Ajouter"), action: addReplacement)
                    .disabled(replaceFrom.isEmpty || replaceTo.isEmpty)
            }
            .padding()

            Text(tr("When the model writes the text on the left, FnVoice replaces it with the text on the right. Correcting a dictation in the history adds these rules for you.", "Quand le modèle écrit le texte de gauche, FnVoice le remplace par celui de droite. Corriger une dictée dans l'historique ajoute ces règles automatiquement."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
                .padding(.bottom, 10)

            Divider()

            if vocabulary.replacements.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(tr("No automatic corrections", "Aucune correction automatique"))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(vocabulary.replacements) { replacement in
                            HStack(spacing: 8) {
                                Text(replacement.from)
                                    .foregroundStyle(.secondary)
                                Image(systemName: "arrow.right")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                                Text(replacement.to)
                                Spacer()
                                Button {
                                    vocabulary.remove(replacement)
                                } label: {
                                    Image(systemName: "trash")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                                .help(tr("Delete", "Supprimer"))
                            }
                            .font(.system(size: 12))
                            .padding(.horizontal)
                            .padding(.vertical, 7)
                            Divider().opacity(0.4)
                        }
                    }
                }
            }
        }
    }

    private func addReplacement() {
        vocabulary.addReplacement(from: replaceFrom, to: replaceTo)
        replaceFrom = ""
        replaceTo = ""
    }
}

private struct TermRow: View {
    let term: VocabularyTerm
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 8) {
            Text(term.term)
                .font(.system(size: 12))
            if let badge {
                Text(badge)
                    .font(.system(size: 9, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(Capsule())
            }
            Spacer()
            if isHovering {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(tr("Delete", "Supprimer"))
            }
        }
        .padding(.horizontal)
        .frame(height: 28)
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }

    private var badge: String? {
        switch term.source {
        case .seed: return nil
        case .manual: return tr("added", "ajouté")
        case .learned: return tr("learned", "appris")
        case .correction: return tr("corrected", "corrigé")
        }
    }
}

#Preview {
    VocabularyView()
}
