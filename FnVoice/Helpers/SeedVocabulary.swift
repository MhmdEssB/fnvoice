import Foundation

/// Starting vocabulary, deliberately empty: FnVoice learns your words as you dictate.
/// Add terms specific to your field here (acronyms, proper names, jargon) if you want
/// them known from the first use.
enum SeedVocabulary {
    /// Increase it when the list is extended, so the new terms get added.
    static let version = 1

    static let terms: [String] = []
}
