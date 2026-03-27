import SwiftUI

struct StatCard: View {
  let title: LocalizedStringKey
  let value: String
  var compact = false

  var body: some View {
    VStack(spacing: 4) {
      Text(value)
        .font(compact ? .title3.bold() : .title2.bold())

      Text(title)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, compact ? 8 : 12)
    .background {
      if !compact {
        RoundedRectangle(cornerRadius: 10)
          .fill(.ultraThinMaterial)
      }
    }
  }
}
