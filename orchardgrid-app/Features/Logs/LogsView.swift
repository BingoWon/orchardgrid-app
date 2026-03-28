import SwiftUI

struct LogsView: View {
  @Environment(AuthManager.self) private var authManager
  @Environment(LogsManager.self) private var manager
  @Environment(ObserverClient.self) private var observerClient
  @State private var statusFilter = "all"
  @State private var roleFilter = "all"
  @State private var pageSize = 50
  @State private var page = 1

  private let statusOptions = ["all", "completed", "failed", "processing", "pending"]

  var body: some View {
    ScrollView {
      GlassEffectContainer(spacing: Constants.standardSpacing) {
        VStack(alignment: .leading, spacing: Constants.standardSpacing) {
          if authManager.isAuthenticated {
            authenticatedContent
          } else {
            GuestFeaturePrompt(
              icon: "list.bullet.rectangle",
              title: "View Logs",
              description: "Sign in to see your complete activity log.",
              benefits: [
                "Track consumer, provider, and self requests",
                "Filter by status and role",
                "Monitor token usage and performance",
              ],
              buttonTitle: "Sign In to View Logs"
            )
          }
        }
        .padding(Constants.standardPadding)
      }
    }
    .refreshable {
      await loadData(isManualRefresh: true)
    }
    .navigationTitle(String(localized: "Logs"))
    .toolbarRole(.editor)
    .toolbarTitleDisplayMode(.inlineLarge)
    .contentToolbar {
      if authManager.isAuthenticated {
        refreshButton
      }
    }
    .task(id: authManager.userId) {
      await loadData()
    }
  }

  // MARK: - Authenticated Content

  @ViewBuilder
  private var authenticatedContent: some View {
    HStack {
      ConnectionStatusBadge(isConnected: observerClient.status == .connected)
      Spacer()
      if !manager.isInitialLoading {
        LastUpdatedView(lastUpdatedText: manager.lastUpdatedText)
      }
    }

    if manager.isInitialLoading {
      ProgressView()
        .frame(maxWidth: .infinity)
        .padding(.vertical, 60)
    } else if let error = manager.lastError {
      ErrorBanner(message: error) {
        Task { await loadData(isManualRefresh: true) }
      }
    } else {
      filtersBar
      logsList
    }
  }

  // MARK: - Filters

  private var filtersBar: some View {
    HStack(spacing: 8) {
      Picker(String(localized: "Status"), selection: $statusFilter) {
        ForEach(statusOptions, id: \.self) { s in
          Text(s == "all" ? String(localized: "All") : s.capitalized).tag(s)
        }
      }
      .labelsHidden()
      .fixedSize()
      #if os(macOS)
        .frame(width: 120)
      #endif

      Picker(String(localized: "Role"), selection: $roleFilter) {
        Text(String(localized: "All")).tag("all")
        ForEach(LogRole.allCases, id: \.self) { r in
          Text(r.label).tag(r.rawValue)
        }
      }
      .labelsHidden()
      .fixedSize()
      #if os(macOS)
        .frame(width: 120)
      #endif

      Spacer()

      Text(
        String(
          localized: "\(manager.total) logs",
          comment: "Total log count label"
        )
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      .monospacedDigit()
    }
    .onChange(of: statusFilter) {
      page = 1
      Task { await loadData() }
    }
    .onChange(of: roleFilter) {
      page = 1
      Task { await loadData() }
    }
  }

  // MARK: - Logs List

  @ViewBuilder
  private var logsList: some View {
    if manager.logs.isEmpty {
      ContentUnavailableView(
        String(localized: "No Logs Found"),
        systemImage: "tray",
        description: Text(String(localized: "Logs will appear here once activity is recorded"))
      )
      .frame(maxWidth: .infinity)
    } else {
      #if os(macOS)
        logsTable
      #else
        if UIDevice.current.userInterfaceIdiom == .pad {
          logsTable
        } else {
          logsCompactList
        }
      #endif

      paginationBar
    }
  }

  // MARK: - Table (macOS + iPad)

  private var logsTable: some View {
    Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 0) {
      GridRow {
        Text("").frame(width: 16)  // status icon
        Text(String(localized: "Role")).fontWeight(.medium)
        Text(String(localized: "Capability")).fontWeight(.medium)
        Text(String(localized: "Device")).fontWeight(.medium)
        Text(String(localized: "Duration")).fontWeight(.medium)
        Text(String(localized: "Tokens")).fontWeight(.medium)
        Text(String(localized: "Time")).fontWeight(.medium)
      }
      .font(.caption2)
      .foregroundStyle(.secondary)
      .padding(.vertical, 6)

      Divider()

      ForEach(manager.logs) { log in
        GridRow {
          statusIcon(log)
          roleBadge(log.role)
          Text(log.capability ?? "—")
            .font(.caption2)
          Text(log.deviceId.map { String($0.prefix(8)) } ?? "—")
            .font(.caption2)
            .monospaced()
          Text(log.durationText)
            .font(.caption2)
            .monospaced()
          Text(log.tokensText)
            .font(.caption2)
            .monospaced()
          Text(log.createdDate, format: .dateTime.month().day().hour().minute())
            .font(.caption2)
        }
        .padding(.vertical, 4)

        Divider()
      }
    }
    .padding(12)
    .background(
      .ultraThinMaterial, in: .rect(cornerRadius: Constants.cornerRadius, style: .continuous))
  }

  // MARK: - Compact List (iPhone)

  private var logsCompactList: some View {
    VStack(spacing: 0) {
      ForEach(manager.logs) { log in
        LogRow(log: log)
        Divider().padding(.leading, 24)
      }
    }
    .padding(.vertical, 4)
    .background(
      .ultraThinMaterial, in: .rect(cornerRadius: Constants.cornerRadius, style: .continuous))
  }

  // MARK: - Status Icon

  private func statusIcon(_ log: LogEntry) -> some View {
    Group {
      switch log.status {
      case "completed":
        Image(systemName: "checkmark.circle.fill")
          .foregroundStyle(.green)
      case "failed":
        Image(systemName: "xmark.circle.fill")
          .foregroundStyle(.red)
      case "processing":
        Image(systemName: "circle.fill")
          .foregroundStyle(.orange)
      default:
        Image(systemName: "circle.dashed")
          .foregroundStyle(.gray)
      }
    }
    .font(.caption2)
    .frame(width: 16)
  }

  // MARK: - Role Badge

  private func roleBadge(_ role: LogRole?) -> some View {
    Group {
      if let role {
        Text(role.label)
          .font(.caption2)
          .padding(.horizontal, 5)
          .padding(.vertical, 1)
          .background(Color(role.color).opacity(0.15), in: Capsule())
          .foregroundStyle(Color(role.color))
      } else {
        Text("—").font(.caption2)
      }
    }
  }

  // MARK: - Pagination

  private var paginationBar: some View {
    HStack {
      Text(
        String(
          localized:
            "\((page - 1) * pageSize + 1)–\(min(page * pageSize, manager.total)) of \(manager.total)",
          comment: "Pagination range"
        )
      )
      .font(.caption)
      .foregroundStyle(.secondary)

      Spacer()

      HStack(spacing: 8) {
        Button {
          page = max(1, page - 1)
          Task { await loadData() }
        } label: {
          Image(systemName: "chevron.left")
        }
        .disabled(page == 1)

        Text("\(page)/\(totalPages)")
          .font(.caption)
          .monospacedDigit()

        Button {
          page = min(totalPages, page + 1)
          Task { await loadData() }
        } label: {
          Image(systemName: "chevron.right")
        }
        .disabled(page >= totalPages)
      }
      .buttonStyle(.plain)
    }
    .padding(.top, 6)
  }

  // MARK: - Refresh

  private var refreshButton: some View {
    Button {
      Task { await loadData(isManualRefresh: true) }
    } label: {
      Image(systemName: "arrow.clockwise")
        .symbolEffect(.rotate, isActive: manager.isRefreshing)
    }
    .disabled(manager.isRefreshing)
  }

  // MARK: - Helpers

  private var totalPages: Int {
    max(1, Int(ceil(Double(manager.total) / Double(pageSize))))
  }

  private func loadData(isManualRefresh: Bool = false) async {
    guard let token = await authManager.getToken() else { return }
    let offset = (page - 1) * pageSize
    await manager.loadLogs(
      limit: pageSize,
      offset: offset,
      status: statusFilter == "all" ? nil : statusFilter,
      role: roleFilter == "all" ? nil : roleFilter,
      authToken: token,
      isManualRefresh: isManualRefresh
    )
  }
}

// MARK: - Compact Log Row (iPhone)

private struct LogRow: View {
  let log: LogEntry

  var body: some View {
    HStack(spacing: 6) {
      // Status icon
      statusIcon
        .frame(width: 16)

      // Role capsule
      if let role = log.role {
        Text(role.label)
          .font(.system(size: 9, weight: .medium))
          .padding(.horizontal, 4)
          .padding(.vertical, 1)
          .background(Color(role.color).opacity(0.15), in: Capsule())
          .foregroundStyle(Color(role.color))
          .fixedSize()
      }

      // Capability
      if let cap = log.capability {
        Text(cap)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer(minLength: 4)

      // Duration
      Text(log.durationText)
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(.secondary)

      // Tokens (compact)
      if let p = log.promptTokens, let c = log.completionTokens {
        Text("\(p + c)t")
          .font(.system(size: 10, design: .monospaced))
          .foregroundStyle(.tertiary)
      }

      // Time
      Text(log.createdDate, format: .dateTime.hour().minute())
        .font(.system(size: 10))
        .foregroundStyle(.tertiary)
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
  }

  @ViewBuilder
  private var statusIcon: some View {
    switch log.status {
    case "completed":
      Image(systemName: "checkmark.circle.fill")
        .foregroundStyle(.green)
        .font(.system(size: 12))
    case "failed":
      Image(systemName: "xmark.circle.fill")
        .foregroundStyle(.red)
        .font(.system(size: 12))
    case "processing":
      Image(systemName: "circle.fill")
        .foregroundStyle(.orange)
        .font(.system(size: 12))
    default:
      Image(systemName: "circle.dashed")
        .foregroundStyle(.gray)
        .font(.system(size: 12))
    }
  }
}

#Preview {
  LogsView()
    .environment(AuthManager())
    .environment(LogsManager())
    .environment(ObserverClient())
}
