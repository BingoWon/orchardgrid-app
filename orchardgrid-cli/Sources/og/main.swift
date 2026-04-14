// ============================================================================
// og — OrchardGrid CLI for Apple Intelligence
//
// Inference (default):  runs FoundationModels directly in-process.
// Management (login, keys, logs, devices): talks to orchardgrid.com / local
// dev server via HTTPS, authenticated with a token from `og login`.
//
// This file is deliberately thin: argument parsing, top-level dispatch, and
// `printUsage`. Every command implementation lives in `ogKit`:
//   • Inference.swift      runModelInfo / runPrompt / runChat
//   • AuthCommands.swift   runLogin / runLogout
//   • MgmtCommands.swift   runMe / runKeys* / runDevicesList / runLogsList
// ============================================================================

import Foundation
import ogKit

// MARK: - Parse

let rawArgs = Array(CommandLine.arguments.dropFirst())
let env = ProcessInfo.processInfo.environment

var args: Arguments
do {
  args = try parseArguments(rawArgs, env: env)
} catch let error as CLIError {
  printErr("error: \(error.description)")
  printUsage()
  exit(ExitCode.usage.rawValue)
} catch {
  printErr("error: \(error.localizedDescription)")
  exit(ExitCode.runtime.rawValue)
}

// Persisted creds, read lazily — ONLY by management subcommands. We never
// assign them onto `args.host`/`args.token`, so `og "hi"` after login still
// runs on-device rather than being silently redirected through HTTP.
let persistedConfig = ConfigStore.load(env: env)

noColor = args.noColor

switch args.mode {
case .help:
  printUsage()
  exit(ExitCode.success.rawValue)
case .version:
  print("og v\(ogVersion)")
  exit(ExitCode.success.rawValue)
default: break
}

// MARK: - Dispatch

do {
  switch args.mode {

  // ── inference / info ────────────────────────────────────────────
  case .modelInfo:
    let engine = try EngineFactory.make(host: args.host, token: args.token)
    try await runModelInfo(engine: engine)

  case .chat:
    let engine = try EngineFactory.make(host: args.host, token: args.token)
    try await runChat(
      engine: engine, args: args, systemPrompt: resolveSystemPrompt(args))

  case .run:
    let prompt = try assemblePrompt(args)
    guard !prompt.isEmpty else {
      printUsage()
      exit(ExitCode.usage.rawValue)
    }
    let engine = try EngineFactory.make(host: args.host, token: args.token)
    try await runPrompt(
      engine: engine, args: args, prompt: prompt,
      systemPrompt: resolveSystemPrompt(args))

  // ── local snapshot ──────────────────────────────────────────────
  case .status:
    runStatus(config: persistedConfig)

  // ── auth ────────────────────────────────────────────────────────
  case .login:
    try await runLogin(args: args)
  case .logout:
    try await runLogout(revoke: args.logoutRevoke)

  // ── management ──────────────────────────────────────────────────
  case .me:
    try await runMe(client: try cloudClient(args: args, config: persistedConfig))
  case .keysList:
    try await runKeysList(
      client: try cloudClient(args: args, config: persistedConfig))
  case .keysCreate:
    try await runKeysCreate(
      client: try cloudClient(args: args, config: persistedConfig),
      name: args.keyName)
  case .keysDelete:
    try await runKeysDelete(
      client: try cloudClient(args: args, config: persistedConfig),
      hint: args.keyHint ?? "")
  case .devicesList:
    try await runDevicesList(
      client: try cloudClient(args: args, config: persistedConfig))
  case .logsList:
    try await runLogsList(
      client: try cloudClient(args: args, config: persistedConfig),
      role: args.logRole, status: args.logStatus,
      limit: args.logLimit, offset: args.logOffset)

  case .help, .version:
    break  // handled above
  }
  exit(ExitCode.success.rawValue)
} catch let og as OGError {
  printErr("\(og.label) \(og.message)")
  exit(og.exitCode)
} catch {
  printErr("error: \(error.localizedDescription)")
  exit(ExitCode.runtime.rawValue)
}

// MARK: - Usage

func printUsage() {
  print(
    """
    \(styled("og", .cyan, .bold)) v\(ogVersion) — OrchardGrid CLI for Apple Intelligence

    \(styled("INFERENCE (on-device by default):", .yellow, .bold))
      og [OPTIONS] <prompt>         Send a single prompt
      og --chat                     Interactive REPL
      og --model-info               Print model info
      og -f <file> [prompt]         Attach file content
      echo "..." | og               Read prompt from stdin

    \(styled("LOCAL SNAPSHOT:", .yellow, .bold))
      og status                     Show app/CLI state (local server, login, capabilities)

    \(styled("AUTH (logs in to orchardgrid.com):", .yellow, .bold))
      og login                      Open browser, authorize this CLI
      og logout [--revoke]          Drop local creds; --revoke also kills the remote token

    \(styled("ACCOUNT:", .yellow, .bold))
      og me                         Print account info
      og keys                       List API keys
      og keys list                  Same
      og keys create [--name N]     Create a new inference API key
      og keys delete <hint>         Revoke an API key
      og devices                    List your devices
      og logs [--role R] [--status S] [--limit N] [--offset M]
                                    View usage logs

    \(styled("OPTIONS:", .yellow, .bold))
      -f, --file <path>             Attach file content (repeatable)
      -s, --system <text>           System prompt
          --system-file <path>      System prompt from file
      -o, --output <plain|json>     Output format [default: plain]
      -q, --quiet                   Suppress chrome
          --no-color                Disable ANSI color
          --temperature <n>         Sampling temperature
          --max-tokens <n>          Max response tokens
          --seed <n>                Random seed
          --context-strategy <s>    newest-first | oldest-first | sliding-window | strict
          --context-max-turns <n>   Max turns for sliding-window
          --permissive              Permissive content guardrails
          --host <url>              Remote OrchardGrid host (default: on-device / saved from login)
          --token <secret>          Bearer token (default: saved from login)
          --role <r>                consumer | provider | self (logs filter)
          --status <s>              Status filter (logs)
          --limit <n>               Page size (logs)
          --offset <n>              Page offset (logs)
          --name <text>             Name for `og keys create`
          --revoke                  With `og logout`: also revoke server-side
      -h, --help                    Show this help
      -v, --version                 Print version

    \(styled("ENVIRONMENT:", .yellow, .bold))
      ORCHARDGRID_HOST              Default remote host
      ORCHARDGRID_TOKEN             Default Bearer token
      OG_NO_BROWSER                 Suppress browser auto-launch in `og login` (for SSH / CI)
      NO_COLOR                      Disable colored output

    \(styled("EXIT CODES:", .yellow, .bold))
      0 success · 1 runtime · 2 usage · 3 guardrail · 4 context overflow ·
      5 model unavailable · 6 rate limited

    \(styled("EXAMPLES:", .yellow, .bold))
      og "What is the capital of Austria?"
      og --chat
      og login
      og keys list
      og keys create --name "my-bot"
      og logs --role self --limit 10
      og logout --revoke
      og --host https://orchardgrid.com "hello"
    """)
}
