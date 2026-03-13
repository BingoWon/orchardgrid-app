import Clerk
import SwiftUI

struct GuestFeaturePrompt: View {
  let icon: String
  let title: String
  let description: String
  let benefits: [String]
  let buttonTitle: String

  @Environment(AuthManager.self) private var authManager

  var body: some View {
    VStack(spacing: 20) {
      Image(systemName: icon)
        .font(.system(size: 48))
        .foregroundStyle(.secondary)

      Text(title)
        .font(.title2)
        .fontWeight(.semibold)

      Text(description)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)

      VStack(alignment: .leading, spacing: 8) {
        ForEach(benefits, id: \.self) { benefit in
          HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
              .foregroundStyle(.green)
              .font(.subheadline)
            Text(benefit)
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
        }
      }
      .padding(.vertical, 8)

      Button {
        authManager.showAuthSheet = true
      } label: {
        Text(buttonTitle)
          .font(.headline)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 12)
      }
      .buttonStyle(.borderedProminent)
      .padding(.horizontal, 32)
    }
    .padding(24)
    .frame(maxWidth: .infinity)
    .glassEffect(in: .rect(cornerRadius: 16, style: .continuous))
  }
}

#Preview("Guest Prompt") {
  GuestFeaturePrompt(
    icon: "server.rack",
    title: "See All Your Devices",
    description: "Sign in to view and manage devices across all your Apple devices.",
    benefits: [
      "Track contributions from each device",
      "View processing statistics",
      "Real-time status updates",
    ],
    buttonTitle: "Sign In to View Devices"
  )
  .environment(AuthManager())
  .padding()
}
