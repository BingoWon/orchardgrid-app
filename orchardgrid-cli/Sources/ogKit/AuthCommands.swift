import Darwin
import Foundation

// MARK: - Auth commands
//
// `og login`: browser-loopback OAuth dance that mints a long-lived,
// management-scoped API key server-side and stashes it in `~/.config/
// orchardgrid/config.json`.
//
// `og logout` (with optional `--revoke`): drop local creds, optionally
// also `DELETE /api/api-keys/<hint>` to kill the server-side record.

// MARK: - Build-time default host

/// Default cloud host when neither `--host`, `ORCHARDGRID_HOST`, nor the
/// saved config file is set. Mirrors the native app's `Debug.xcconfig` /
/// `Release.xcconfig` split: debug builds (`swift build`, `make build`)
/// target the local dev worker; release builds (`swift build -c release`,
/// `make install`) target production.
///
/// Implemented as a function — not a top-level `let` — to work around a
/// Swift 6.2 initialization-order bug where a top-level `#if DEBUG`
/// binding is observed as `<uninitialized>` from inside async functions.
public func defaultCloudHost() -> String {
  #if DEBUG
    return "http://localhost:4399"
  #else
    return "https://orchardgrid.com"
  #endif
}

// MARK: - Device label

/// Pretty device label for `og login`. Uses POSIX `gethostname(3)` directly
/// — bypassing `Host.current()` / `ProcessInfo.hostName` which both route
/// through `NSHost` + mDNS on macOS and deadlock under Swift 6 strict
/// concurrency on macOS 26 (lldb backtrace shows many threads stuck in
/// `mdns_hostbyaddr` on `__psynch_mutexwait`).
public func deviceDisplayName() -> String {
  var buf = [CChar](repeating: 0, count: 256)
  guard gethostname(&buf, buf.count) == 0 else { return "Mac" }
  return String(cString: buf).replacingOccurrences(of: ".local", with: "")
}

// MARK: - og login

public func runLogin(host customHost: String?) async throws {
  let host = customHost ?? defaultCloudHost()
  let deviceLabel = deviceDisplayName()

  let result = try await LoginFlow.run(host: host, deviceLabel: deviceLabel)
  let config = ConfigFile(
    host: result.host,
    token: result.token,
    keyHint: String(result.token.prefix(20)) + "…",
    deviceLabel: result.deviceLabel
  )
  try ConfigStore.save(config)
  print(styled("✓ logged in", .green) + " as \(deviceLabel)")
  print(styled("  token saved to \(ConfigStore.path().path)", .dim))
}

// MARK: - og logout [--revoke]

public func runLogout(revoke: Bool) async throws {
  let config = ConfigStore.load()

  // Always try to revoke first (if requested) — we want the remote kill
  // to happen before the local file is gone, so an error surfaces a
  // useful hint ("your token is already invalid? log in again to revoke").
  if revoke {
    guard let config else {
      printErr("(not logged in, nothing to revoke)")
      return
    }
    do {
      let api = try CloudAPI(host: config.host, token: config.token)
      try await api.deleteAPIKey(hint: config.keyHint)
      print(styled("✓ revoked", .green) + " \(config.keyHint)")
    } catch let og as OGError {
      // Revocation failed — still drop the local file below; at least the
      // user can't accidentally keep using a key they meant to kill.
      printErr("\(og.label) revocation failed: \(og.message)")
    }
  }

  if ConfigStore.delete() {
    print(styled("✓ logged out", .green))
  } else if !revoke {
    // Only show this when plain `og logout` had nothing to do. After
    // `og logout --revoke` with a config, we already printed "✓ revoked".
    printErr("(not logged in)")
  }
}
