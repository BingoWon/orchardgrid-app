import ArgumentParser
import Darwin
import Foundation
import ogKit

// MARK: - @main entry
//
// Thin wrapper around `Og.main()` that preserves OGError's 1-6
// taxonomy (guardrail=3, context overflow=4, etc.) while delegating
// everything else — help, version, parse errors — to SAP's defaults
// (exit 0 for clean exits, exit 64 EX_USAGE for parse / validation).
// MCPError is translated to OGError at the point it's thrown (see
// `withMCP`), so the single catch here covers every domain error.

@main
struct OgMain {
  static func main() async {
    do {
      var command = try Og.parseAsRoot(nil)
      if var asyncCommand = command as? AsyncParsableCommand {
        try await asyncCommand.run()
      } else {
        try command.run()
      }
    } catch let og as OGError {
      FileHandle.standardError.write(
        Data(("\(og.label) \(og.message)\n").utf8))
      Darwin.exit(og.exitCode)
    } catch {
      Og.exit(withError: error)
    }
  }
}
