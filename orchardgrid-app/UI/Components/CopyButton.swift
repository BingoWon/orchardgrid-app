import SwiftUI

struct CopyButton: View {
  let text: String
  var showLabel = true
  @State private var copied = false

  var body: some View {
    Button {
      Clipboard.copy(text)
      copied = true
      Task {
        try? await Task.sleep(for: .seconds(1.5))
        copied = false
      }
    } label: {
      HStack(spacing: 4) {
        Image(systemName: copied ? "checkmark" : "doc.on.doc")
          .foregroundStyle(copied ? .green : .blue)
        if showLabel, copied {
          Text("Copied")
            .font(.caption2)
            .foregroundStyle(.green)
        }
      }
      .animation(.easeInOut(duration: 0.2), value: copied)
    }
    .font(.caption)
    .buttonStyle(.plain)
  }
}
