import SwiftUI

struct ErrorBanner: View {
  let error: APIError
  let onRetry: () -> Void

  var body: some View {
    HStack {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)

      Text(error.localizedDescription)
        .font(.subheadline)

      Spacer()

      Button("Retry", action: onRetry)
        .buttonStyle(.glass)
    }
    .padding()
    .glassEffect(in: .rect(cornerRadius: 12, style: .continuous))
  }
}
