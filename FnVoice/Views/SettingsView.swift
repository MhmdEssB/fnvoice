import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var catalog = ModelCatalog.shared
    @ObservedObject private var vocabulary = VocabularyService.shared

    @State private var apiKeyInput: String = ""
    @State private var isValidating: Bool = false
    @State private var showSuccessHint: Bool = false
    @State private var showErrorHint: Bool = false
    
    private let accentColor = Color(nsColor: .controlAccentColor)
    private let secondaryBg = Color(white: 1).opacity(0.04)
    private let borderColor = Color(white: 1).opacity(0.08)
    
    var body: some View {
        VStack(spacing: 0) {
            // MARK: - Header
            headerSection
            
            ScrollView(showsIndicators: false) {
                VStack(spacing: 20) {
                    
                    // MARK: - API Configuration Section
                    SettingsSection(title: tr("OPENROUTER KEY", "CLÉ OPENROUTER"), icon: "key.fill") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                SecureField("sk-or-...", text: $apiKeyInput)
                                    .textFieldStyle(RefinedTextFieldStyle())
                                    .frame(maxWidth: .infinity)
                                    .onSubmit(validateKey)

                                Button(action: validateKey) {
                                    HStack(spacing: 6) {
                                        if isValidating {
                                            ProgressView()
                                                .controlSize(.small)
                                                .scaleEffect(0.6)
                                        } else {
                                            Text(tr("Check", "Valider"))
                                                .font(.system(size: 11, weight: .medium))
                                        }
                                    }
                                    .frame(width: 70, height: 24)
                                }
                                .buttonStyle(RefinedButtonStyle(isPrimary: true))
                                .disabled(apiKeyInput.isEmpty || isValidating)
                            }
                            
                            HStack(spacing: 12) {
                                statusIndicator
                                
                                Spacer()
                                
                                Link(destination: URL(string: Constants.openRouterKeysPage)!) {
                                    HStack(spacing: 4) {
                                        Text(tr("Get a key", "Obtenir une clé"))
                                        Image(systemName: "arrow.up.right")
                                            .font(.system(size: 9))
                                    }
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundColor(accentColor.opacity(0.9))
                                }
                                .buttonStyle(.plain)
                                .onHover { inside in
                                    if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                                }
                            }
                        }
                    }
                    
                    // MARK: - Model Section
                    SettingsSection(title: tr("TRANSCRIPTION MODEL", "MODÈLE DE TRANSCRIPTION"), icon: "cpu") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                Picker("", selection: $settings.modelID) {
                                    ForEach(modelChoices) { model in
                                        Text(model.name).tag(model.id)
                                    }
                                }
                                .labelsHidden()
                                .frame(maxWidth: .infinity)

                                Button {
                                    Task { await catalog.refresh() }
                                } label: {
                                    if catalog.isLoading {
                                        ProgressView().controlSize(.small).scaleEffect(0.6)
                                            .frame(width: 14, height: 14)
                                    } else {
                                        Image(systemName: "arrow.clockwise")
                                            .font(.system(size: 11, weight: .medium))
                                            .frame(width: 14, height: 14)
                                    }
                                }
                                .buttonStyle(RefinedButtonStyle(isPrimary: false))
                                .disabled(catalog.isLoading)
                                .help(tr("Refresh the model list", "Mettre à jour la liste des modèles"))
                            }

                            HStack(spacing: 8) {
                                Text(selectedModel?.priceLabel ?? tr("Price unknown", "Tarif inconnu"))
                                    .font(.system(size: 10, weight: .bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.primary.opacity(0.05))
                                    .cornerRadius(4)

                                if settings.modelID == Constants.defaultModel {
                                    Text(tr("Recommended", "Recommandé"))
                                        .font(.system(size: 10, weight: .bold))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(accentColor.opacity(0.15))
                                        .foregroundColor(accentColor)
                                        .cornerRadius(4)
                                }

                                Spacer()

                                Text(tr("\(catalog.models.count) models", "\(catalog.models.count) modèles"))
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }

                            if let summary = selectedModel?.summary, !summary.isEmpty {
                                Text(summary)
                                    .font(.system(size: 11))
                                    .lineSpacing(2)
                                    .foregroundColor(.secondary)
                                    .lineLimit(3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            if catalog.loadFailed {
                                Text(tr("Model list not refreshed. Check your connection.", "Liste des modèles non mise à jour : vérifie ta connexion."))
                                    .font(.system(size: 11))
                                    .foregroundColor(.orange)
                            }

                            Divider().opacity(0.5)

                            HStack {
                                Text(tr("Spoken language", "Langue parlée"))
                                    .font(.system(size: 12))
                                Spacer()
                                Picker("", selection: $settings.language) {
                                    ForEach(AppSettings.languages, id: \.code) { language in
                                        Text(language.name).tag(language.code)
                                    }
                                }
                                .labelsHidden()
                                .frame(width: 190)
                            }

                            Toggle(isOn: $settings.strictPrivacy) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tr("Strict privacy", "Confidentialité stricte"))
                                        .font(.system(size: 12))
                                    Text(tr("Only uses providers that do not retain data. Some models may then refuse the request.", "N'utilise que des fournisseurs qui ne conservent pas les données. Certains modèles peuvent alors refuser la demande."))
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        }
                    }

                    // MARK: - Vocabulary Section
                    SettingsSection(title: tr("VOCABULARY", "VOCABULAIRE"), icon: "character.book.closed") {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tr("\(vocabulary.terms.count) known terms", "\(vocabulary.terms.count) termes connus"))
                                        .font(.system(size: 12, weight: .semibold))
                                    Text(tr("\(vocabulary.personalTermCount) learned or added by you, \(vocabulary.replacements.count) automatic corrections", "\(vocabulary.personalTermCount) appris ou ajoutés par toi, \(vocabulary.replacements.count) corrections automatiques"))
                                        .font(.system(size: 11))
                                        .foregroundColor(.secondary)
                                }
                                Spacer()
                                Button(tr("Manage...", "Gérer...")) {
                                    WindowManager.shared.showVocabulary()
                                }
                                .buttonStyle(RefinedButtonStyle(isPrimary: false))
                            }

                            Toggle(isOn: $settings.autoLearn) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(tr("Learn my terms automatically", "Apprendre mes termes automatiquement"))
                                        .font(.system(size: 12))
                                    Text(tr("An acronym or technical word dictated twice is added to the vocabulary.", "Un acronym ou un mot technique dicté deux fois est ajouté au vocabulaire."))
                                        .font(.system(size: 10))
                                        .foregroundColor(.secondary)
                                }
                            }
                            .toggleStyle(.switch)
                            .controlSize(.small)
                        }
                    }

                    // MARK: - Usage Section
                    SettingsSection(title: tr("USAGE", "UTILISATION"), icon: "command") {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack(spacing: 16) {
                                ShortcutKeyView(label: "Fn", subLabel: "Maintenir")

                                Text(tr("Hold the Fn key and speak. Release to transcribe and paste the text.", "Maintenez la touche Fn enfoncée pour parler. Relâchez pour transcrire et coller le texte."))
                                    .font(.system(size: 12))
                                    .lineSpacing(3)
                                    .foregroundColor(.secondary)
                            }
                            
                            Divider().opacity(0.5)
                            
                            HStack(spacing: 12) {
                                Image(systemName: "text.cursor")
                                    .font(.system(size: 14))
                                    .foregroundColor(accentColor)
                                    .frame(width: 24)
                                
                                Text(tr("The text is pasted automatically at your cursor.", "Le texte transcrit sera inséré automatiquement à l'emplacement actuel de votre curseur."))
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    // MARK: - About Section
                    SettingsSection(title: tr("ABOUT", "À PROPOS"), icon: "info.circle") {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("FnVoice for macOS")
                                    .font(.system(size: 12, weight: .semibold))
                                Text(tr("Version \(Constants.appVersion), transcription through OpenRouter", "Version \(Constants.appVersion), transcription via OpenRouter"))
                                    .font(.system(size: 11))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button(tr("History", "Historique")) {
                                WindowManager.shared.showHistory()
                            }
                            .buttonStyle(RefinedButtonStyle(isPrimary: false))
                        }
                    }
                }
                .padding(24)
            }
            
            // MARK: - Footer
            footerSection
        }
        .frame(width: 440, height: 700)
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    // MARK: - Subviews
    
    private var headerSection: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text("FnVoice")
                        .font(.system(size: 16, weight: .bold))
                        .kerning(-0.2)
                    Text(tr("Voice dictation, version \(Constants.appVersion)", "Dictée vocale, version \(Constants.appVersion)"))
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            
            Divider().opacity(0.5)
        }
    }
    
    private var statusIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(appState.hasAPIKey ? Color.green : Color.orange)
                .frame(width: 6, height: 6)
                .shadow(color: (appState.hasAPIKey ? Color.green : Color.orange).opacity(0.4), radius: 3)
            
            Text(statusLabel)
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(showErrorHint ? .orange : .secondary)
            
            if appState.hasAPIKey {
                Button(action: { appState.clearAPIKey() }) {
                    Text(tr("Reset", "Réinitialiser"))
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary)
                        .underline()
                }
                .buttonStyle(.plain)
                .padding(.leading, 4)
            }
        }
    }
    
    private var footerSection: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.5)
            HStack {
                Text(tr("FnVoice transcribes with the model of your choice through OpenRouter.", "FnVoice transcrit avec le modèle de ton choix via OpenRouter."))
                    .font(.system(size: 10))
                    .foregroundColor(.secondary.opacity(0.7))
                
                Spacer()
                
                Button(tr("Quit", "Quitter")) {
                    NSApplication.shared.terminate(nil)
                }
                .buttonStyle(RefinedButtonStyle(isPrimary: false))
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.8))
    }
    
    // MARK: - Logic

    private var statusLabel: String {
        if showErrorHint { return tr("Key rejected by OpenRouter", "Clé refusée par OpenRouter") }
        if showSuccessHint { return tr("Key saved", "Clé enregistrée") }
        return appState.hasAPIKey ? tr("Key valid", "Clé valide") : tr("Key not set", "Clé non configurée")
    }

    private var selectedModel: TranscriptionModel? {
        catalog.model(for: settings.modelID)
    }

    /// OpenRouter's list, plus the chosen model if it is no longer in it.
    private var modelChoices: [TranscriptionModel] {
        if selectedModel != nil { return catalog.models }
        let current = TranscriptionModel(id: settings.modelID, name: settings.modelID, summary: "", pricePerHour: nil)
        return [current] + catalog.models
    }

    private func validateKey() {
        guard !apiKeyInput.isEmpty else { return }
        
        isValidating = true
        showErrorHint = false
        
        Task {
            let success = await appState.updateAPIKey(apiKeyInput)
            await MainActor.run {
                isValidating = false
                if success {
                    apiKeyInput = ""
                    showSuccessHint = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { showSuccessHint = false }
                } else {
                    showErrorHint = true
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct SettingsSection<Content: View>: View {
    let title: String
    let icon: String
    let content: Content
    
    init(title: String, icon: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.icon = icon
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.secondary)
                    .kerning(0.5)
            }
            
            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.4))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
            )
        }
    }
}

struct ShortcutKeyView: View {
    let label: String
    let subLabel: String
    
    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(0.07))
                    .frame(width: 36, height: 36)
                
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color.primary.opacity(0.15), lineWidth: 0.5)
                    .frame(width: 36, height: 36)
                
                Text(label)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            
            Text(subLabel)
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.secondary.opacity(0.8))
                .textCase(.uppercase)
        }
    }
}

// MARK: - Styles

struct RefinedTextFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .textFieldStyle(.plain)
            .background(Color.primary.opacity(0.06))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(0.12), lineWidth: 1)
            )
            .font(.system(size: 12, design: .monospaced))
    }
}

struct RefinedButtonStyle: ButtonStyle {
    let isPrimary: Bool
    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                ZStack {
                    if isPrimary {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(LinearGradient(colors: [Color.accentColor, Color.accentColor.opacity(0.8)], startPoint: .top, endPoint: .bottom))
                    } else {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(Color.primary.opacity(isHovering ? 0.08 : 0.04))
                    }
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(isPrimary ? Color.white.opacity(0.1) : Color.primary.opacity(0.1), lineWidth: 0.5)
            )
            .foregroundColor(isPrimary ? .white : .primary)
            .opacity(isEnabled ? 1 : 0.45)
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: configuration.isPressed)
            .onHover { inside in
                isHovering = inside
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}