import Foundation

// MARK: - Management commands (talk to /api/* via CloudAPI)
//
// `og me / keys / devices / logs`. All require a management-scope token;
// the token + host come from CLI flags, env vars, or the saved config —
// resolved by `resolveManagement`.

public func cloudClient(
  host explicitHost: String?,
  token explicitToken: String?,
  config: ConfigFile?
) throws -> CloudAPI {
  let (host, token) = resolveManagement(
    host: explicitHost, token: explicitToken,
    config: config, defaultHost: defaultCloudHost())
  guard let token, !token.isEmpty else {
    throw OGError.runtime("not logged in — run `og login`")
  }
  return try CloudAPI(host: host, token: token)
}

// MARK: - og me

public func runMe(client: CloudAPI) async throws {
  let me = try await client.me()
  print("\(styled("user:", .dim)) \(me.id)")
  print("\(styled("admin:", .dim)) \(me.isAdmin ? "yes" : "no")")
}

// MARK: - og keys

public func runKeysList(client: CloudAPI) async throws {
  let keys = try await client.listAPIKeys()
  if keys.isEmpty {
    print(styled("(no API keys)", .dim))
    return
  }
  let nameWidth = max(4, keys.compactMap { $0.name?.count }.max() ?? 0)
  let hintWidth = max(6, keys.map { $0.keyHint.count }.max() ?? 0)
  print(
    "\(pad("SCOPE", 11)) \(pad("NAME", nameWidth)) \(pad("HINT", hintWidth))  LAST USED"
  )
  for key in keys {
    let scope = key.scope ?? "inference"
    let name = key.name ?? "—"
    let lastUsed = key.lastUsedAt.map(formatTimestamp) ?? "—"
    let scopeText = ANSI.apply(
      pad(scope, 11),
      styles: scope == "management" ? [.cyan] : [.dim],
      enabled: !noColor && isatty(STDOUT_FILENO) != 0)
    print(
      "\(scopeText) \(pad(name, nameWidth)) \(pad(key.keyHint, hintWidth))  \(lastUsed)"
    )
  }
}

public func runKeysCreate(client: CloudAPI, name: String?) async throws {
  let created = try await client.createAPIKey(
    name: name, scope: "inference", deviceLabel: nil)
  guard let plaintext = created.key else {
    throw OGError.runtime("server did not return a plaintext key")
  }
  print(styled("✓ key created", .green) + " (scope: inference)")
  print("  name:  \(created.name ?? "—")")
  print("  hint:  \(created.keyHint)")
  print()
  print(styled("  Save this key — you won't see it again:", .yellow, .bold))
  print("  \(plaintext)")
}

public func runKeysDelete(client: CloudAPI, hint: String) async throws {
  guard !hint.isEmpty else {
    throw OGError.usage("missing key hint (try `og keys list`)")
  }
  try await client.deleteAPIKey(hint: hint)
  print(styled("✓ deleted", .green) + " \(hint)")
}

// MARK: - og devices

public func runDevicesList(client: CloudAPI) async throws {
  let devices = try await client.listDevices()
  if devices.isEmpty {
    print(styled("(no devices)", .dim))
    return
  }
  let nameWidth = max(4, devices.compactMap { $0.deviceName?.count }.max() ?? 0)
  print(
    "\(pad("STATUS", 7)) \(pad("PLATFORM", 8)) \(pad("NAME", nameWidth)) \(pad("CHIP", 14)) LOGS"
  )
  for d in devices {
    let statusStyle: [Style] = d.isOnline ? [.green] : [.dim]
    let statusText = ANSI.apply(
      pad(d.isOnline ? "online" : "offline", 7),
      styles: statusStyle,
      enabled: !noColor && isatty(STDOUT_FILENO) != 0)
    print(
      "\(statusText) \(pad(d.platform, 8)) \(pad(d.deviceName ?? "—", nameWidth)) \(pad(d.chipModel ?? "—", 14)) \(d.logsProcessed)"
    )
  }
}

// MARK: - og logs

public func runLogsList(
  client: CloudAPI, role: String?, status: String?, limit: Int, offset: Int
) async throws {
  let page = try await client.logs(
    limit: limit, offset: offset, role: role, status: status)
  if page.logs.isEmpty {
    print(styled("(no logs)", .dim))
    return
  }
  print(
    "\(pad("WHEN", 19)) \(pad("STATUS", 10)) \(pad("CAPABILITY", 10)) \(pad("ROLE", 8)) TOKENS"
  )
  for log in page.logs {
    let when = formatTimestamp(log.createdAt)
    let statusStyle: [Style] =
      log.status == "completed"
      ? [.green] : log.status == "failed" ? [.red] : [.yellow]
    let statusText = ANSI.apply(
      pad(log.status, 10), styles: statusStyle,
      enabled: !noColor && isatty(STDOUT_FILENO) != 0)
    let tokens = "\(log.promptTokens ?? 0)→\(log.completionTokens ?? 0)"
    print(
      "\(pad(when, 19)) \(statusText) \(pad(log.capability ?? "—", 10)) \(pad(log.role ?? "—", 8)) \(tokens)"
    )
  }
  if page.total > page.logs.count {
    print(
      styled(
        "\n(\(page.logs.count) of \(page.total); --offset \(offset + limit) for next page)",
        .dim))
  }
}
