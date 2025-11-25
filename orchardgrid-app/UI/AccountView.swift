import SwiftUI

struct AccountView: View {
  @Environment(AuthManager.self) private var authManager
  @State private var isEditingName = false
  @State private var editedName = ""
  @State private var isSaving = false
  @State private var showDeleteConfirmation = false
  @State private var showFinalConfirmation = false
  @State private var isDeleting = false
  @State private var email = ""
  @State private var password = ""

  private let repoURL = URL(string: "https://github.com/BingoWon/orchardgrid-app")!

  var body: some View {
    Form {
      if authManager.isAuthenticated {
        authenticatedContent
      } else {
        guestContent
      }

      // Open Source section - always visible
      Section("Open Source") {
        VStack(alignment: .leading, spacing: 12) {
          Text("The OrchardGrid app is open source. Explore and contribute on GitHub.")
            .font(.subheadline)
            .foregroundStyle(.secondary)

          HStack(spacing: 12) {
            Image("GitHubLogo")
              .resizable()
              .scaledToFit()
              .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
              Text("GitHub Repository")
                .font(.headline)
              Text(repoURL.absoluteString)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            }

            Spacer()

            Link("Open", destination: repoURL)
              .buttonStyle(.borderedProminent)
          }
        }
        .padding(.vertical, 4)
      }
    }
    .formStyle(.grouped)
    .navigationTitle("Account")
    .toolbarRole(.editor)
    .toolbarTitleDisplayMode(.inlineLarge)
    .alert("Delete Account?", isPresented: $showDeleteConfirmation) {
      Button("Cancel", role: .cancel) {}
      Button("Continue", role: .destructive) {
        showFinalConfirmation = true
      }
    } message: {
      Text("This will permanently delete your account and all associated data.")
    }
    .alert("Are you absolutely sure?", isPresented: $showFinalConfirmation) {
      Button("Cancel", role: .cancel) {}
      Button("Delete Account", role: .destructive) {
        Task { await deleteAccount() }
      }
    } message: {
      Text("This action cannot be undone. All your devices, API keys, and tasks will be deleted.")
    }
    .sheet(isPresented: Binding(
      get: { authManager.showRegisterView },
      set: { authManager.showRegisterView = $0 }
    )) {
      RegisterView()
        .environment(authManager)
    }
  }

  // MARK: - Guest Content

  @ViewBuilder
  private var guestContent: some View {
    Section {
      VStack(spacing: 16) {
        // Guest Icon
        Image(systemName: "person.crop.circle.badge.questionmark")
          .font(.system(size: 48))
          .foregroundStyle(.secondary)
          .padding(.top, 8)

        Text("Contributing as Guest")
          .font(.headline)

        Text("Sign in to unlock all features and track your contributions.")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 8)
    }

    // Error
    if let error = authManager.lastError {
      Section {
        Text(error)
          .font(.caption)
          .foregroundStyle(.red)
      }
    }

    Section("Sign In") {
      SocialLoginButton(provider: .apple) {
        authManager.loginWithApple()
      }
      .listRowInsets(EdgeInsets())
      .listRowBackground(Color.clear)

      SocialLoginButton(provider: .google) {
        authManager.loginWithGoogle()
      }
      .listRowInsets(EdgeInsets())
      .listRowBackground(Color.clear)
    }

    Section("Or continue with email") {
      TextField("Email", text: $email)
        #if os(iOS)
          .keyboardType(.emailAddress)
          .textContentType(.emailAddress)
          .autocapitalization(.none)
        #endif

      SecureField("Password", text: $password)
        #if os(iOS)
          .textContentType(.password)
        #endif

      Button {
        Task { await authManager.login(email: email, password: password) }
      } label: {
        if authManager.isLoading {
          ProgressView()
            .frame(maxWidth: .infinity)
        } else {
          Text("Sign In")
            .frame(maxWidth: .infinity)
        }
      }
      .buttonStyle(.borderedProminent)
      .disabled(email.isEmpty || password.isEmpty || authManager.isLoading)
      .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
      .listRowBackground(Color.clear)

      Button {
        authManager.showRegisterView = true
      } label: {
        Text("Don't have an account? **Sign Up**")
          .font(.subheadline)
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(.plain)
      .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
      .listRowBackground(Color.clear)
    }
  }

  // MARK: - Authenticated Content

  @ViewBuilder
  private var authenticatedContent: some View {
    Section("Profile") {
      if let user = authManager.currentUser {
        if isEditingName {
          HStack {
            TextField("Name", text: $editedName)
              .textFieldStyle(.plain)
            Button {
              Task { await saveName() }
            } label: {
              Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            }
            .disabled(isSaving)
            .buttonStyle(.plain)
            Button {
              isEditingName = false
              editedName = user.name ?? ""
            } label: {
              Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
          }
        } else {
          HStack {
            Text("Name")
            Spacer()
            Text(user.name ?? "N/A")
              .foregroundStyle(.secondary)
            Button {
              editedName = user.name ?? ""
              isEditingName = true
            } label: {
              Image(systemName: "pencil")
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
          }
        }
        LabeledContent("Email", value: user.email)
      }
    }

    Section("Session") {
      Button("Sign Out", role: .destructive) {
        authManager.logout()
      }
    }

    Section {
      Button("Delete Account", role: .destructive) {
        showDeleteConfirmation = true
      }
      .disabled(isDeleting)
    } footer: {
      Text(
        "This will permanently delete your account and all associated data including devices, API keys, and tasks. This action cannot be undone."
      )
      .font(.caption)
    }
  }

  private func saveName() async {
    guard let token = authManager.authToken else { return }

    isSaving = true
    defer { isSaving = false }

    do {
      let url = URL(string: "\(Config.apiBaseURL)/auth/profile")!
      var request = URLRequest(url: url)
      request.httpMethod = "PATCH"
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONEncoder().encode(["name": editedName.isEmpty ? nil : editedName])

      let (data, response) = try await Config.urlSession.data(for: request)

      guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
        throw NSError(domain: "Failed to update name", code: -1)
      }

      let updatedUser = try JSONDecoder().decode(User.self, from: data)
      await MainActor.run {
        authManager.currentUser = updatedUser
        isEditingName = false
      }

      Logger.success(.auth, "Name updated successfully")
    } catch {
      Logger.error(.auth, "Failed to update name: \(error.localizedDescription)")
    }
  }

  private func deleteAccount() async {
    guard let token = authManager.authToken else { return }

    isDeleting = true
    defer { isDeleting = false }

    do {
      let url = URL(string: "\(Config.apiBaseURL)/auth/account")!
      var request = URLRequest(url: url)
      request.httpMethod = "DELETE"
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

      let (data, response) = try await URLSession.shared.data(for: request)

      guard let httpResponse = response as? HTTPURLResponse else {
        throw NSError(domain: "Invalid response", code: -1)
      }

      guard httpResponse.statusCode == 200 else {
        let errorText = String(data: data, encoding: .utf8) ?? "Unknown error"
        throw NSError(domain: errorText, code: httpResponse.statusCode)
      }

      await MainActor.run {
        authManager.logout()
      }

      Logger.log(.auth, "Account deleted successfully")
    } catch {
      Logger.error(.auth, "Failed to delete account: \(error.localizedDescription)")
    }
  }
}

#Preview {
  AccountView()
    .environment(AuthManager())
}
