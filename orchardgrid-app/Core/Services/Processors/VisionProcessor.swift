import CoreGraphics
import Foundation
import Vision

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

enum VisionProcessor {
  struct Request: Codable, Sendable {
    let image: String
    let tasks: [String]
  }

  struct Response: Codable, Sendable {
    var ocr: [TextResult]?
    var classifications: [Classification]?
    var faces: [FaceResult]?
    var barcodes: [BarcodeResult]?
  }

  struct TextResult: Codable, Sendable {
    let text: String
    let confidence: Float
  }

  struct Classification: Codable, Sendable {
    let label: String
    let confidence: Float
  }

  struct FaceResult: Codable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
  }

  struct BarcodeResult: Codable, Sendable {
    let payload: String
    let symbology: String
  }

  static var isAvailable: Bool { true }

  static func handle(_ data: Data) async throws -> Data {
    let req = try JSONDecoder().decode(Request.self, from: data)
    guard let imageData = Data(base64Encoded: req.image),
          let cgImage = decodeCGImage(from: imageData)
    else {
      throw VisionError.invalidImage
    }

    let tasks = Set(req.tasks)
    var resp = Response()
    let handler = VNImageRequestHandler(cgImage: cgImage)

    if tasks.contains("ocr") {
      let request = VNRecognizeTextRequest()
      request.recognitionLevel = .accurate
      try handler.perform([request])
      resp.ocr = (request.results ?? []).compactMap { obs in
        guard let candidate = obs.topCandidates(1).first else { return nil }
        return TextResult(text: candidate.string, confidence: candidate.confidence)
      }
    }

    if tasks.contains("classify") {
      let request = VNClassifyImageRequest()
      try handler.perform([request])
      resp.classifications = (request.results ?? [])
        .filter { $0.confidence > 0.1 }
        .prefix(10)
        .map { Classification(label: $0.identifier, confidence: $0.confidence) }
    }

    if tasks.contains("faces") {
      let request = VNDetectFaceRectanglesRequest()
      try handler.perform([request])
      resp.faces = (request.results ?? []).map { face in
        let b = face.boundingBox
        return FaceResult(x: b.origin.x, y: b.origin.y, width: b.width, height: b.height)
      }
    }

    if tasks.contains("barcodes") {
      let request = VNDetectBarcodesRequest()
      try handler.perform([request])
      resp.barcodes = (request.results ?? []).compactMap { obs in
        guard let payload = obs.payloadStringValue else { return nil }
        return BarcodeResult(payload: payload, symbology: obs.symbology.rawValue)
      }
    }

    return try JSONEncoder().encode(resp)
  }

  private static func decodeCGImage(from data: Data) -> CGImage? {
    #if os(macOS)
      guard let image = NSImage(data: data) else { return nil }
      return image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    #else
      guard let image = UIImage(data: data) else { return nil }
      return image.cgImage
    #endif
  }
}

enum VisionError: LocalizedError {
  case invalidImage

  var errorDescription: String? {
    switch self {
    case .invalidImage: "Failed to decode the provided image data"
    }
  }
}
