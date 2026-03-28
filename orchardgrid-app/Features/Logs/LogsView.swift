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
  private let roleOptions = ["all", "sent", "served", "local"]

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
                "Track requests sent, served, and local",
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
    HStack(spacing: 12) {
      Picker(String(localized: "Status"), selection: $statusFilter) {
        ForEach(statusOptions, id: \.self) { s in
          Text(s == "all" ? String(localized: "All Status") : s.capitalized).tag(s)
        }
      }
      .labelsHidden()
      #if os(macOS)
        .frame(width: 130)
      #endif

      Picker(String(localized: "Role"), selection: $roleFilter) {
        Text(String(localized: "All Roles")).tag("all")
        ForEach(LogRole.allCases, id: \.self) { r in
          Text(r.label).tag(r.rawValue)
        }
      }
      .labelsHidden()
      #if os(macOS)
        .frame(width: 110)
      #endif

      Spacer()

      Text("\(manager.total) logs")
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
          logsCards
        }
      #endif

      paginationBar
    }
  }

  // MARK: - Table (macOS + iPad)

  private var logsTable: some View {
    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 0) {
      // Header
      GridRow {
        Text(String(localized: "Status")).fontWeight(.medium)
        Text(String(localized: "Role")).fontWeight(.medium)
        Text(String(localized: "Capability")).fontWeight(.medium)
        Text(String(localized: "Device")).fontWeight(.medium)
        Text(String(localized: "Duration")).fontWeight(.medium)
        Text(String(localized: "Tokens")).fontWeight(.medium)
        Text(String(localized: "Time")).fontWeight(.medium)
      }
      .font(.caption)
      .foregroundStyle(.secondary)
      .padding(.vertical, 8)

      Divider()

      ForEach(manager.logs) { log in
        GridRow {
          statusBadge(log.status)
          roleBadge(log.role)
          Text(log.capability ?? "—")
            .font(.caption)
          Text(log.deviceId.map { String($0.prefix(8)) + "…" } ?? "—")
            .font(.caption)
            .monospaced()
          Text(log.durationText)
            .font(.caption)
            .monospaced()
          Text(log.tokensText)
            .font(.caption)
            .monospaced()
          Text(log.createdDate, format: .dateTime.month().day().hour().minute())
            .font(.caption)
        }
        .padding(.vertical, 6)

        Divider()
      }
    }
    .padding(Constants.standardPadding)
    .background(
      .ultraThinMaterial, in: .rect(cornerRadius: Constants.cornerRadius, style: .continuous))
  }

  // MARK: - Cards (iPhone)

  private var logsCards: some View {
    ForEach(manager.logs) { log in
      LogCard(log: log)
    }
  }

  // MARK: - Badges

  private func statusBadge(_ status: String) -> some View {
    HStack(spacing: 4) {
      Circle()
        .fill(statusColor(status))
        .frame(width: 7, height: 7)
      Text(status.capitalized)
        .font(.caption)
    }
  }

  private func roleBadge(_ role: LogRole?) -> some View {
    Group {
      if let role {
        Text(role.label)
          .font(.caption)
          .padding(.horizontal, 6)
          .padding(.vertical, 2)
          .background(roleColor(role).opacity(0.15), in: Capsule())
          .foregroundStyle(roleColor(role))
      } else {
        Text("—").font(.caption)
      }
    }
  }

  // MARK: - Pagination

  private var paginationBar: some View {
    HStack {
      Text(
        "\((page - 1) * pageSize + 1)-\(min(page * pageSize, manager.total)) of \(manager.total)"
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
    .padding(.top, 8)
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

  private func statusColor(_ status: String) -> Color {
    switch status {
    case "completed": .green
    case "failed": .red
    case "processing": .orange
    case "pending": .gray
    default: .gray
    }
  }

  private func roleColor(_ role: LogRole) -> Color {
    switch role {
    case .sent: .blue
    case .served: .purple
    case .local: .green
    }
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

// MARK: - Log Card (iPhone)

private struct LogCard: View {
  let log: ComputeTask

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      // Top row: Status + Role + Time
      HStack {
        HStack(spacing: 4) {
          Circle()
            .fill(statusColor)
            .frame(width: 8, height: 8)
          Text(log.status.capitalized)
            .font(.subheadline.weight(.medium))
        }

        if let role = log.role {
          Text(role.label)
            .font(.caption)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(roleColor.opacity(0.15), in: Capsule())
            .foregroundStyle(roleColor)
        }

        Spacer()

        Text(log.createdDate, format: .dateTime.month().day().hour().minute())
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      // Detail row
      HStack(spacing: 12) {
        if let cap = log.capability {
          Label(cap, systemImage: "cpu")
        }
        if let deviceId = log.deviceId {
          Label(String(deviceId.prefix(8)) + "…", systemImage: "desktopcomputer")
        }
        Label(log.durationText, systemImage: "clock")
      }
      .font(.caption)
      .foregroundStyle(.secondary)

      // Tokens row
      if log.promptTokens != nil || log.completionTokens != nil {
        Label(log.tokensText, systemImage: "number")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(12)
    .background(.ultraThinMaterial, in: .rect(cornerRadius: 12, style: .continuous))
  }

  private var statusColor: Color {
    switch log.status {
    case "completed": .green
    case "failed": .red
    case "processing": .orange
    case "pending": .gray
    default: .gray
    }
  }

  private var roleColor: Color {
    guard let role = log.role else { return .gray }
    switch role {
    case .sent: return .blue
    case .served: return .purple
    case .local: return .green
    }
  }
}

#Preview {
  LogsView()
    .environment(AuthManager())
    .environment(LogsManager())
    .environment(ObserverClient())
}
