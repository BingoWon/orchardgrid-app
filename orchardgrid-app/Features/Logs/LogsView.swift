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
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          Task {
            if selectedTab == 0 {
              await loadConsumingTasks()
            } else {
              await loadProvidingTasks()
            }
          }
        } label: {
          Image(systemName: "arrow.clockwise")
            .rotationEffect(.degrees(manager.isLoading ? 360 : 0))
            .animation(
              manager.isLoading
                ? .linear(duration: 1).repeatForever(autoreverses: false)
                : .default,
              value: manager.isLoading
            )
        }
        .disabled(manager.isLoading)
      }
    }
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
    #if os(macOS)
      // macOS: Use Table for better desktop experience
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
    #else
      // iOS/iPadOS: Use List for better mobile experience
      ScrollView {
        LazyVStack(spacing: 12) {
          ForEach(tasks) { task in
            taskCard(task: task)
          }
        }
        .padding()
      }
    #endif
  }

  @ViewBuilder
  private func taskCard(task: ComputeTask) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      // Header: Status and Time
      HStack {
        HStack(spacing: 6) {
          Circle()
            .fill(statusColor(for: task.status))
            .frame(width: 10, height: 10)
          Text(task.status.capitalized)
            .font(.subheadline)
            .fontWeight(.medium)
        }

        Spacer()

        Text(task.createdDate, format: .dateTime.month().day().hour().minute())
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      // Details
      VStack(alignment: .leading, spacing: 8) {
        HStack {
          Text("Task ID")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 70, alignment: .leading)
          Text(task.id.prefix(12) + "...")
            .font(.system(.caption, design: .monospaced))
        }

        if let deviceId = task.deviceId {
          HStack {
            Text("Device")
              .font(.caption)
              .foregroundStyle(.secondary)
              .frame(width: 70, alignment: .leading)
            Text(deviceId.prefix(12) + "...")
              .font(.system(.caption, design: .monospaced))
          }
        }

        HStack {
          Text("Duration")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 70, alignment: .leading)
          Text(task.durationText)
            .font(.system(.caption, design: .monospaced))
        }
      }
    }
    .padding()
    #if os(macOS)
      .background(Color(nsColor: .controlBackgroundColor))
    #else
      .background(Color(uiColor: .systemBackground))
    #endif
      .cornerRadius(12)
      .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: 1)
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
