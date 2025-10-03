import SwiftUI

struct PlaceholderView: View {
  let icon: String
  let title: String
  let description: String

  var body: some View {
    VStack(spacing: 16) {
      Image(systemName: icon)
        .font(.system(size: 48))
        .foregroundStyle(.secondary)

      VStack(spacing: 8) {
        Text(title)
          .font(.title2)
          .fontWeight(.semibold)

        Text(description)
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }
}
