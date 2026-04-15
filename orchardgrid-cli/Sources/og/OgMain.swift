import ArgumentParser
import Darwin
import Foundation
import ogKit

// MARK: - @main entry
//
// Custom wrapper around `Og.main()` so we can map swift-argument-parser's
// default exit codes (0 for success/help, 64 EX_USAGE for parse errors,
// 1 otherwise) onto the CLI's documented 0-6 contract — most notably
// "usage errors exit 2 regardless of source".

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
      Darwin.exit(0)
    } catch let og as OGError {
      // Single place where OGError turns into a stderr line + exit code.
      FileHandle.standardError.write(
        Data(("\(og.label) \(og.message)\n").utf8))
      Darwin.exit(og.exitCode)
    } catch {
      // Let SAP print help / usage / error messages exactly as it
      // normally would, then override the exit code.
      let messageText = Og.fullMessage(for: error)
      if !messageText.isEmpty {
        if isCleanExit(error) {
          print(messageText)
        } else {
          FileHandle.standardError.write(Data((messageText + "\n").utf8))
        }
      }
      Darwin.exit(ogExitCode(for: error))
    }
  }

  /// SAP's own computed exit code — 0 for help / CleanExit / .success,
  /// non-zero otherwise. We trust this for the "clean vs error" split,
  /// then remap every non-zero SAP code (64 for parse errors, 1 for
  /// generic) onto our "usage" (2) so the exit-code contract stays 0-6.
  private static func ogExitCode(for error: Error) -> Int32 {
    if let og = error as? OGError { return og.exitCode }
    let sap = Og.exitCode(for: error).rawValue
    return sap == 0 ? 0 : ExitStatus.usage.rawValue
  }

  private static func isCleanExit(_ error: Error) -> Bool {
    Og.exitCode(for: error).rawValue == 0
  }
}
