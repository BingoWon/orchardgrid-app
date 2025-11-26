import SwiftUI

struct LogsView: View {
  @Environment(AuthManager.self) private var authManager
  @Environment(LogsManager.self) private var manager
  @Environment(ObserverClient.self) private var observerClient
  @State private var selectedTab = 0
  @State private var consumingStatus = "all"
  @State private var providingStatus = "all"
  @State private var consumingPageSize = 50
  @State private var providingPageSize = 50
  @State private var consumingPage = 1
  @State private var providingPage = 1

  private let statusOptions = ["all", "completed", "failed", "processing", "pending"]

  var body: some View {
    ScrollView {
      GlassEffectContainer {
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
    .withPlatformToolbar {
      if authManager.isAuthenticated {
        refreshButton
      }
    }
    .task {
      await loadData()
    }
  }

  // MARK: - Authenticated Content

  @ViewBuilder
  private var authenticatedContent: some View {
    // Status Bar
    HStack {
      HStack(spacing: 4) {
        Circle()
          .fill(observerClient.status == .connected ? .green : .gray)
          .frame(width: 6, height: 6)
        Text(observerClient.status == .connected ? "Live" : "Offline")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()

      if !manager.isInitialLoading {
        LastUpdatedView(lastUpdatedText: manager.lastUpdatedText)
      }
    }

    // Loading State
    if manager.isInitialLoading {
      loadingState
    }
    // Error State
    else if let error = manager.errorMessage {
      errorState(error: error)
    }
    // Content
    else {
      // Summary Card
      summaryCard

      // Tab Selector
      tabSelector

      // Task List
      if selectedTab == 0 {
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
        SummaryStatView(title: "Consuming", value: "\(manager.consumingTotal)")
        SummaryStatView(title: "Providing", value: "\(manager.providingTotal)")
        SummaryStatView(
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
      Text("Consuming").tag(0)
      Text("Providing").tag(1)
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

  private var loadingState: some View {
    VStack(spacing: 16) {
      ProgressView()
      Text("Loading logs...")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 60)
  }

  private var emptyTasksState: some View {
    VStack(spacing: 12) {
      Image(systemName: "tray")
        .font(.system(size: 32))
        .foregroundStyle(.secondary)
      Text("No tasks found")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 40)
  }

  private func errorState(error: String) -> some View {
    HStack {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)

      Text(error)
        .font(.subheadline)

      Spacer()

      Button("Retry") {
        Task { await loadData(isManualRefresh: true) }
      }
      .buttonStyle(.glass)
    }
    .padding()
    .glassEffect(in: .rect(cornerRadius: 12, style: .continuous))
  }

  // MARK: - Refresh Button

  private var refreshButton: some View {
    Button {
      Task { await loadData(isManualRefresh: true) }
    } label: {
      Image(systemName: "arrow.clockwise")
        .rotationEffect(.degrees(manager.isRefreshing ? 360 : 0))
        .animation(
          manager.isRefreshing
            ? .linear(duration: 1).repeatForever(autoreverses: false)
            : .default,
          value: manager.isRefreshing
        )
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
    guard let token = authManager.authToken else { return }
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
    guard let token = authManager.authToken else { return }
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

// MARK: - Summary Stat View

private struct SummaryStatView: View {
  let title: String
  let value: String

  var body: some View {
    VStack(spacing: 4) {
      Text(value)
        .font(.title2.bold())

      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 12)
    .background(.ultraThinMaterial, in: .rect(cornerRadius: 10))
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
        .labelStyle(.titleOnly)
      }
    }
    .padding(12)
    .glassEffect(in: .rect(cornerRadius: 12, style: .continuous))
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
