import Foundation
import Testing

@testable import ogKit

@Suite("Config store")
struct ConfigTests {

  /// Use a scratch HOME for each test so we don't touch the user's real
  /// `~/.config/orchardgrid/config.json`.
  private func scratchEnv() -> (env: [String: String], cleanup: () -> Void) {
    let tmp = FileManager.default.temporaryDirectory
      .appendingPathComponent("og-test-\(UUID().uuidString)", isDirectory: true)
    try! FileManager.default.createDirectory(
      at: tmp, withIntermediateDirectories: true)
    let env = ["HOME": tmp.path]
    return (
      env,
      {
        try? FileManager.default.removeItem(at: tmp)
      }
    )
  }

  @Test("path honours HOME env var")
  func pathRespectsHome() {
    let url = ConfigStore.path(env: ["HOME": "/tmp/anywhere"])
    #expect(url.path == "/tmp/anywhere/.config/orchardgrid/config.json")
  }

  @Test("load returns nil when no config file exists")
  func loadNilWhenAbsent() {
    let (env, cleanup) = scratchEnv()
    defer { cleanup() }
    #expect(ConfigStore.load(env: env) == nil)
  }

  @Test("save writes file with 0600 perms; load round-trips")
  func saveLoadRoundtrip() throws {
    let (env, cleanup) = scratchEnv()
    defer { cleanup() }

    let original = ConfigFile(
      host: "https://orchardgrid.com",
      token: "ogk_secret_abc",
      keyHint: "sk-orchardgrid-a…",
      deviceLabel: "MyMac"
    )
    try ConfigStore.save(original, env: env)

    let loaded = ConfigStore.load(env: env)
    #expect(loaded == original)

    let attrs = try FileManager.default.attributesOfItem(
      atPath: ConfigStore.path(env: env).path)
    let perms = (attrs[.posixPermissions] as? NSNumber)?.intValue ?? 0
    #expect(perms == 0o600)
  }

  @Test("delete removes file and reports whether it existed")
  func deleteRemoves() throws {
    let (env, cleanup) = scratchEnv()
    defer { cleanup() }

    #expect(ConfigStore.delete(env: env) == false)  // absent

    let cfg = ConfigFile(
      host: "http://127.0.0.1:4399",
      token: "t",
      keyHint: "t…",
      deviceLabel: "test"
    )
    try ConfigStore.save(cfg, env: env)
    #expect(ConfigStore.load(env: env) != nil)

    #expect(ConfigStore.delete(env: env) == true)
    #expect(ConfigStore.load(env: env) == nil)
  }

  // MARK: - resolveManagement

  @Test("resolveManagement falls back to config when args are empty")
  func resolveUsesConfig() {
    let args = Arguments()
    let cfg = ConfigFile(
      host: "http://saved:4399", token: "saved-tok",
      keyHint: "…", deviceLabel: "x")
    let resolved = resolveManagement(
      args: args, config: cfg, defaultHost: "https://default.com")
    #expect(resolved.host == "http://saved:4399")
    #expect(resolved.token == "saved-tok")
  }

  @Test("resolveManagement prefers explicit --host/--token over config")
  func resolveExplicitWins() {
    var args = Arguments()
    args.host = "http://explicit:9000"
    args.token = "explicit-tok"
    let cfg = ConfigFile(
      host: "http://saved:4399", token: "saved-tok",
      keyHint: "…", deviceLabel: "x")
    let resolved = resolveManagement(
      args: args, config: cfg, defaultHost: "https://default.com")
    #expect(resolved.host == "http://explicit:9000")
    #expect(resolved.token == "explicit-tok")
  }

  @Test("resolveManagement falls back to defaultHost when neither args nor config set it")
  func resolveUsesDefault() {
    let args = Arguments()
    let resolved = resolveManagement(
      args: args, config: nil, defaultHost: "https://default.com")
    #expect(resolved.host == "https://default.com")
    #expect(resolved.token == nil)
  }

  @Test("resolveManagement does NOT modify the inference args (host/token stay nil)")
  func resolveDoesNotMutateArgs() {
    let args = Arguments()
    let cfg = ConfigFile(
      host: "http://saved:4399", token: "tok",
      keyHint: "…", deviceLabel: "x")
    _ = resolveManagement(args: args, config: cfg, defaultHost: "x")
    // The inference path still sees nil host → LocalEngine (on-device).
    #expect(args.host == nil)
    #expect(args.token == nil)
  }
}
