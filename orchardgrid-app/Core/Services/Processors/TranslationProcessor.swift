import Foundation
import NaturalLanguage
import Translation

enum TranslationProcessor {
  struct Request: Codable, Sendable {
    let text: [String]
    let source_language: String?
    let target_language: String
  }

  struct Response: Codable, Sendable {
    let translations: [TranslatedText]
    let detected_language: String?

    struct TranslatedText: Codable, Sendable {
      let text: String
    }
  }

  static var isAvailable: Bool { true }

  static func handle(_ data: Data) async throws -> Data {
    let req = try JSONDecoder().decode(Request.self, from: data)
    let target = Locale.Language(identifier: req.target_language)

    let source: Locale.Language
    var detectedLanguage: String?

    if let sourceId = req.source_language {
      source = Locale.Language(identifier: sourceId)
    } else {
      let combined = req.text.joined(separator: " ")
      guard let detected = NLLanguageRecognizer.dominantLanguage(for: combined) else {
        throw TranslationProcessorError.languageNotDetected
      }
      source = Locale.Language(identifier: detected.rawValue)
      detectedLanguage = detected.rawValue
    }

    let session = TranslationSession(installedSource: source, target: target)

    let requests = req.text.enumerated().map { idx, text in
      TranslationSession.Request(sourceText: text, clientIdentifier: "\(idx)")
    }

    let responses = try await session.translations(from: requests)

    let translations = responses.map { resp in
      Response.TranslatedText(text: resp.targetText)
    }

    return try JSONEncoder().encode(Response(
      translations: translations,
      detected_language: detectedLanguage
    ))
  }
}

enum TranslationProcessorError: LocalizedError {
  case languageNotDetected

  var errorDescription: String? {
    switch self {
    case .languageNotDetected: "Could not detect the source language"
    }
  }
}
