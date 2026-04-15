import Foundation

// MARK: - Version

/// CLI version. Exposed from the library so both main.swift's usage banner
/// and subcommand output (model-info, etc.) reference the same string.
public let ogVersion = "0.1.0"

// MARK: - ANSI Styling

public enum Style: String, Sendable {
  case bold = "\u{001B}[1m"
  case dim = "\u{001B}[2m"
  case cyan = "\u{001B}[36m"
  case magenta = "\u{001B}[35m"
  case green = "\u{001B}[32m"
  case yellow = "\u{001B}[33m"
  case red = "\u{001B}[31m"
}

public let ansiReset = "\u{001B}[0m"

/// Pure formatter — deterministic, test-friendly. Takes an explicit `enabled`
/// flag so tests don't depend on global state or TTY detection.
public enum ANSI {
  public static func apply(_ text: String, styles: [Style], enabled: Bool) -> String {
    guard enabled else { return text }
    return styles.map(\.rawValue).joined() + text + ansiReset
  }
}

/// Global color flag, set once at startup from CLI args / env. Mutated only
/// during argument parsing; readers after that point see a stable value.
public nonisolated(unsafe) var noColor = false

/// Setter used by command-layer `FormatOptions.applyColor()`. Kept as a
/// free function so call sites don't need to worry about module prefix.
public func applyGlobalNoColor(_ value: Bool) { noColor = value }

/// Convenience wrapper for the common "print to a TTY" case.
public func styled(_ text: String, _ styles: Style...) -> String {
  ANSI.apply(text, styles: styles, enabled: !noColor && isatty(STDOUT_FILENO) != 0)
}

// MARK: - IO Helpers

public func printErr(_ message: String) {
  FileHandle.standardError.write(Data((message + "\n").utf8))
}

public func writeStdout(_ text: String) {
  FileHandle.standardOutput.write(Data(text.utf8))
}

// MARK: - JSON Output Envelope

public struct JSONOutput: Encodable, Sendable {
  public let content: String
  public let usage: Usage?

  public init(content: String, usage: Usage?) {
    self.content = content
    self.usage = usage
  }
}
