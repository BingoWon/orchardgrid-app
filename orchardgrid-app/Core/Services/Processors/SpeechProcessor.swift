import AVFoundation
import Foundation
import Speech

enum SpeechProcessor {
  struct Request: Codable, Sendable {
    let audio: String
    let language: String?
  }

  struct Response: Codable, Sendable {
    let text: String
    let segments: [Segment]?
  }

  struct Segment: Codable, Sendable {
    let text: String
    let timestamp: Double
    let duration: Double
  }

  static var isAvailable: Bool {
    SFSpeechRecognizer()?.isAvailable ?? false
  }

  static func requestPermissionIfNeeded() async -> Bool {
    let status = SFSpeechRecognizer.authorizationStatus()
    if status == .authorized { return true }
    if status == .denied || status == .restricted { return false }

    return await withCheckedContinuation { cont in
      SFSpeechRecognizer.requestAuthorization { newStatus in
        cont.resume(returning: newStatus == .authorized)
      }
    }
  }

  static func handle(_ data: Data) async throws -> Data {
    let req = try JSONDecoder().decode(Request.self, from: data)
    guard let audioData = Data(base64Encoded: req.audio) else {
      throw SpeechError.invalidAudio
    }

    guard await requestPermissionIfNeeded() else {
      throw SpeechError.notAuthorized
    }

    let locale = Locale(identifier: req.language ?? "en-US")
    guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
      throw SpeechError.unavailable
    }

    let tempURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("\(UUID().uuidString).wav")
    try audioData.write(to: tempURL)
    defer { try? FileManager.default.removeItem(at: tempURL) }

    let sfRequest = SFSpeechURLRecognitionRequest(url: tempURL)
    sfRequest.requiresOnDeviceRecognition = true
    sfRequest.shouldReportPartialResults = false

    let result: SFSpeechRecognitionResult = try await withCheckedThrowingContinuation { cont in
      recognizer.recognitionTask(with: sfRequest) { result, error in
        if let error {
          cont.resume(throwing: error)
        } else if let result, result.isFinal {
          cont.resume(returning: result)
        }
      }
    }

    let segments = result.bestTranscription.segments.map { seg in
      Segment(
        text: seg.substring,
        timestamp: seg.timestamp,
        duration: seg.duration
      )
    }

    let resp = Response(
      text: result.bestTranscription.formattedString,
      segments: segments.isEmpty ? nil : segments
    )
    return try JSONEncoder().encode(resp)
  }
}

enum SpeechError: LocalizedError {
  case unavailable
  case invalidAudio
  case notAuthorized

  var errorDescription: String? {
    switch self {
    case .unavailable: "Speech recognition is not available on this device"
    case .invalidAudio: "Failed to decode the provided audio data"
    case .notAuthorized: "Speech recognition permission not granted. Please enable it in System Settings → Privacy & Security → Speech Recognition."
    }
  }
}
