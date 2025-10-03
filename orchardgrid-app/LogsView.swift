import SwiftUI

struct LogsView: View {
  @Environment(AuthManager.self) private var authManager
  @State private var manager = LogsManager()
  @State private var selectedTab = 0
  @State private var consumingStatus = "all"
  @State private var providingStatus = "all"
  @State private var consumingPageSize = 50
  @State private var providingPageSize = 50
  @State private var consumingPage = 1
  @State private var providingPage = 1

  private let statusOptions = ["all", "completed", "failed", "processing", "pending"]
  private let pageSizeOptions = [10, 25, 50, 100]

  var body: some View {
    VStack(spacing: 0) {
      // Header
      VStack(alignment: .leading, spacing: 8) {
        Text("Logs")
          .font(.largeTitle)
          .fontWeight(.bold)
        Text("Detailed logs for providing and consuming computing resources")
          .font(.subheadline)
          .foregroundStyle(.secondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding()

      Divider()

      // Tabs
      Picker("", selection: $selectedTab) {
        Text("Consuming").tag(0)
        Text("Providing").tag(1)
      }
      .pickerStyle(.segmented)
      .padding()

      // Content
      if selectedTab == 0 {
        consumingView
      } else {
        providingView
      }
    }
    .navigationTitle("Logs")
    .task {
      await loadData()
    }
  }

  private var consumingView: some View {
    taskListView(
      tasks: manager.consumingTasks,
      total: manager.consumingTotal,
      status: $consumingStatus,
      pageSize: $consumingPageSize,
      page: $consumingPage,
      totalPages: consumingTotalPages,
      onReload: { Task { await loadConsumingTasks() } }
    )
  }

  private var providingView: some View {
    taskListView(
      tasks: manager.providingTasks,
      total: manager.providingTotal,
      status: $providingStatus,
      pageSize: $providingPageSize,
      page: $providingPage,
      totalPages: providingTotalPages,
      onReload: { Task { await loadProvidingTasks() } }
    )
  }

  private var consumingTotalPages: Int {
    max(1, Int(ceil(Double(manager.consumingTotal) / Double(consumingPageSize))))
  }

  private var providingTotalPages: Int {
    max(1, Int(ceil(Double(manager.providingTotal) / Double(providingPageSize))))
  }

  @ViewBuilder
  private func taskListView(
    tasks: [ComputeTask],
    total: Int,
    status: Binding<String>,
    pageSize: Binding<Int>,
    page: Binding<Int>,
    totalPages: Int,
    onReload: @escaping () -> Void
  ) -> some View {
    VStack(spacing: 16) {
      // Filters
      HStack {
        Picker("Status", selection: status) {
          ForEach(statusOptions, id: \.self) { status in
            Text(status.capitalized).tag(status)
          }
        }
        .frame(width: 150)
        .onChange(of: status.wrappedValue) {
          page.wrappedValue = 1
          onReload()
        }

        Picker("Per Page", selection: pageSize) {
          ForEach(pageSizeOptions, id: \.self) { size in
            Text("\(size) / page").tag(size)
          }
        }
        .frame(width: 160)
        .onChange(of: pageSize.wrappedValue) {
          page.wrappedValue = 1
          onReload()
        }

        Spacer()
      }
      .padding(.horizontal)

      // Content
      if manager.isLoading {
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if tasks.isEmpty {
        Text("No logs found")
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        taskTable(tasks: tasks)
        paginationBar(
          page: page,
          pageSize: pageSize.wrappedValue,
          total: total,
          totalPages: totalPages,
          onReload: onReload
        )
      }
    }
    .padding()
  }

  @ViewBuilder
  private func taskTable(tasks: [ComputeTask]) -> some View {
    Table(tasks) {
      TableColumn("Time") { task in
        Text(task.createdDate, format: .dateTime.year().month().day().hour().minute().second())
          .font(.system(.body, design: .monospaced))
      }
      .width(min: 150, ideal: 180)

      TableColumn("Task ID") { task in
        Text(task.id.prefix(8) + "...")
          .font(.system(.body, design: .monospaced))
      }
      .width(min: 100, ideal: 120)

      TableColumn("Device") { task in
        if let deviceId = task.deviceId {
          Text(deviceId.prefix(8) + "...")
            .font(.system(.body, design: .monospaced))
        } else {
          Text("-")
        }
      }
      .width(min: 100, ideal: 120)

      TableColumn("Status") { task in
        HStack(spacing: 4) {
          Circle()
            .fill(statusColor(for: task.status))
            .frame(width: 8, height: 8)
          Text(task.status.capitalized)
        }
      }
      .width(min: 100, ideal: 120)

      TableColumn("Duration") { task in
        Text(task.durationText)
          .font(.system(.body, design: .monospaced))
      }
      .width(min: 80, ideal: 100)
    }
  }

  @ViewBuilder
  private func paginationBar(
    page: Binding<Int>,
    pageSize: Int,
    total: Int,
    totalPages: Int,
    onReload: @escaping () -> Void
  ) -> some View {
    HStack {
      Text(
        "Showing \((page.wrappedValue - 1) * pageSize + 1) to \(min(page.wrappedValue * pageSize, total)) of \(total) logs"
      )
      .font(.caption)
      .foregroundStyle(.secondary)

      Spacer()

      Button("Previous") {
        page.wrappedValue = max(1, page.wrappedValue - 1)
        onReload()
      }
      .disabled(page.wrappedValue == 1)

      Text("Page \(page.wrappedValue) of \(totalPages)")
        .font(.caption)

      Button("Next") {
        page.wrappedValue = min(totalPages, page.wrappedValue + 1)
        onReload()
      }
      .disabled(page.wrappedValue == totalPages)
    }
    .padding(.horizontal)
  }

  private func statusColor(for status: String) -> Color {
    switch status {
    case "completed": .green
    case "failed": .red
    case "processing": .orange
    case "pending": .gray
    default: .gray
    }
  }

  private func loadData() async {
    await loadConsumingTasks()
    await loadProvidingTasks()
  }

  private func loadConsumingTasks() async {
    guard let token = authManager.authToken else { return }
    let offset = (consumingPage - 1) * consumingPageSize
    await manager.loadConsumingTasks(
      limit: consumingPageSize,
      offset: offset,
      status: consumingStatus == "all" ? nil : consumingStatus,
      authToken: token
    )
  }

  private func loadProvidingTasks() async {
    guard let token = authManager.authToken else { return }
    let offset = (providingPage - 1) * providingPageSize
    await manager.loadProvidingTasks(
      limit: providingPageSize,
      offset: offset,
      status: providingStatus == "all" ? nil : providingStatus,
      authToken: token
    )
  }
}

#Preview {
  LogsView()
    .environment(AuthManager())
}
