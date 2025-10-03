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
      TabView(selection: $selectedTab) {
        consumingView
          .tag(0)
        providingView
          .tag(1)
      }
      .tabViewStyle(.automatic)
    }
    .navigationTitle("Logs")
    .task {
      await loadData()
    }
  }

  private var consumingView: some View {
    VStack(spacing: 16) {
      // Filters
      HStack {
        Picker("Status", selection: $consumingStatus) {
          ForEach(statusOptions, id: \.self) { status in
            Text(status.capitalized).tag(status)
          }
        }
        .frame(width: 150)
        .onChange(of: consumingStatus) {
          consumingPage = 1
          Task { await loadConsumingTasks() }
        }

        Picker("Per Page", selection: $consumingPageSize) {
          ForEach(pageSizeOptions, id: \.self) { size in
            Text("\(size) / page").tag(size)
          }
        }
        .frame(width: 120)
        .onChange(of: consumingPageSize) {
          consumingPage = 1
          Task { await loadConsumingTasks() }
        }

        Spacer()
      }
      .padding(.horizontal)

      // Table
      if manager.isLoading {
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if manager.consumingTasks.isEmpty {
        Text("No logs found")
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        Table(manager.consumingTasks) {
          TableColumn("Time") { task in
            Text(task.createdDate, style: .date)
              .font(.system(.body, design: .monospaced))
          }
          .width(min: 100, ideal: 150)

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
            Text(task.status.capitalized)
              .foregroundStyle(Color(task.statusColor))
          }
          .width(min: 80, ideal: 100)

          TableColumn("Duration") { task in
            Text(task.durationText)
              .font(.system(.body, design: .monospaced))
          }
          .width(min: 80, ideal: 100)
        }

        // Pagination
        HStack {
          Text(
            "Showing \((consumingPage - 1) * consumingPageSize + 1) to \(min(consumingPage * consumingPageSize, manager.consumingTotal)) of \(manager.consumingTotal) logs"
          )
          .font(.caption)
          .foregroundStyle(.secondary)

          Spacer()

          Button("Previous") {
            consumingPage = max(1, consumingPage - 1)
            Task { await loadConsumingTasks() }
          }
          .disabled(consumingPage == 1)

          Text("Page \(consumingPage) of \(consumingTotalPages)")
            .font(.caption)

          Button("Next") {
            consumingPage = min(consumingTotalPages, consumingPage + 1)
            Task { await loadConsumingTasks() }
          }
          .disabled(consumingPage == consumingTotalPages)
        }
        .padding(.horizontal)
      }
    }
    .padding()
  }

  private var providingView: some View {
    VStack(spacing: 16) {
      // Filters
      HStack {
        Picker("Status", selection: $providingStatus) {
          ForEach(statusOptions, id: \.self) { status in
            Text(status.capitalized).tag(status)
          }
        }
        .frame(width: 150)
        .onChange(of: providingStatus) {
          providingPage = 1
          Task { await loadProvidingTasks() }
        }

        Picker("Per Page", selection: $providingPageSize) {
          ForEach(pageSizeOptions, id: \.self) { size in
            Text("\(size) / page").tag(size)
          }
        }
        .frame(width: 120)
        .onChange(of: providingPageSize) {
          providingPage = 1
          Task { await loadProvidingTasks() }
        }

        Spacer()
      }
      .padding(.horizontal)

      // Table
      if manager.isLoading {
        ProgressView()
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else if manager.providingTasks.isEmpty {
        Text("No logs found")
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        Table(manager.providingTasks) {
          TableColumn("Time") { task in
            Text(task.createdDate, style: .date)
              .font(.system(.body, design: .monospaced))
          }
          .width(min: 100, ideal: 150)

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
            Text(task.status.capitalized)
              .foregroundStyle(Color(task.statusColor))
          }
          .width(min: 80, ideal: 100)

          TableColumn("Duration") { task in
            Text(task.durationText)
              .font(.system(.body, design: .monospaced))
          }
          .width(min: 80, ideal: 100)
        }

        // Pagination
        HStack {
          Text(
            "Showing \((providingPage - 1) * providingPageSize + 1) to \(min(providingPage * providingPageSize, manager.providingTotal)) of \(manager.providingTotal) logs"
          )
          .font(.caption)
          .foregroundStyle(.secondary)

          Spacer()

          Button("Previous") {
            providingPage = max(1, providingPage - 1)
            Task { await loadProvidingTasks() }
          }
          .disabled(providingPage == 1)

          Text("Page \(providingPage) of \(providingTotalPages)")
            .font(.caption)

          Button("Next") {
            providingPage = min(providingTotalPages, providingPage + 1)
            Task { await loadProvidingTasks() }
          }
          .disabled(providingPage == providingTotalPages)
        }
        .padding(.horizontal)
      }
    }
    .padding()
  }

  private var consumingTotalPages: Int {
    max(1, Int(ceil(Double(manager.consumingTotal) / Double(consumingPageSize))))
  }

  private var providingTotalPages: Int {
    max(1, Int(ceil(Double(manager.providingTotal) / Double(providingPageSize))))
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
