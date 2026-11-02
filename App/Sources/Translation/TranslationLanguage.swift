import Foundation

/// A language the live translator can listen to and translate into.
struct TranslationLanguage: Identifiable, Hashable, Sendable {
    /// Translation framework identifier, e.g. "en", "zh-Hans".
    let id: String
    let name: String
    /// Locale for speech recognition and the spoken translation.
    let speechLocale: Locale

    var language: Locale.Language { Locale.Language(identifier: id) }

    static let english = TranslationLanguage(id: "en", name: "English", speechLocale: Locale(identifier: "en-US"))
    static let vietnamese = TranslationLanguage(id: "vi", name: "Vietnamese", speechLocale: Locale(identifier: "vi-VN"))

    static let all: [TranslationLanguage] = [
        english,
        vietnamese,
        TranslationLanguage(id: "zh-Hans", name: "Chinese (Simplified)", speechLocale: Locale(identifier: "zh-CN")),
        TranslationLanguage(id: "ja", name: "Japanese", speechLocale: Locale(identifier: "ja-JP")),
        TranslationLanguage(id: "ko", name: "Korean", speechLocale: Locale(identifier: "ko-KR")),
        TranslationLanguage(id: "fr", name: "French", speechLocale: Locale(identifier: "fr-FR")),
        TranslationLanguage(id: "de", name: "German", speechLocale: Locale(identifier: "de-DE")),
        TranslationLanguage(id: "es", name: "Spanish", speechLocale: Locale(identifier: "es-ES")),
    ]
}
