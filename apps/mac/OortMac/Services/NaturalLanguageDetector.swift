import NaturalLanguage
import OortLibrary

/// The language of a text for the core (`TextLanguageDetector`): NaturalLanguage's first hypothesis, as before.
struct NaturalLanguageDetector: TextLanguageDetector {
    func dominantLanguage(of text: String) -> (tag: String, confidence: Double)? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let (language, confidence) = recognizer.languageHypotheses(withMaximum: 1).first,
              language != .undetermined else { return nil }
        return (Self.resolvedTag(language, text: text), confidence)
    }

    static func resolvedTag(_ language: NLLanguage, text: String) -> String {
        // NaturalLanguage can mistake Spanish store text for Catalan, especially when game names dominate it.
        if language == .catalan, text.contains("¡") || text.contains("¿") { return NLLanguage.spanish.rawValue }
        return language.rawValue
    }
}
