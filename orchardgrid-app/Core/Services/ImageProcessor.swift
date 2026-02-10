/**
 * ImageProcessor.swift
 * OrchardGrid Image Generation Service
 *
 * Wraps Apple's ImageCreator API (ImagePlayground framework)
 * for programmatic on-device image generation.
 * Note: Requires iOS 18.4+ / macOS 15.4+ with Apple Intelligence enabled.
 */

import CoreGraphics
import Foundation
import ImagePlayground
import OSLog

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

// MARK: - Image Processing Errors

enum ImageProcessorError: LocalizedError, Sendable {
  case notSupported
  case unavailable
  case invalidStyle(String)
  case invalidCount(Int)
  case conversionFailed
  case generationFailed(String)

  var errorDescription: String? {
    switch self {
    case .notSupported:
      "Image generation is not supported on this device"
    case .unavailable:
      "Image generation is temporarily unavailable. The model may still be downloading."
    case let .invalidStyle(style):
      "Invalid style '\(style)'. Supported styles: illustration, sketch"
    case let .invalidCount(n):
      "Invalid image count \(n). Must be between 1 and 4."
    case .conversionFailed:
      "Failed to convert generated image to PNG data"
    case let .generationFailed(message):
      "Image generation failed: \(message)"
    }
  }
}

// MARK: - Image Processor

/// Stateless namespace for on-device image generation via ImageCreator.
/// All methods are static — no instance needed.
enum ImageProcessor {
  // MARK: - Availability

  static var isAvailable: Bool {
    ImagePlaygroundViewController.isAvailable
  }

  // MARK: - Public API

  /// Generate images from a text prompt.
  /// - Parameters:
  ///   - prompt: Text description for image generation
  ///   - style: Style name ("illustration" or "sketch"), nil defaults to illustration
  ///   - count: Number of images to generate (1-4)
  /// - Returns: Array of PNG image data
  static func generateImages(
    prompt: String,
    style: String?,
    count: Int
  ) async throws -> [Data] {
    guard (1 ... 4).contains(count) else {
      throw ImageProcessorError.invalidCount(count)
    }

    let playgroundStyle = try mapStyle(style)
    let concept = ImagePlaygroundConcept.text(prompt)
    let creator = try await ImageCreator()

    var results: [Data] = []

    do {
      for try await image in creator.images(for: [concept], style: playgroundStyle, limit: count) {
        guard let pngData = pngData(from: image.cgImage) else {
          Logger.error(.imageGen, "Failed to convert CGImage to PNG")
          throw ImageProcessorError.conversionFailed
        }
        results.append(pngData)
      }
    } catch let error as ImageCreator.Error {
      switch error {
      case .notSupported:
        throw ImageProcessorError.notSupported
      case .unavailable:
        throw ImageProcessorError.unavailable
      @unknown default:
        throw ImageProcessorError.generationFailed(error.localizedDescription)
      }
    } catch let error as ImageProcessorError {
      throw error
    } catch {
      throw ImageProcessorError.generationFailed(error.localizedDescription)
    }

    Logger.success(.imageGen, "Generated \(results.count) image(s)")
    return results
  }

  // MARK: - Private Helpers

  private static func mapStyle(_ style: String?) throws -> ImagePlaygroundStyle {
    guard let style else { return .illustration }

    switch style.lowercased() {
    case "illustration":
      return .illustration
    case "sketch":
      return .sketch
    default:
      throw ImageProcessorError.invalidStyle(style)
    }
  }

  private static func pngData(from cgImage: CGImage) -> Data? {
    #if os(macOS)
      let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
      return bitmapRep.representation(using: .png, properties: [:])
    #else
      let uiImage = UIImage(cgImage: cgImage)
      return uiImage.pngData()
    #endif
  }
}
