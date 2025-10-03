import SwiftUI

struct AccountView: View {
  @Environment(AuthManager.self) private var authManager

  var body: some View {
    Form {
      Section("Profile") {
        if let user = authManager.currentUser {
          LabeledContent("Name", value: user.name ?? "N/A")
          LabeledContent("Email", value: user.email)
        }
      }

      Section {
        Button("Sign Out", role: .destructive) {
          authManager.logout()
        }
      }
    }
    .formStyle(.grouped)
    .navigationTitle("Account")
  }
}

#Preview {
  AccountView()
    .environment(AuthManager())
}
