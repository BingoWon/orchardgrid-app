import Foundation
import OrchardGridCore

// MARK: - Inference runners
//
// `og model-info`, `og "prompt"`, `og chat`. All three use the same
// `LLMEngine` abstraction — on-device FoundationModels by default, or
// HTTP `RemoteEngine` when `--host` is set.

public func runModelInfo(engine: LLMEngine) async throws {
  let info = try await engine.health()
  let sourceLabel: String
  switch info.source {
  case .onDevice: sourceLabel = "on-device · FoundationModels"
  case .remote(let url): sourceLabel = url.absoluteString
  }
  let statusText = info.available ? info.detail : "model unavailable — \(info.detail)"
  let statusStyle: [Style] = info.available ? [.green] : [.yellow]
  let statusLine = ANSI.apply(
    statusText, styles: statusStyle, enabled: !noColor && isatty(STDOUT_FILENO) != 0)

  var lines: [String] = [
    "\(styled(AppIdentity.cliName, .cyan, .bold)) v\(ogVersion) — model info",
    "\(styled("├", .dim)) model:    \(AppIdentity.modelName)",
    "\(styled("├", .dim)) source:   \(sourceLabel)",
    "\(styled("├", .dim)) status:   \(statusLine)",
  ]
  if let ctx = info.contextSize {
    lines.append("\(styled("└", .dim)) context:  \(ctx) tokens")
  } else {
    lines[lines.count - 1] = lines[lines.count - 1].replacingOccurrences(
      of: "├", with: "└")
  }
  for line in lines { print(line) }
}

public func runPrompt(
  engine: LLMEngine,
  prompt: String,
  systemPrompt: String?,
  chatOptions: ChatOptions,
  outputFormat: OutputFormat,
  mcp: MCPManager? = nil
) async throws {
  var messages: [ChatMessage] = []
  if let systemPrompt {
    messages.append(ChatMessage(role: "system", content: systemPrompt))
  }
  messages.append(ChatMessage(role: "user", content: prompt))

  let streamToStdout = outputFormat == .plain
  let result = try await engine.chat(
    messages: messages, options: chatOptions, mcp: mcp
  ) { delta in
    if streamToStdout { writeStdout(delta) }
  }

  switch outputFormat {
  case .plain:
    print()
  case .json:
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let envelope = JSONOutput(content: result.content, usage: result.usage)
    let data = try encoder.encode(envelope)
    print(String(decoding: data, as: UTF8.self))
  }
}

public func runChat(
  engine: LLMEngine,
  systemPrompt: String?,
  chatOptions: ChatOptions,
  quiet: Bool,
  mcp: MCPManager? = nil
) async throws {
  guard isatty(STDIN_FILENO) != 0 else {
    throw OGError.usage("`og chat` requires an interactive terminal")
  }

  var messages: [ChatMessage] = []
  if let systemPrompt {
    messages.append(ChatMessage(role: "system", content: systemPrompt))
  }

  if !quiet {
    print(
      styled("OrchardGrid Chat", .cyan, .bold)
        + styled(" · \(AppIdentity.cliName) v\(ogVersion)", .dim))
    print(styled(String(repeating: "─", count: 48), .dim))
    if let systemPrompt {
      print(styled("system: ", .magenta, .bold) + styled(systemPrompt, .dim))
    }
    print(styled("Type 'quit' to exit.\n", .dim))
  }

  while true {
    if !quiet { writeStdout(styled("you› ", .yellow, .bold)) }
    guard let input = readLine() else {
      if !quiet { print() }
      break
    }
    let trimmed = input.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty { continue }
    if ["quit", "exit"].contains(trimmed.lowercased()) { break }

    messages.append(ChatMessage(role: "user", content: trimmed))
    if !quiet { writeStdout(styled(" ai› ", .cyan, .bold)) }

    do {
      let result = try await engine.chat(
        messages: messages, options: chatOptions, mcp: mcp
      ) { delta in
        writeStdout(delta)
      }
      print("\n")
      messages.append(ChatMessage(role: "assistant", content: result.content))
    } catch let og as OGError {
      messages.removeLast()
      printErr("\(og.label) \(og.message)")
    }
  }

  if !quiet { print(styled("Goodbye.", .dim)) }
}

// MARK: - Prompt assembly helpers

/// Resolve the effective system prompt: `--system-file` wins over
/// `--system` (file is treated as the full text, trimmed).
public func resolveSystemPrompt(
  system: String?,
  systemFile: String?
) -> String? {
  if let systemFile {
    if let text = try? String(contentsOfFile: systemFile, encoding: .utf8) {
      return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    printErr("warning: could not read \(systemFile)")
  }
  return system
}

/// Assemble the final prompt: positional text + `-f` files + stdin (if
/// piped). File / stdin content is prepended to the positional prompt.
public func assemblePrompt(
  positional: String,
  filePaths: [String]
) throws -> String {
  var finalPrompt = positional
  var fileContents: [String] = []

  for path in filePaths {
    do {
      fileContents.append(try String(contentsOfFile: path, encoding: .utf8))
    } catch {
      throw OGError.runtime(
        "could not read \(path): \(error.localizedDescription)")
    }
  }

  if isatty(STDIN_FILENO) == 0 {
    var lines: [String] = []
    while let line = readLine(strippingNewline: false) { lines.append(line) }
    let stdinText = lines.joined().trimmingCharacters(in: .whitespacesAndNewlines)
    if !stdinText.isEmpty {
      if finalPrompt.isEmpty && fileContents.isEmpty {
        finalPrompt = stdinText
      } else {
        fileContents.append(stdinText)
      }
    }
  }

  if !fileContents.isEmpty {
    let combined = fileContents.joined(separator: "\n\n")
    finalPrompt = finalPrompt.isEmpty ? combined : "\(combined)\n\n\(finalPrompt)"
  }
  return finalPrompt
}
