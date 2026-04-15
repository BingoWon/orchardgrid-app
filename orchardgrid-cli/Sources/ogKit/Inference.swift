import Foundation
import OrchardGridCore

// MARK: - Inference commands
//
// `og --model-info`, `og "prompt"`, `og --chat`. All three use the same
// `LLMEngine` abstraction — on-device FoundationModels by default, or
// HTTP `RemoteEngine` when `--host` is set. No config-file coupling.

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
  args: Arguments,
  prompt: String,
  systemPrompt: String?,
  mcp: MCPManager? = nil
) async throws {
  var messages: [ChatMessage] = []
  if let systemPrompt {
    messages.append(ChatMessage(role: "system", content: systemPrompt))
  }
  messages.append(ChatMessage(role: "user", content: prompt))

  let streamToStdout = args.outputFormat == .plain
  let result = try await engine.chat(
    messages: messages, options: chatOptions(args), mcp: mcp
  ) { delta in
    if streamToStdout { writeStdout(delta) }
  }

  switch args.outputFormat {
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
  engine: LLMEngine, args: Arguments, systemPrompt: String?, mcp: MCPManager? = nil
) async throws {
  guard isatty(STDIN_FILENO) != 0 else {
    throw OGError.usage("--chat requires an interactive terminal")
  }

  var messages: [ChatMessage] = []
  if let systemPrompt {
    messages.append(ChatMessage(role: "system", content: systemPrompt))
  }

  if !args.quiet {
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
    if !args.quiet { writeStdout(styled("you› ", .yellow, .bold)) }
    guard let input = readLine() else {
      if !args.quiet { print() }
      break
    }
    let trimmed = input.trimmingCharacters(in: .whitespaces)
    if trimmed.isEmpty { continue }
    if ["quit", "exit"].contains(trimmed.lowercased()) { break }

    messages.append(ChatMessage(role: "user", content: trimmed))
    if !args.quiet { writeStdout(styled(" ai› ", .cyan, .bold)) }

    do {
      let result = try await engine.chat(
        messages: messages, options: chatOptions(args), mcp: mcp
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

  if !args.quiet { print(styled("Goodbye.", .dim)) }
}

// MARK: - Helpers

public func chatOptions(_ args: Arguments) -> ChatOptions {
  ChatOptions(
    temperature: args.temperature,
    maxTokens: args.maxTokens,
    seed: args.seed,
    contextStrategy: args.contextStrategy,
    contextMaxTurns: args.contextMaxTurns,
    permissive: args.permissive
  )
}

/// Resolve the effective system prompt: `--system-file` wins over `--system`
/// (file is treated as the full text, trimmed).
public func resolveSystemPrompt(_ args: Arguments) -> String? {
  if let sysFile = args.systemFile {
    if let text = try? String(contentsOfFile: sysFile, encoding: .utf8) {
      return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    printErr("warning: could not read \(sysFile)")
  }
  return args.systemPrompt
}

/// Assemble the final prompt: positional args + `-f` files + stdin.
/// File / stdin content is prepended to the positional prompt text.
public func assemblePrompt(_ args: Arguments) throws -> String {
  var finalPrompt = args.prompt
  var fileContents: [String] = []

  for path in args.filePaths {
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
