import Foundation
import Network

// MARK: - Login Flow

/// The loopback OAuth dance: CLI opens a tiny HTTP server on 127.0.0.1:<port>,
/// opens the user's browser to the web /cli/login page with that callback
/// URL, and waits for the browser to redirect back with `?token=…&state=…`.
public enum LoginFlow {

  public struct Result: Sendable {
    public let token: String
    public let host: String
    public let deviceLabel: String
  }

  /// Runs the full flow. Blocks until the callback is received or the
  /// timeout elapses.
  ///
  /// - Parameters:
  ///   - host: Base URL of the OrchardGrid web app, e.g. `https://orchardgrid.com`.
  ///   - deviceLabel: Human-readable device name stored on the server side.
  ///   - timeout: How long to wait for the browser callback before giving up.
  ///   - openURL: Injectable opener (so tests can intercept).
  public static func run(
    host: String,
    deviceLabel: String,
    timeout: Duration = .seconds(300),
    openURL: @Sendable (URL) -> Void = Self.openInBrowser
  ) async throws -> Result {
    guard let baseURL = URL(string: host) else {
      throw OGError.usage("invalid host: \(host)")
    }

    let state = Self.randomToken(32)
    let server = try await LoopbackServer.start()

    let loginURL = Self.buildLoginURL(
      base: baseURL,
      port: server.port,
      state: state,
      deviceLabel: deviceLabel
    )

    printErr("Opening browser to authorize:")
    printErr("  \(loginURL.absoluteString)")
    printErr("")
    printErr("If the browser doesn't open automatically, copy the URL above.")
    printErr("Waiting for callback on http://127.0.0.1:\(server.port)/ …")

    openURL(loginURL)

    let callback = try await server.awaitCallback(timeout: timeout)
    guard callback.state == state else {
      throw OGError.runtime("state mismatch — possible CSRF, aborting")
    }
    guard !callback.token.isEmpty else {
      throw OGError.runtime("server returned no token")
    }

    return Result(
      token: callback.token,
      host: baseURL.absoluteString,
      deviceLabel: deviceLabel
    )
  }

  // MARK: - Browser opener

  /// Opens the authorization URL in the default browser.
  /// Set `OG_NO_BROWSER=1` to suppress — used by the pytest suite so
  /// running `make test-int` doesn't spam real browser tabs with URLs
  /// that point at mock servers or dead loopback ports.
  public static func openInBrowser(_ url: URL) {
    if ProcessInfo.processInfo.environment["OG_NO_BROWSER"] != nil {
      printErr("(OG_NO_BROWSER=1 — skipping browser launch)")
      return
    }
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    task.arguments = [url.absoluteString]
    try? task.run()
  }

  // MARK: - URL building

  static func buildLoginURL(
    base: URL,
    port: UInt16,
    state: String,
    deviceLabel: String
  ) -> URL {
    var components = URLComponents(url: base, resolvingAgainstBaseURL: false)!
    components.path = "/cli/login"
    components.queryItems = [
      URLQueryItem(name: "redirect_uri", value: "http://127.0.0.1:\(port)/cb"),
      URLQueryItem(name: "state", value: state),
      URLQueryItem(name: "device_label", value: deviceLabel),
    ]
    return components.url!
  }

  static func randomToken(_ bytes: Int) -> String {
    var data = Data(count: bytes)
    _ = data.withUnsafeMutableBytes {
      SecRandomCopyBytes(kSecRandomDefault, bytes, $0.baseAddress!)
    }
    return data.map { String(format: "%02x", $0) }.joined()
  }
}

// MARK: - Loopback Server

/// Tiny one-shot HTTP server. Listens on an ephemeral port on 127.0.0.1,
/// accepts one GET request, extracts query params, sends a small HTML
/// success page, then shuts down. The callback is delivered via an
/// `AsyncThrowingStream` — Sendable-safe without manual locking.
final class LoopbackServer: @unchecked Sendable {
  struct Callback: Sendable {
    let token: String
    let state: String
  }

  let port: UInt16

  private let listener: NWListener
  private let stream: AsyncThrowingStream<Callback, Error>
  private let continuation: AsyncThrowingStream<Callback, Error>.Continuation

  private init(
    listener: NWListener,
    port: UInt16,
    stream: AsyncThrowingStream<Callback, Error>,
    continuation: AsyncThrowingStream<Callback, Error>.Continuation
  ) {
    self.listener = listener
    self.port = port
    self.stream = stream
    self.continuation = continuation
  }

  /// Binds on an ephemeral port on 127.0.0.1 and waits for the listener to
  /// reach `.ready` before returning — that's the only state where
  /// `listener.port` reflects the actual bound port (before .ready it can
  /// still be `.any`/0 which is what the caller's URL would incorrectly use).
  static func start() async throws -> LoopbackServer {
    let params = NWParameters.tcp
    params.allowLocalEndpointReuse = true
    let listener = try NWListener(using: params, on: .any)

    var cont: AsyncThrowingStream<Callback, Error>.Continuation!
    let stream = AsyncThrowingStream<Callback, Error> { c in cont = c }
    let continuation = cont!

    listener.newConnectionHandler = { connection in
      connection.start(queue: .global())
      Self.handle(connection: connection, continuation: continuation)
    }

    let port: UInt16 = try await withCheckedThrowingContinuation {
      (cc: CheckedContinuation<UInt16, any Error>) in
      listener.stateUpdateHandler = { state in
        switch state {
        case .ready:
          if let bound = listener.port?.rawValue, bound != 0 {
            listener.stateUpdateHandler = nil
            cc.resume(returning: bound)
          } else {
            listener.stateUpdateHandler = nil
            cc.resume(
              throwing: OGError.runtime(
                "loopback listener ready but port is 0 / unresolved"))
          }
        case .failed(let error):
          listener.stateUpdateHandler = nil
          cc.resume(throwing: error)
        case .cancelled:
          listener.stateUpdateHandler = nil
          cc.resume(throwing: OGError.runtime("loopback listener cancelled"))
        default:
          break
        }
      }
      listener.start(queue: .global())
    }

    return LoopbackServer(
      listener: listener, port: port, stream: stream, continuation: continuation)
  }

  func awaitCallback(timeout: Duration) async throws -> Callback {
    defer {
      listener.cancel()
      continuation.finish()
    }
    return try await withThrowingTaskGroup(of: Callback.self) { group in
      group.addTask { [stream] in
        for try await cb in stream { return cb }
        throw OGError.runtime("loopback stream closed before callback")
      }
      group.addTask {
        try await Task.sleep(for: timeout)
        throw OGError.runtime("login timed out waiting for browser callback")
      }
      defer { group.cancelAll() }
      return try await group.next()!
    }
  }

  // MARK: - Request handling

  private static func handle(
    connection: NWConnection,
    continuation: AsyncThrowingStream<Callback, Error>.Continuation
  ) {
    connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) {
      data, _, _, _ in
      guard let data, let request = String(data: data, encoding: .utf8) else {
        connection.cancel()
        return
      }

      let firstLine = request.components(separatedBy: "\r\n").first ?? ""
      let parts = firstLine.split(separator: " ")
      guard parts.count >= 2 else {
        connection.cancel()
        return
      }
      let path = String(parts[1])

      guard let urlComponents = URLComponents(string: "http://localhost\(path)")
      else {
        connection.cancel()
        return
      }
      let items = urlComponents.queryItems ?? []
      let token = items.first(where: { $0.name == "token" })?.value ?? ""
      let state = items.first(where: { $0.name == "state" })?.value ?? ""

      let body = Self.successPage
      let response =
        "HTTP/1.1 200 OK\r\n"
        + "Content-Type: text/html; charset=utf-8\r\n"
        + "Content-Length: \(body.utf8.count)\r\n"
        + "Connection: close\r\n"
        + "\r\n"
        + body

      // Yield the callback only AFTER the response has been fully flushed
      // to the kernel socket buffer. The outer `awaitCallback`'s defer
      // cancels the listener as soon as it receives the callback; if we
      // yielded before `send` drained, that cancellation would reset
      // the in-flight TCP connection and the browser would see
      // `RemoteDisconnected`.
      connection.send(
        content: Data(response.utf8),
        completion: .contentProcessed { _ in
          connection.cancel()
          continuation.yield(Callback(token: token, state: state))
        })
    }
  }

  /// Brand-matched success page — mirrors orchardgrid.com's visual language
  /// (forest-green primary, cream accent, Inter + Plus Jakarta Sans, subtle
  /// radial spotlight) and adapts automatically to light / dark OS theme.
  /// Served directly from the tiny loopback HTTP server with no framework.
  private static let successPage = #"""
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>OrchardGrid · CLI authorized</title>
      <link rel="preconnect" href="https://rsms.me/">
      <link rel="stylesheet" href="https://rsms.me/inter/inter.css">
      <style>
        :root {
          --bg:           #fafafa;
          --card:         #ffffff;
          --fg:           #1a1a1a;
          --muted:        #6b6b6b;
          --border:       #e7e5df;
          --primary:      #015135;
          --primary-10:   rgba(1, 81, 53, 0.08);
          --primary-20:   rgba(1, 81, 53, 0.18);
          --radius:       14px;
          --radius-sm:    10px;
          --shadow:       0 1px 2px rgba(0,0,0,0.04), 0 8px 24px rgba(0,0,0,0.04);
        }
        @media (prefers-color-scheme: dark) {
          :root {
            --bg:         #13211c;
            --card:       #18281f;
            --fg:         #f2f2f0;
            --muted:      #9aa7a0;
            --border:     rgba(228, 223, 184, 0.12);
            --primary:    #4aa88d;
            --primary-10: rgba(74, 168, 141, 0.14);
            --primary-20: rgba(74, 168, 141, 0.28);
            --shadow:     0 1px 2px rgba(0,0,0,0.3), 0 12px 40px rgba(0,0,0,0.4);
          }
        }
        * { box-sizing: border-box; margin: 0; padding: 0; }
        html, body { height: 100%; }
        body {
          font-family: "Inter", ui-sans-serif, system-ui, -apple-system,
                       "Segoe UI", sans-serif;
          font-feature-settings: "cv11", "ss01";
          background: var(--bg);
          color: var(--fg);
          display: flex;
          align-items: center;
          justify-content: center;
          padding: 24px;
          position: relative;
          overflow: hidden;
        }
        /* Radial spotlight echoing the landing page hero */
        body::before {
          content: "";
          position: absolute;
          inset: -20%;
          background: radial-gradient(ellipse at top,
                      var(--primary-10) 0%, transparent 55%);
          pointer-events: none;
          z-index: 0;
        }
        .card {
          position: relative;
          z-index: 1;
          background: var(--card);
          border: 1px solid var(--border);
          border-radius: var(--radius);
          box-shadow: var(--shadow);
          padding: 36px 40px;
          max-width: 440px;
          width: 100%;
          text-align: center;
        }
        .mark {
          display: inline-flex;
          align-items: center;
          justify-content: center;
          width: 56px;
          height: 56px;
          border-radius: 16px;
          background: var(--primary-10);
          color: var(--primary);
          margin-bottom: 20px;
          box-shadow: inset 0 0 0 1px var(--primary-20);
        }
        .mark svg { width: 28px; height: 28px; }
        h1 {
          font-family: "Plus Jakarta Sans", "Inter", sans-serif;
          font-size: 22px;
          font-weight: 600;
          letter-spacing: -0.01em;
          margin-bottom: 8px;
        }
        p {
          font-size: 14.5px;
          line-height: 1.55;
          color: var(--muted);
        }
        .hint {
          margin-top: 20px;
          padding: 10px 14px;
          background: var(--primary-10);
          border-radius: var(--radius-sm);
          font-size: 13px;
          color: var(--fg);
          display: inline-flex;
          align-items: center;
          gap: 8px;
        }
        .hint code {
          font-family: "JetBrains Mono", ui-monospace, SFMono-Regular, monospace;
          font-size: 12.5px;
          color: var(--primary);
          font-weight: 500;
        }
      </style>
    </head>
    <body>
      <div class="card">
        <div class="mark" aria-hidden="true">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor"
               stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round">
            <polyline points="4 12 10 18 20 6"/>
          </svg>
        </div>
        <h1>CLI authorized</h1>
        <p>Your <code style="font-family:'JetBrains Mono',ui-monospace,monospace">og</code>
        session is connected. You can close this tab and return to your terminal.</p>
        <div class="hint">
          <svg width="14" height="14" viewBox="0 0 24 24" fill="none"
               stroke="currentColor" stroke-width="2" stroke-linecap="round"
               stroke-linejoin="round" aria-hidden="true">
            <polyline points="4 17 10 11 4 5"/><line x1="12" y1="19" x2="20" y2="19"/>
          </svg>
          <span>Try <code>og me</code> or <code>og keys list</code></span>
        </div>
      </div>
    </body>
    </html>
    """#
}
