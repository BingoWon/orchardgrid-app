/**
 * ImageGenerationTool.swift
 * Foundation Models tool that enables image generation via Apple Intelligence
 */

import Foundation
@preconcurrency import FoundationModels
import ImagePlayground

// MARK: - Image Collector

/// Thread-safe side-channel for passing reference images to the tool
/// and collecting generated filenames back to the ChatManager.
actor ImageCollector {
  private var filenames: [String] = []
  private var referenceImageURL: URL?

  func setReferenceImage(_ url: URL?) {
    referenceImageURL = url
  }

  func getReferenceImage() -> URL? {
    referenceImageURL
  }

  func add(_ filename: String) {
    filenames.append(filename)
  }

  func flush() -> [String] {
    let result = filenames
    filenames = []
    referenceImageURL = nil
    return result
  }
}

// MARK: - Image Generation Tool

struct ImageGenerationTool: Tool {
  let name = "generateImage"
  let description = """
    Generate an image from a text description. Works best with scenes, objects, \
    and illustrations. For images of people, a reference photo must be attached first.
    """

  let collector: ImageCollector

  @Generable
  struct Arguments {
    @Guide(description: "Text description of the image to generate")
    var prompt: String
  }

  func call(arguments: Arguments) async throws -> String {
    guard await ImageProcessor.isAvailable else {
      return "Image generation is not available on this device."
    }

    let referenceURL = await collector.getReferenceImage()

    do {
      let images = try await ImageProcessor.generateImages(
        prompt: arguments.prompt,
        style: nil,
        count: 1,
        sourceImage: referenceURL
      )

      guard let imageData = images.first else {
        return "Image generation produced no output."
      }

      let filename = "chat_\(UUID().uuidString).png"
      let dir = await ChatImages.directory
      let url = dir.appendingPathComponent(filename)

      try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
      try imageData.write(to: url, options: .atomic)

      await collector.add(filename)

      return "Image generated successfully for prompt: \(arguments.prompt)"
    } catch {
      let hint =
        referenceURL == nil
        ? " Tip: If your prompt involves a person, ask the user to attach a reference photo first."
        : ""
      return "Image generation failed: \(error.localizedDescription)\(hint)"
    }
  }
}
