import SwiftUI

struct ServerStatusView: View {
  let server: APIServer

  var body: some View {
    ScrollView {
      VStack(spacing: 24) {
        headerSection
        statusSection
        if !server.errorMessage.isEmpty {
          errorSection
        }
        statisticsSection
        usageSection
      }
      .padding()
    }
    .frame(minWidth: 600, minHeight: 700)
  }

  private var headerSection: some View {
    VStack(spacing: 8) {
      Text("Giant Big")
        .font(.system(size: 36, weight: .bold, design: .rounded))

      Text("Apple Intelligence API Server")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
  }

  private var statusSection: some View {
    HStack(spacing: 16) {
      Circle()
        .fill(server.isRunning ? .green : .red)
        .frame(width: 16, height: 16)
        .shadow(color: server.isRunning ? .green.opacity(0.5) : .red.opacity(0.5), radius: 4)

      VStack(alignment: .leading, spacing: 4) {
        Text(server.isRunning ? "Running" : "Stopped")
          .font(.headline)

        Text("Port \(server.port)")
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Spacer()
    }
    .padding()
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
  }

  private var errorSection: some View {
    HStack {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.red)

      Text(server.errorMessage)
        .font(.caption)

      Spacer()
    }
    .padding()
    .background(.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
  }

  private var statisticsSection: some View {
    VStack(alignment: .leading, spacing: 16) {
      Label("Statistics", systemImage: "chart.bar.fill")
        .font(.headline)

      HStack {
        Text("Total Requests")
          .foregroundStyle(.secondary)
        Spacer()
        Text("\(server.requestCount)")
          .fontWeight(.semibold)
          .monospacedDigit()
      }

      if !server.lastRequest.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          Text("Last Request")
            .font(.subheadline)
            .foregroundStyle(.secondary)

          Text(server.lastRequest)
            .font(.caption)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            .textSelection(.enabled)
        }
      }

      if !server.lastResponse.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          Text("Last Response")
            .font(.subheadline)
            .foregroundStyle(.secondary)

          Text(server.lastResponse)
            .font(.caption)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            .textSelection(.enabled)
        }
      }
    }
    .padding()
    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
  }

  private var usageSection: some View {
    VStack(alignment: .leading, spacing: 16) {
      Label("API Usage", systemImage: "terminal.fill")
        .font(.headline)

      VStack(alignment: .leading, spacing: 12) {
        InfoRow(title: "Base URL", value: "http://localhost:\(server.port)/v1")
        InfoRow(title: "Model", value: "apple-intelligence")
      }

      Divider()

      VStack(alignment: .leading, spacing: 8) {
        Text("Example Request")
          .font(.subheadline)
          .foregroundStyle(.secondary)

        Text("""
        curl http://localhost:\(server.port)/v1/chat/completions \\
          -H "Content-Type: application/json" \\
          -d '{
            "model": "apple-intelligence",
            "messages": [
              {"role": "user", "content": "Hello!"}
            ]
          }'
        """)
        .font(.system(.caption, design: .monospaced))
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
        .textSelection(.enabled)
      }
    }
    .padding()
    .background(.blue.opacity(0.05), in: RoundedRectangle(cornerRadius: 12))
  }
}

struct InfoRow: View {
  let title: String
  let value: String

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)

      Text(value)
        .font(.system(.caption, design: .monospaced))
        .textSelection(.enabled)
    }
  }
}

#Preview {
  ServerStatusView(server: APIServer())
}
