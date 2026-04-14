import Foundation
import Testing

@testable import ogKit

@Suite("LoopbackServer binding & callback")
struct LoopbackServerTests {

  /// Regression guard for the port-binding bug: NWListener's
  /// `listener.port` can return `.any` (rawValue == 0) before the listener
  /// reaches `.ready`, which made an earlier version build a nonsense
  /// redirect URL like `http://127.0.0.1:0/cb`.
  @Test("start() returns a real ephemeral port, never 0")
  func portIsReal() async throws {
    let server = try await LoopbackServer.start()
    defer { /* listener auto-cancels when awaitCallback returns */  }

    #expect(server.port != 0)
    #expect(server.port >= 1024)
    #expect(server.port <= 65535)

    // Cancel by timing out a callback wait.
    await #expect(throws: OGError.self) {
      try await server.awaitCallback(timeout: .milliseconds(50))
    }
  }

  @Test("awaitCallback times out if no request arrives")
  func timesOutWithoutCallback() async throws {
    let server = try await LoopbackServer.start()
    let start = Date()
    do {
      _ = try await server.awaitCallback(timeout: .milliseconds(200))
      Issue.record("expected timeout")
    } catch let og as OGError {
      guard case .runtime(let msg) = og else {
        Issue.record("expected .runtime, got \(og)")
        return
      }
      #expect(msg.contains("timed out"))
    }
    let elapsed = Date().timeIntervalSince(start)
    // Should time out close to 200 ms — not 0 ms (instant error) and not
    // many seconds.
    #expect(elapsed >= 0.15)
    #expect(elapsed < 2.0)
  }

  @Test("awaitCallback delivers the callback when the loopback is hit")
  func deliversCallback() async throws {
    let server = try await LoopbackServer.start()
    let port = server.port

    // Fire a request at the loopback from a detached task that starts
    // AFTER we're awaiting the callback.
    let hitTask = Task.detached {
      try? await Task.sleep(for: .milliseconds(50))
      var request = URLRequest(
        url: URL(string: "http://127.0.0.1:\(port)/cb?token=hello&state=s1")!)
      request.timeoutInterval = 2
      _ = try? await URLSession.shared.data(for: request)
    }

    let callback = try await server.awaitCallback(timeout: .seconds(3))
    #expect(callback.token == "hello")
    #expect(callback.state == "s1")

    await hitTask.value  // cleanup
  }

  @Test("two consecutive servers get different ephemeral ports")
  func consecutiveServersDiffer() async throws {
    let s1 = try await LoopbackServer.start()
    let s2 = try await LoopbackServer.start()
    #expect(s1.port != s2.port)
    // Cancel both to release ports before the suite finishes.
    _ = try? await s1.awaitCallback(timeout: .milliseconds(10))
    _ = try? await s2.awaitCallback(timeout: .milliseconds(10))
  }
}
