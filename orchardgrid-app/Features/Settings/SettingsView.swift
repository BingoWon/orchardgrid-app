import SwiftUI

struct SettingsView: View {
  @AppStorage("autoRefreshEnabled") private var autoRefreshEnabled = false
  @AppStorage("autoRefreshInterval") private var autoRefreshInterval = RefreshConfig.defaultInterval
  @State private var showAccountSheet = false
  
  var body: some View {
    Form {
      Section {
        Toggle("Enable Auto-Refresh", isOn: $autoRefreshEnabled)
        
        if autoRefreshEnabled {
          Picker("Refresh Interval", selection: $autoRefreshInterval) {
            ForEach(RefreshConfig.availableIntervals, id: \.self) { interval in
              Text(RefreshConfig.intervalName(for: interval))
                .tag(interval)
            }
          }
          
          Text("Data will automatically refresh in the background at the selected interval.")
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      } header: {
        Label("Auto-Refresh", systemImage: "arrow.clockwise")
      } footer: {
        if !autoRefreshEnabled {
          Text("Enable auto-refresh to keep your data up-to-date automatically. You can still manually refresh by pulling down on any page.")
        }
      }
      
      Section {
        HStack {
          Text("Version")
          Spacer()
          Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")
            .foregroundStyle(.secondary)
        }
        
        HStack {
          Text("Build")
          Spacer()
          Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown")
            .foregroundStyle(.secondary)
        }
      } header: {
        Label("About", systemImage: "info.circle")
      }
    }
    .navigationTitle("Settings")
    .toolbarRole(.editor)
    .toolbarTitleDisplayMode(.inlineLarge)
    .withAccountToolbar(showAccountSheet: $showAccountSheet)
  }
}

#Preview {
  NavigationStack {
    SettingsView()
  }
}
