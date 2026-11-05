import AppKit
import Foundation

/// Domain of a term: the review only applies the terms of the subject the user is talking about.
enum VocabularyDomain: String, CaseIterable {
    case science, tech, business, law, brands, people, places, other

    /// Label shown to the review model.
    var label: String {
        switch self {
        case .science: return tr("Science, medicine and research", "Science, médecine et recherche")
        case .tech: return tr("Software, IT and technology", "Logiciel, informatique et technologie")
        case .business: return tr("Business, finance and economics", "Affaires, finance et économie")
        case .law: return tr("Law, politics and public institutions", "Droit, politique et institutions publiques")
        case .brands: return tr("Companies, brands and products", "Entreprises, marques et produits")
        case .people: return tr("People's names", "Noms de personnes")
        case .places: return tr("Places", "Lieux")
        case .other: return tr("Other", "Autres")
        }
    }
}

/// Tolerant reading: an unknown value (old label, future version) gives "unclassified"
/// instead of making the whole vocabulary file unreadable.
extension VocabularyDomain: Codable {
    init(from decoder: Decoder) throws {
        let value = try decoder.singleValueContainer().decode(String.self)
        guard let domain = VocabularyDomain(rawValue: value) ?? VocabularyDomain.allCases.first(where: { $0.label == value }) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: value))
        }
        self = domain
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

struct VocabularyTerm: Codable, Identifiable, Hashable {
    enum Source: String, Codable {
        case seed       // starting list
        case manual     // added by hand
        case learned    // spotted automatically in dictations
        case correction // from a user correction
    }

    var term: String
    var count: Int
    var source: Source
    /// Filled by the automatic classification (nil = not classified yet).
    var domain: VocabularyDomain?

    var id: String { term.lowercased() }

    init(term: String, count: Int, source: Source, domain: VocabularyDomain? = nil) {
        self.term = term
        self.count = count
        self.source = source
        self.domain = domain
    }

    private enum CodingKeys: String, CodingKey { case term, count, source, domain }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        term = try c.decode(String.self, forKey: .term)
        count = try c.decode(Int.self, forKey: .count)
        source = try c.decode(Source.self, forKey: .source)
        domain = try? c.decodeIfPresent(VocabularyDomain.self, forKey: .domain)
    }
}

/// Replacement applied automatically after every transcription.
struct VocabularyReplacement: Codable, Identifiable, Hashable {
    var id = UUID()
    var from: String
    var to: String
}

/// Personal vocabulary: the terms are sent to the model so it recognises them,
/// and the list grows with dictations and corrections.
final class VocabularyService: ObservableObject {
    static let shared = VocabularyService()

    @Published private(set) var terms: [VocabularyTerm] = []
    @Published private(set) var replacements: [VocabularyReplacement] = []

    /// Unknown words already seen, waiting to be seen a second time.
    private var candidates: [String: Int] = [:]
    /// Words never to learn (deleted or corrected by the user).
    private var blocked: Set<String> = []
    private var seedVersion = 0

    private let fileURL: URL
    private let promotionThreshold = 2

    private struct Store: Codable {
        var terms: [VocabularyTerm]
        var replacements: [VocabularyReplacement]
        var candidates: [String: Int]
        var blocked: [String]
        var seedVersion: Int
    }

    private init() {
        fileURL = AppFolder.url.appendingPathComponent("vocabulary.json")
        load()
        installSeedIfNeeded()
    }

    // MARK: - Reading

    /// Terms to send to the model: the user's first, then the most frequent.
    func keyterms(limit: Int) -> [String] {
        guard limit > 0 else { return [] }
        let sorted = terms.sorted { a, b in
            let pa = Self.priority(a.source), pb = Self.priority(b.source)
            if pa != pb { return pa < pb }
            if a.count != b.count { return a.count > b.count }
            return a.term.localizedCaseInsensitiveCompare(b.term) == .orderedAscending
        }
        return Array(sorted.prefix(limit).map(\.term))
    }

    private static func priority(_ source: VocabularyTerm.Source) -> Int {
        switch source {
        case .manual, .correction: return 0
        case .learned: return 1
        case .seed: return 2
        }
    }

    var personalTermCount: Int {
        terms.filter { $0.source != .seed }.count
    }

    // MARK: - Manual edits

    func add(_ raw: String, source: VocabularyTerm.Source = .manual) {
        let term = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard term.count >= 2 else { return }
        let key = term.lowercased()
        blocked.remove(key)
        candidates[key] = nil
        if let index = terms.firstIndex(where: { $0.id == key }) {
            // A term confirmed by the user gets priority
            if source != .learned, terms[index].source == .seed || terms[index].source == .learned {
                terms[index].source = source
            }
            terms[index].term = term
        } else {
            terms.append(VocabularyTerm(term: term, count: 0, source: source))
        }
        save()
        Task { @MainActor in await self.classifyPendingTerms() }
    }

    func remove(_ term: VocabularyTerm) {
        terms.removeAll { $0.id == term.id }
        candidates[term.id] = nil
        blocked.insert(term.id)
        save()
    }

    func addReplacement(from: String, to: String) {
        let from = from.trimmingCharacters(in: .whitespacesAndNewlines)
        let to = to.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !from.isEmpty, !to.isEmpty, from.lowercased() != to.lowercased() else { return }
        replacements.removeAll { $0.from.lowercased() == from.lowercased() }
        replacements.append(VocabularyReplacement(from: from, to: to))
        save()
    }

    func remove(_ replacement: VocabularyReplacement) {
        replacements.removeAll { $0.id == replacement.id }
        save()
    }

    // MARK: - Automatic corrections

    /// Applies the learned replacements ("N-A-S-A" → "NASA") on whole words.
    func applyReplacements(to text: String) -> String {
        var result = text
        for replacement in replacements {
            let pattern = "(?<![\\p{L}\\p{N}])" + NSRegularExpression.escapedPattern(for: replacement.from) + "(?![\\p{L}\\p{N}])"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: NSRegularExpression.escapedTemplate(for: replacement.to)
            )
        }
        return result
    }

    // MARK: - Learning as you dictate

    /// Spots the technical terms in a transcription. An unknown word seen twice is kept.
    func learn(from text: String) {
        var changed = false
        for word in Self.words(in: text) {
            let key = word.lowercased()
            if let index = terms.firstIndex(where: { $0.id == key }) {
                terms[index].count += 1
                changed = true
                continue
            }
            guard !blocked.contains(key), Self.looksTechnical(word) else { continue }
            let seen = (candidates[key] ?? 0) + 1
            if seen >= promotionThreshold {
                candidates[key] = nil
                terms.append(VocabularyTerm(term: word, count: seen, source: .learned))
            } else {
                candidates[key] = seen
            }
            changed = true
        }
        if changed {
            save()
            Task { @MainActor in await self.classifyPendingTerms() }
        }
    }

    /// Learns from a correction the user made in the history:
    /// the corrected words become known terms, and the mistake is replaced in future.
    func learnCorrection(original: String, corrected: String) {
        let old = Self.tokens(in: original)
        let new = Self.tokens(in: corrected)
        guard !old.isEmpty, !new.isEmpty else { return }

        let diff = new.map { $0.lowercased() }.difference(from: old.map { $0.lowercased() })
        var removed = Set<Int>(), inserted = Set<Int>()
        for change in diff {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }

        var i = 0, j = 0
        while i < old.count || j < new.count {
            guard removed.contains(i) || inserted.contains(j) else {
                i += 1
                j += 1
                continue
            }
            var before: [String] = [], after: [String] = []
            while removed.contains(i) || inserted.contains(j) {
                if removed.contains(i) {
                    before.append(old[i])
                    i += 1
                } else {
                    after.append(new[j])
                    j += 1
                }
            }
            learnHunk(before: before, after: after)
        }
        save()
    }

    private func learnHunk(before: [String], after: [String]) {
        // A corrected word counts if it is technical or already in the vocabulary
        let technical = after.map(Self.withoutElision).filter { word in
            Self.looksTechnical(word) || terms.contains { $0.id == word.lowercased() }
        }
        guard !technical.isEmpty else { return } // simple rewording: nothing to learn

        // The old spelling must never be learned as a term again
        for word in before where !after.contains(where: { $0.lowercased() == word.lowercased() }) {
            let key = word.lowercased()
            guard Self.looksTechnical(word) else { continue }
            terms.removeAll { $0.id == key && $0.source == .learned }
            candidates[key] = nil
            blocked.insert(key)
        }

        for word in technical {
            add(word, source: .correction)
        }

        // Automatic replacement, only if the mistake is not a common standalone word
        let safeToReplace = before.count >= 2
            || (before.count == 1 && (Self.isSpelledOut(before[0]) || Self.looksTechnical(before[0])))
        if safeToReplace, before.count <= 6, after.count <= 4 {
            addReplacement(from: before.joined(separator: " "), to: after.joined(separator: " "))
        }
    }

    // MARK: - Word analysis

    /// Words split on spaces, without the punctuation around them.
    private static func tokens(in text: String) -> [String] {
        let edge = CharacterSet.punctuationCharacters.union(.symbols)
        return text
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: edge) }
            .filter { !$0.isEmpty }
    }

    /// Like `tokens`, removing the elided article ("l'NASA" → "NASA").
    private static func words(in text: String) -> [String] {
        tokens(in: text).map(withoutElision)
    }

    private static func withoutElision(_ token: String) -> String {
        let parts = token.split(whereSeparator: { $0 == "'" || $0 == "’" })
        if parts.count == 2, parts[0].count <= 5 { return String(parts[1]) }
        return token
    }

    private static let spelledOut = try! NSRegularExpression(pattern: "^(\\p{L}[-.])+\\p{L}\\.?$")

    /// True for an acronym (NASA, EQ-5D) or a word missing from the French and English dictionaries.
    static func looksTechnical(_ word: String) -> Bool {
        guard word.count >= 3, word.count <= 40 else { return false }
        guard word.contains(where: { $0.isLetter }) else { return false }
        // Spelled-out letters ("N-A-S-A"): almost always a transcription error
        if isSpelledOut(word) { return false }

        let letters = word.filter { $0.isLetter }
        let uppercase = letters.filter { $0.isUppercase }.count
        if letters.count >= 2, uppercase == letters.count { return true } // acronym

        return !isKnownWord(word)
    }

    private static func isSpelledOut(_ word: String) -> Bool {
        spelledOut.firstMatch(in: word, range: NSRange(word.startIndex..., in: word)) != nil
    }

    private static func isKnownWord(_ word: String) -> Bool {
        let checker = NSSpellChecker.shared
        for language in ["fr", "en"] {
            let misspelled = checker.checkSpelling(
                of: word,
                startingAt: 0,
                language: language,
                wrap: false,
                inSpellDocumentWithTag: 0,
                wordCount: nil
            )
            if misspelled.location == NSNotFound { return true }
        }
        return false
    }

    // MARK: - Glossary by domain

    /// Glossary grouped by domain, in the priority order of `keyterms`.
    func glossaryByDomain(limit: Int) -> [(domain: VocabularyDomain, terms: [String])] {
        let wanted = keyterms(limit: limit)
        let byID = Dictionary(terms.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        var groups: [VocabularyDomain: [String]] = [:]
        for term in wanted {
            let domain = byID[term.lowercased()].flatMap(domain(of:)) ?? .other
            groups[domain, default: []].append(term)
        }
        return VocabularyDomain.allCases.compactMap { domain in
            groups[domain].map { (domain, $0) }
        }
    }

    private func domain(of term: VocabularyTerm) -> VocabularyDomain? {
        term.domain ?? SeedVocabulary.domains[term.id]
    }

    // MARK: - Classification by domain

    private var isClassifying = false
    private var lastClassificationFailure: Date?

    /// Sorts the terms without a domain (learned, added, corrected) with a small language model.
    /// Called at launch and after each learning; does nothing when there is nothing to sort.
    @MainActor
    func classifyPendingTerms() async {
        guard !isClassifying, let apiKey = KeychainHelper.shared.getAPIKey() else { return }
        // After a failure (network, model unavailable), wait 10 min before trying again
        if let failure = lastClassificationFailure, Date().timeIntervalSince(failure) < 600 { return }
        let pending = terms.filter { domain(of: $0) == nil }.map(\.term)
        guard !pending.isEmpty else { return }
        isClassifying = true
        defer { isClassifying = false }

        let names = VocabularyDomain.allCases.enumerated().map { "\($0.offset + 1). \($0.element.label)" }.joined(separator: "\n")
        for start in stride(from: 0, to: pending.count, by: 120) {
            let batch = Array(pending[start..<min(start + 120, pending.count)])
            let system = """
            You sort the terms of a user's personal dictation vocabulary into domains.
            Domains:
            \(names)
            Answer only with one line per term, in the same order, made of the term, a tab, then the domain number. Write nothing else.
            """
            guard let answer = try? await OpenRouterChat.complete(
                system: system,
                user: batch.joined(separator: "\n"),
                models: Constants.correctionModels,
                maxTokens: 4000,
                timeout: 90,
                apiKey: apiKey,
                strictPrivacy: AppSettings.shared.strictPrivacy
            ) else {
                lastClassificationFailure = Date()
                return
            }

            var assigned = 0
            for line in answer.split(separator: "\n") {
                // Tolerates "term<TAB>3", "term : 3", "- term - 3", "1. term 3"…
                guard let match = Self.classificationLine.firstMatch(in: String(line), range: NSRange(line.startIndex..., in: line)),
                      let termRange = Range(match.range(at: 1), in: line),
                      let numberRange = Range(match.range(at: 2), in: line),
                      let number = Int(line[numberRange]),
                      VocabularyDomain.allCases.indices.contains(number - 1) else { continue }
                let key = line[termRange].trimmingCharacters(in: CharacterSet(charactersIn: " \t-–:•*\"«»“”'.")).lowercased()
                guard let index = terms.firstIndex(where: { $0.id == key }), terms[index].domain == nil else { continue }
                terms[index].domain = VocabularyDomain.allCases[number - 1]
                assigned += 1
            }
            // Unusable answer: sort nothing rather than put everything under "Other"
            guard assigned > 0 else {
                lastClassificationFailure = Date()
                return
            }
            // A term the model forgot goes under "Other": it will not be sent with every dictation
            for term in batch {
                if let index = terms.firstIndex(where: { $0.id == term.lowercased() }), terms[index].domain == nil,
                   SeedVocabulary.domains[terms[index].id] == nil {
                    terms[index].domain = .other
                    assigned += 1
                }
            }
            save()
        }
        lastClassificationFailure = nil
        isClassifying = false
        // Some terms may have been learned during the call: sort them too
        if terms.contains(where: { domain(of: $0) == nil }) {
            await classifyPendingTerms()
        }
    }

    private static let classificationLine = try! NSRegularExpression(pattern: "^\\s*(?:\\d+[.)]\\s+)?(.+?)[\\s\\t:–-]+(\\d{1,2})\\s*$")

    // MARK: - Storage

    private func installSeedIfNeeded() {
        guard seedVersion < SeedVocabulary.version else { return }
        var known = Set(terms.map(\.id))
        for term in SeedVocabulary.terms {
            let key = term.lowercased()
            guard !known.contains(key), !blocked.contains(key) else { continue }
            terms.append(VocabularyTerm(term: term, count: 0, source: .seed))
            known.insert(key)
        }
        seedVersion = SeedVocabulary.version
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let store = try? JSONDecoder().decode(Store.self, from: data) else {
            return
        }
        terms = store.terms
        replacements = store.replacements
        candidates = store.candidates
        blocked = Set(store.blocked)
        seedVersion = store.seedVersion
    }

    private func save() {
        let store = Store(
            terms: terms,
            replacements: replacements,
            candidates: candidates,
            blocked: blocked.sorted(),
            seedVersion: seedVersion
        )
        guard let data = try? JSONEncoder().encode(store) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
