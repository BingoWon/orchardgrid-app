import Foundation

// MARK: - Persisted Config

/// Persistent configuration written to `~/.config/orchardgrid/config.json`
/// after `og login`. Read on every CLI invocation to fill in `--host` and
/// `--token` when the user hasn't specified them explicitly.
public struct ConfigFile: Codable, Sendable, Equatable {
  public var host: String
  public var token: String
  public var keyHint: String
  public var deviceLabel: String

  public init(host: String, token: String, keyHint: String, deviceLabel: String) {
    self.host = host
    self.token = token
    self.keyHint = keyHint
    self.deviceLabel = deviceLabel
  }
}

// MARK: - Store

public enum ConfigStore {
  /// `~/.config/orchardgrid/config.json`. Expressed via `$HOME` so tests can
  /// override via `HOME=/tmp/og-test`.
  public static func path(env: [String: String] = ProcessInfo.processInfo.environment) -> URL {
    let home =
      env["HOME"].map { URL(fileURLWithPath: $0) } ?? URL(fileURLWithPath: NSHomeDirectory())
    return
      home
      .appendingPathComponent(".config", isDirectory: true)
      .appendingPathComponent("orchardgrid", isDirectory: true)
      .appendingPathComponent("config.json")
  }

  public static func load(env: [String: String] = ProcessInfo.processInfo.environment)
    -> ConfigFile?
  {
    let url = path(env: env)
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(ConfigFile.self, from: data)
  }

  /// Write the config. Creates `~/.config/orchardgrid/` if missing and
  /// chmod's the file to 0600 — this file contains a long-lived token.
  public static func save(
    _ config: ConfigFile,
    env: [String: String] = ProcessInfo.processInfo.environment
  ) throws {
    let url = path(env: env)
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(),
      withIntermediateDirectories: true,
      attributes: [.posixPermissions: 0o700]
    )
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    let data = try encoder.encode(config)
    try data.write(to: url, options: [.atomic])
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600], ofItemAtPath: url.path)
  }

  @discardableResult
  public static func delete(env: [String: String] = ProcessInfo.processInfo.environment) -> Bool {
    let url = path(env: env)
    guard FileManager.default.fileExists(atPath: url.path) else { return false }
    try? FileManager.default.removeItem(at: url)
    return true
  }
}

// MARK: - Resolution

/// Resolve the **management-plane** host + token that `/api/*` subcommands
/// should talk to. Priority (highest first):
///   1. Explicit `--host` / `--token` / env vars (already on `args`)
///   2. Saved `~/.config/orchardgrid/config.json`
///   3. Built-in default (host only — no token)
///
/// Note: this is *only* used by management subcommands (`me`, `keys`,
/// `devices`, `logs`). Inference (`run`, `chat`, `modelInfo`) intentionally
/// does **not** read config.host — saved creds shouldn't silently redirect
/// on-device inference to HTTP.
public func resolveManagement(
  host explicitHost: String?,
  token explicitToken: String?,
  config: ConfigFile?,
  defaultHost: String
) -> (host: String, token: String?) {
  let host = explicitHost ?? config?.host ?? defaultHost
  let token = explicitToken ?? config?.token
  return (host, token)
}
