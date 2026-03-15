import Foundation
import NaturalLanguage

enum NLPProcessor {
  struct Request: Codable, Sendable {
    let text: String
    let tasks: [String]
  }

  struct Response: Codable, Sendable {
    var language: LanguageResult?
    var entities: [Entity]?
    var tokens: [Token]?
    var sentences: [String]?
    var embedding: [Double]?
  }

  struct LanguageResult: Codable, Sendable {
    let code: String
    let confidence: Double
  }

  struct Entity: Codable, Sendable {
    let text: String
    let type: String
    let range: [Int]
  }

  struct Token: Codable, Sendable {
    let text: String
    var pos: String?
    var lemma: String?
  }

  static var isAvailable: Bool { true }

  static func handle(_ data: Data) async throws -> Data {
    let req = try JSONDecoder().decode(Request.self, from: data)
    let tasks = Set(req.tasks)
    var resp = Response()

    if tasks.contains("language") {
      let recognizer = NLLanguageRecognizer()
      recognizer.processString(req.text)
      if let lang = recognizer.dominantLanguage {
        let hypotheses = recognizer.languageHypotheses(withMaximum: 1)
        resp.language = LanguageResult(
          code: lang.rawValue,
          confidence: hypotheses[lang] ?? 0
        )
      }
    }

    let needsTokens = !tasks.isDisjoint(with: ["tokens", "pos_tags", "lemmas", "entities"])
    if needsTokens {
      let tagger = NLTagger(tagSchemes: [.lexicalClass, .lemma, .nameType])
      tagger.string = req.text
      let range = req.text.startIndex..<req.text.endIndex

      if tasks.contains("tokens") || tasks.contains("pos_tags") || tasks.contains("lemmas") {
        var tokens: [Token] = []
        tagger.enumerateTags(
          in: range, unit: .word, scheme: .lexicalClass,
          options: [.omitWhitespace, .omitPunctuation]
        ) { tag, tokenRange in
          var token = Token(text: String(req.text[tokenRange]))
          if tasks.contains("pos_tags") { token.pos = tag?.rawValue }
          if tasks.contains("lemmas") {
            token.lemma =
              tagger.tag(at: tokenRange.lowerBound, unit: .word, scheme: .lemma).0?.rawValue
          }
          tokens.append(token)
          return true
        }
        resp.tokens = tokens
      }

      if tasks.contains("entities") {
        var entities: [Entity] = []
        tagger.enumerateTags(
          in: range, unit: .word, scheme: .nameType,
          options: [.omitWhitespace, .joinNames]
        ) { tag, tokenRange in
          if let tag {
            let start = req.text.distance(from: req.text.startIndex, to: tokenRange.lowerBound)
            let length = req.text.distance(from: tokenRange.lowerBound, to: tokenRange.upperBound)
            entities.append(
              Entity(
                text: String(req.text[tokenRange]),
                type: tag.rawValue,
                range: [start, start + length]
              ))
          }
          return true
        }
        resp.entities = entities
      }
    }

    if tasks.contains("sentences") {
      let tokenizer = NLTokenizer(unit: .sentence)
      tokenizer.string = req.text
      resp.sentences = tokenizer.tokens(for: req.text.startIndex..<req.text.endIndex)
        .map { String(req.text[$0]) }
    }

    if tasks.contains("embedding") {
      let lang = NLLanguageRecognizer.dominantLanguage(for: req.text) ?? .english
      if let embedding = NLEmbedding.sentenceEmbedding(for: lang) {
        resp.embedding = embedding.vector(for: req.text)
      }
    }

    return try JSONEncoder().encode(resp)
  }
}
