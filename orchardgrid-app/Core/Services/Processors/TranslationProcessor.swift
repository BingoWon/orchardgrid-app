@preconcurrency import FoundationModels
import Foundation

enum TranslationProcessor {
  struct Request: Codable, Sendable {
    let text: [String]
    let source_language: String?
    let target_language: String
  }

  struct Response: Codable, Sendable {
    let translations: [Translation]

    struct Translation: Codable, Sendable {
      let text: String
    }
  }

  static var isAvailable: Bool {
    if case .available = SystemLanguageModel.default.availability { return true }
    return false
  }

  @MainActor
  static func handle(_ data: Data) async throws -> Data {
    let req = try JSONDecoder().decode(Request.self, from: data)

    let sourceLang = req.source_language.map { " from \($0)" } ?? ""
    let instructions = """
    You are a professional translator. Translate\(sourceLang) to \(req.target_language). \
    Output ONLY the translated text, preserving the original formatting. No explanations.
    """

    let session = LanguageModelSession(instructions: instructions)

    var translations: [Response.Translation] = []
    for text in req.text {
      let result = try await session.respond(to: text)
      translations.append(.init(text: result.content))
    }

    return try JSONEncoder().encode(Response(translations: translations))
  }
}
