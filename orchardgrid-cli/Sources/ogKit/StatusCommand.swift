import Foundation

// MARK: - og status
//
// One-shot snapshot covering everything the user might want to know
// before running an actual command:
//   • Is OrchardGrid.app running with Local Sharing on? On what port?
//   • Is Cloud Sharing on?
//   • Am I logged in to the cloud (CLI token)?
//   • Where does that token live?
//
// All inputs are local — App Group UserDefaults (state owned by the
// GUI app) + ~/.config/orchardgrid/config.json (state owned by `og
// login`). No network calls.

public func runStatus(config: ConfigFile?) {
  print(styled("OrchardGrid status", .cyan, .bold))
  print(styled(String(repeating: "─", count: 48), .dim))

  // ── Local sharing (from GUI app via App Group) ──────────────────
  let running = SharedDefaults.localRunning
  let enabled = SharedDefaults.localEnabled
  let port = SharedDefaults.localPort

  let localStatus: String
  let localStyle: [Style]
  if running, let port {
    localStatus = "running · http://127.0.0.1:\(port)"
    localStyle = [.green]
  } else if enabled {
    localStatus = "enabled but not running (open OrchardGrid.app)"
    localStyle = [.yellow]
  } else {
    localStatus = "off"
    localStyle = [.dim]
  }
  printRow(
    "local sharing",
    ANSI.apply(
      localStatus, styles: localStyle,
      enabled: !noColor && isatty(STDOUT_FILENO) != 0))

  // ── Cloud sharing ───────────────────────────────────────────────
  let cloud = SharedDefaults.cloudEnabled ? "on" : "off"
  let cloudStyle: [Style] = SharedDefaults.cloudEnabled ? [.green] : [.dim]
  printRow(
    "cloud sharing",
    ANSI.apply(
      cloud, styles: cloudStyle,
      enabled: !noColor && isatty(STDOUT_FILENO) != 0))

  // ── Capabilities ────────────────────────────────────────────────
  let caps = SharedDefaults.enabledCapabilities
  printRow(
    "capabilities",
    caps.isEmpty ? styled("(none)", .dim) : caps.joined(separator: ", "))

  // ── CLI auth ────────────────────────────────────────────────────
  if let config {
    let host = config.host
    let label = config.deviceLabel
    printRow(
      "logged in",
      styled("yes", .green) + " · \(label) → \(host)")
    printRow(
      "config file",
      styled(ConfigStore.path().path, .dim))
  } else {
    printRow("logged in", styled("no", .dim) + " · run `og login`")
  }

  // ── Hint when App Group is unavailable ──────────────────────────
  if SharedDefaults.store == nil {
    print()
    print(
      styled(
        "(App Group container unavailable — install via `brew install --cask "
          + "orchardgrid` or `make bundle-cli` to read live app state)",
        .dim))
  }
}

private func printRow(_ label: String, _ value: String) {
  print("\(styled(pad(label, 16), .dim)) \(value)")
}
