import SwiftUI

/// Table view for devices - used on macOS and iPad landscape
struct DeviceTableView: View {
  let devices: [Device]

  var body: some View {
    #if os(macOS)
      Table(devices) {
        TableColumn("Device") { device in
          HStack(spacing: 8) {
            Image(systemName: device.platformIcon)
              .foregroundStyle(.blue)
            Text(device.deviceName ?? device.platform)
              .fontWeight(.medium)
          }
        }
        .width(min: 120, ideal: 160)

        TableColumn("📍") { device in
          Text(device.flagEmoji)
            .help(device.countryCode ?? "Unknown")
        }
        .width(30)

        TableColumn("Platform") { device in
          Text(device.platform)
        }
        .width(min: 60, ideal: 80)

        TableColumn("Hardware") { device in
          HStack(spacing: 4) {
            if let chip = device.chipModel {
              Text(chip)
            }
            if device.chipModel != nil, device.memoryGb != nil {
              Text("·")
                .foregroundStyle(.secondary)
            }
            if let memory = device.memoryGb {
              Text("\(Int(memory)) GB")
            }
          }
          .font(.system(.body, design: .default))
        }
        .width(min: 100, ideal: 140)

        TableColumn("Status") { device in
          HStack(spacing: 6) {
            Circle()
              .fill(device.isOnline ? Color.green : Color.gray)
              .frame(width: 8, height: 8)
            Text(device.isOnline ? "Online" : "Offline")
          }
        }
        .width(min: 70, ideal: 90)

        TableColumn("Last Seen") { device in
          Text(device.lastSeenText)
            .foregroundStyle(.secondary)
        }
        .width(min: 80, ideal: 100)

        TableColumn("Tasks") { device in
          Text("\(device.tasksProcessed)")
            .fontWeight(.semibold)
        }
        .width(min: 50, ideal: 60)
      }
      .tableStyle(.inset(alternatesRowBackgrounds: true))
    #else
      // iOS Table using Grid (for iPad landscape)
      ScrollView(.horizontal, showsIndicators: false) {
        LazyVStack(spacing: 0) {
          // Header
          HStack(spacing: 0) {
            tableHeader("Device", width: 160)
            tableHeader("📍", width: 40)
            tableHeader("Platform", width: 80)
            tableHeader("Hardware", width: 140)
            tableHeader("Status", width: 100)
            tableHeader("Last Seen", width: 100)
            tableHeader("Tasks", width: 60)
          }
          .padding(.vertical, 8)
          .background(Color(uiColor: .secondarySystemBackground))

          Divider()

          // Rows
          ForEach(devices) { device in
            HStack(spacing: 0) {
              // Device
              HStack(spacing: 8) {
                Image(systemName: device.platformIcon)
                  .foregroundStyle(.blue)
                Text(device.deviceName ?? device.platform)
                  .fontWeight(.medium)
                  .lineLimit(1)
              }
              .frame(width: 160, alignment: .leading)
              .padding(.horizontal, 8)

              // Location
              Text(device.flagEmoji)
                .frame(width: 40)

              // Platform
              Text(device.platform)
                .frame(width: 80, alignment: .leading)
                .padding(.horizontal, 8)

              // Hardware
              HStack(spacing: 4) {
                if let chip = device.chipModel {
                  Text(chip)
                }
                if device.chipModel != nil, device.memoryGb != nil {
                  Text("·")
                    .foregroundStyle(.secondary)
                }
                if let memory = device.memoryGb {
                  Text("\(Int(memory)) GB")
                }
              }
              .frame(width: 140, alignment: .leading)
              .padding(.horizontal, 8)
              .lineLimit(1)

              // Status
              HStack(spacing: 6) {
                Circle()
                  .fill(device.isOnline ? Color.green : Color.gray)
                  .frame(width: 8, height: 8)
                Text(device.isOnline ? "Online" : "Offline")
              }
              .frame(width: 100, alignment: .leading)
              .padding(.horizontal, 8)

              // Last Seen
              Text(device.lastSeenText)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .leading)
                .padding(.horizontal, 8)

              // Tasks
              Text("\(device.tasksProcessed)")
                .fontWeight(.semibold)
                .frame(width: 60, alignment: .trailing)
                .padding(.horizontal, 8)
            }
            .padding(.vertical, 10)

            Divider()
          }
        }
      }
    #endif
  }

  #if !os(macOS)
    private func tableHeader(_ title: String, width: CGFloat) -> some View {
      Text(title)
        .font(.caption)
        .fontWeight(.semibold)
        .foregroundStyle(.secondary)
        .frame(width: width, alignment: title == "Tasks" ? .trailing : .leading)
        .padding(.horizontal, 8)
    }
  #endif
}

#Preview {
  DeviceTableView(devices: [])
}
