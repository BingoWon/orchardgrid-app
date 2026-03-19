import AVFoundation
import Foundation
import SoundAnalysis
import Synchronization

enum SoundProcessor {
  struct Request: Codable, Sendable {
    let audio: String
  }

  struct Response: Codable, Sendable {
    let classifications: [Classification]
    let duration: Double
  }

  struct Classification: Codable, Sendable {
    let label: String
    let confidence: Double
  }

  static var isAvailable: Bool { true }

  static func handle(_ data: Data) async throws -> Data {
    let req = try JSONDecoder().decode(Request.self, from: data)
    guard let audioData = Data(base64Encoded: req.audio) else {
      throw SoundError.invalidAudio
    }

    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("\(UUID().uuidString).wav")
    try audioData.write(to: tempURL)
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let analyzer = try SNAudioFileAnalyzer(url: tempURL)
    let classifyRequest = try SNClassifySoundRequest(classifierIdentifier: .version1)
    let observer = SoundResultObserver()

    try analyzer.add(classifyRequest, withObserver: observer)
    await analyzer.analyze()

    let asset = AVURLAsset(url: tempURL)
    let duration = try await asset.load(.duration).seconds

    let resp = Response(
      classifications: observer.topResults(limit: 10),
      duration: duration
    )
    return try JSONEncoder().encode(resp)
  }
}

private final class SoundResultObserver: NSObject, SNResultsObserving, @unchecked Sendable {
  private let results = Mutex<[String: Double]>([:])

  func request(_: SNRequest, didProduce result: SNResult) {
    guard let classification = result as? SNClassificationResult else { return }
    results.withLock { dict in
      for item in classification.classifications where item.confidence > 0.01 {
        dict[item.identifier] = max(dict[item.identifier] ?? 0, item.confidence)
      }
    }
  }

  func request(_: SNRequest, didFailWithError error: Error) {
    print("[SoundProcessor] Analysis failed: \(error.localizedDescription)")
  }
  func requestDidComplete(_: SNRequest) {}

  func topResults(limit: Int) -> [SoundProcessor.Classification] {
    results.withLock { dict in
      dict.sorted { $0.value > $1.value }
        .prefix(limit)
        .map { SoundProcessor.Classification(label: $0.key, confidence: $0.value) }
    }
  }
}

enum SoundError: LocalizedError {
  case invalidAudio

  var errorDescription: String? {
    "Failed to decode the provided audio data"
  }
}
