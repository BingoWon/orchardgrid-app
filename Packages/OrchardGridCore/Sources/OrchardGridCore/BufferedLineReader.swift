import Darwin
import Foundation

// MARK: - Buffered newline-delimited line reader
//
// MCP runs JSON-RPC 2.0 over stdio with one JSON object per line. Foundation
// doesn't ship a stream reader that respects a timeout, so we do buffered
// reads against the raw fd with `poll(2)` as the deadline gate.

public final class BufferedLineReader: @unchecked Sendable {
  private let fd: Int32
  private let bufferSize: Int
  private var leftover = Data()

  public init(fileDescriptor: Int32, bufferSize: Int = 4096) {
    self.fd = fileDescriptor
    self.bufferSize = bufferSize
  }

  /// Read one line (without trailing '\n'). Throws `MCPError.timedOut`
  /// if no complete line arrives before the deadline.
  public func readLine(timeoutMilliseconds: Int, label: String) throws -> String {
    var line = Data()
    let deadline = Date().timeIntervalSinceReferenceDate + Double(timeoutMilliseconds) / 1000

    if let nl = leftover.firstIndex(of: UInt8(ascii: "\n")) {
      line.append(leftover[leftover.startIndex..<nl])
      leftover = Data(leftover[(nl + 1)...])
      if let s = String(data: line, encoding: .utf8), !s.isEmpty { return s }
    } else if !leftover.isEmpty {
      line.append(leftover)
      leftover = Data()
    }

    var chunk = [UInt8](repeating: 0, count: bufferSize)
    while true {
      let remaining = Int((deadline - Date().timeIntervalSinceReferenceDate) * 1000)
      if remaining <= 0 {
        throw MCPError.timedOut("\(label) timed out after \(timeoutMilliseconds / 1000)s")
      }

      var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
      let ready = poll(&pfd, 1, Int32(remaining))
      if ready == 0 {
        throw MCPError.timedOut("\(label) timed out after \(timeoutMilliseconds / 1000)s")
      }
      if ready < 0 {
        if errno == EINTR { continue }
        throw MCPError.processError(
          "poll failed: \(String(cString: strerror(errno)))")
      }
      if (pfd.revents & Int16(POLLNVAL)) != 0 {
        throw MCPError.processError("MCP stdout became invalid")
      }
      if (pfd.revents & Int16(POLLERR)) != 0 {
        throw MCPError.processError("MCP stdout reported an I/O error")
      }
      if (pfd.revents & Int16(POLLHUP)) != 0 && (pfd.revents & Int16(POLLIN)) == 0 {
        throw MCPError.processError("MCP server closed unexpectedly")
      }
      if (pfd.revents & Int16(POLLIN)) == 0 { continue }

      let n = Darwin.read(fd, &chunk, chunk.count)
      if n == 0 { throw MCPError.processError("MCP server closed unexpectedly") }
      if n < 0 {
        if errno == EINTR { continue }
        throw MCPError.processError(
          "read failed: \(String(cString: strerror(errno)))")
      }
      let bytes = chunk[..<n]
      if let nl = bytes.firstIndex(of: UInt8(ascii: "\n")) {
        line.append(contentsOf: bytes[bytes.startIndex..<nl])
        let after = bytes.index(after: nl)
        if after < bytes.endIndex { leftover = Data(bytes[after...]) }
        break
      }
      line.append(contentsOf: bytes)
    }
    guard let s = String(data: line, encoding: .utf8), !s.isEmpty else {
      throw MCPError.processError("Empty MCP response")
    }
    return s
  }
}
