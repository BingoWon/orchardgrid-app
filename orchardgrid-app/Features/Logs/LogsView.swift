import SwiftUI

private enum LogTab: Int {
  case consuming, providing
}

struct LogsView: View {
  @Environment(AuthManager.self) private var authManager
  @Environment(LogsManager.self) private var manager
  @Environment(ObserverClient.self) private var observerClient
  @State private var selectedTab = LogTab.consuming
  @State private var consumingStatus = "all"
  @State private var providingStatus = "all"
  @State private var consumingPageSize = 50
  @State private var providingPageSize = 50
  @State private var consumingPage = 1
  @State private var providingPage = 1

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
              title: "View Task History",
              description: "Sign in to see your complete task history with detailed logs.",
              benefits: [
                "View consuming and providing tasks",
                "Filter by status",
                "Track task duration and performance",
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
    .navigationTitle("Logs")
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
    } else if let error = manager.errorMessage {
      ErrorBanner(message: error) {
        Task { await loadData(isManualRefresh: true) }
      }
    } else {
      summaryCard
      tabSelector

      if selectedTab == .consuming {
        taskSection(
          title: "Consuming Tasks",
          tasks: manager.consumingTasks,
          total: manager.consumingTotal,
          status: $consumingStatus,
          page: $consumingPage,
          pageSize: consumingPageSize,
          totalPages: consumingTotalPages,
          onReload: { Task { await loadConsumingTasks() } }
        )
      } else {
        taskSection(
          title: "Providing Tasks",
          tasks: manager.providingTasks,
          total: manager.providingTotal,
          status: $providingStatus,
          page: $providingPage,
          pageSize: providingPageSize,
          totalPages: providingTotalPages,
          onReload: { Task { await loadProvidingTasks() } }
        )
      }
    }
  }

  // MARK: - Summary Card

  private var summaryCard: some View {
    VStack(alignment: .leading, spacing: Constants.summaryCardSpacing) {
      Text("Summary")
        .font(.headline)
        .foregroundStyle(.secondary)

      HStack(spacing: 16) {
        StatCard(title: "Consuming", value: "\(manager.consumingTotal)")
        StatCard(title: "Providing", value: "\(manager.providingTotal)")
        StatCard(
          title: "Total",
          value: "\(manager.consumingTotal + manager.providingTotal)"
        )
      }
    }
    .padding(Constants.standardPadding)
    .frame(maxWidth: .infinity, alignment: .leading)
    .glassEffect(in: .rect(cornerRadius: Constants.cornerRadius, style: .continuous))
  }

  // MARK: - Tab Selector

  private var tabSelector: some View {
    Picker("", selection: $selectedTab) {
      Text("Consuming").tag(LogTab.consuming)
      Text("Providing").tag(LogTab.providing)
    }
    .pickerStyle(.segmented)
  }

  // MARK: - Task Section

  @ViewBuilder
  private func taskSection(
    title: String,
    tasks: [ComputeTask],
    total: Int,
    status: Binding<String>,
    page: Binding<Int>,
    pageSize: Int,
    totalPages: Int,
    onReload: @escaping () -> Void
  ) -> some View {
    VStack(alignment: .leading, spacing: Constants.summaryCardSpacing) {
      // Header with Filter
      HStack {
        Text(title)
          .font(.headline)
          .foregroundStyle(.secondary)

        Spacer()

        Picker("Status", selection: status) {
          ForEach(statusOptions, id: \.self) { s in
            Text(s.capitalized).tag(s)
          }
        }
        .labelsHidden()
        .frame(width: 120)
        .onChange(of: status.wrappedValue) {
          page.wrappedValue = 1
          onReload()
        }
      }

      // Tasks
      if tasks.isEmpty {
        emptyTasksState
      } else {
        ForEach(tasks) { task in
          TaskCard(task: task)
        }

        // Pagination
        paginationBar(
          page: page,
          pageSize: pageSize,
          total: total,
          totalPages: totalPages,
          onReload: onReload
        )
      }
    }
  }

  // MARK: - Task Card

  // MARK: - Pagination

  private func paginationBar(
    page: Binding<Int>,
    pageSize: Int,
    total: Int,
    totalPages: Int,
    onReload: @escaping () -> Void
  ) -> some View {
    HStack {
      Text(
        "\((page.wrappedValue - 1) * pageSize + 1)-\(min(page.wrappedValue * pageSize, total)) of \(total)"
      )
      .font(.caption)
      .foregroundStyle(.secondary)

      Spacer()

      HStack(spacing: 8) {
        Button {
          page.wrappedValue = max(1, page.wrappedValue - 1)
          onReload()
        } label: {
          Image(systemName: "chevron.left")
        }
        .disabled(page.wrappedValue == 1)

        Text("\(page.wrappedValue)/\(totalPages)")
          .font(.caption)
          .monospacedDigit()

        Button {
          page.wrappedValue = min(totalPages, page.wrappedValue + 1)
          onReload()
        } label: {
          Image(systemName: "chevron.right")
        }
        .disabled(page.wrappedValue >= totalPages)
      }
      .buttonStyle(.plain)
    }
    .padding(.top, 8)
  }

  // MARK: - States

  private var emptyTasksState: some View {
    ContentUnavailableView(
      "No Tasks Found",
      systemImage: "tray",
      description: Text("Tasks will appear here once processed")
    )
    .frame(maxWidth: .infinity)
  }

  // MARK: - Refresh Button

  private var refreshButton: some View {
    Button {
      Task { await loadData(isManualRefresh: true) }
    } label: {
      Image(systemName: "arrow.clockwise")
        .symbolEffect(.rotate, isActive: manager.isRefreshing)
    }
    .disabled(manager.isRefreshing)
  }

  // MARK: - Computed Properties

  private var consumingTotalPages: Int {
    max(1, Int(ceil(Double(manager.consumingTotal) / Double(consumingPageSize))))
  }

  private var providingTotalPages: Int {
    max(1, Int(ceil(Double(manager.providingTotal) / Double(providingPageSize))))
  }

  // MARK: - Data Loading

  private func loadData(isManualRefresh: Bool = false) async {
    await loadConsumingTasks(isManualRefresh: isManualRefresh)
    await loadProvidingTasks(isManualRefresh: isManualRefresh)
  }

  private func loadConsumingTasks(isManualRefresh: Bool = false) async {
    guard let token = await authManager.getToken() else { return }
    let offset = (consumingPage - 1) * consumingPageSize
    await manager.loadConsumingTasks(
      limit: consumingPageSize,
      offset: offset,
      status: consumingStatus == "all" ? nil : consumingStatus,
      authToken: token,
      isManualRefresh: isManualRefresh
    )
  }

  private func loadProvidingTasks(isManualRefresh: Bool = false) async {
    guard let token = await authManager.getToken() else { return }
    let offset = (providingPage - 1) * providingPageSize
    await manager.loadProvidingTasks(
      limit: providingPageSize,
      offset: offset,
      status: providingStatus == "all" ? nil : providingStatus,
      authToken: token,
      isManualRefresh: isManualRefresh
    )
  }
}

// MARK: - Task Card

private struct TaskCard: View {
  let task: ComputeTask

  var body: some View {
    HStack(spacing: 12) {
      // Status Indicator
      Circle()
        .fill(statusColor)
        .frame(width: 10, height: 10)

      // Info
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text(task.status.capitalized)
            .font(.subheadline)
            .fontWeight(.medium)

          Spacer()

          Text(task.createdDate, format: .dateTime.month().day().hour().minute())
            .font(.caption)
            .foregroundStyle(.secondary)
        }

        HStack(spacing: 16) {
          Label(task.id.prefix(8) + "...", systemImage: "number")
          if let deviceId = task.deviceId {
            Label(deviceId.prefix(8) + "...", systemImage: "desktopcomputer")
          }
          Label(task.durationText, systemImage: "clock")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
      }
    }
    .padding(12)
    .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 12, style: .continuous))
  }

  private var statusColor: Color {
    switch task.status {
    case "completed": .green
    case "failed": .red
    case "processing": .orange
    case "pending": .gray
    default: .gray
    }
  }
}

#Preview {
  LogsView()
    .environment(AuthManager())
    .environment(LogsManager())
    .environment(ObserverClient())
}
