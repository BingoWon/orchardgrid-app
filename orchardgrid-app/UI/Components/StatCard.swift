import SwiftUI

struct StatCard: View {
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
    .background(.primary.opacity(0.04), in: .rect(cornerRadius: 10))
  }
}
