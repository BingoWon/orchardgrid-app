import SwiftUI

struct EarningsView: View {
  var body: some View {
    PlaceholderView(
      icon: "dollarsign.circle.fill",
      title: "Earnings",
      description: "Track your earnings here"
    )
    .navigationTitle("Earnings")
  }
}

#Preview {
  EarningsView()
}
