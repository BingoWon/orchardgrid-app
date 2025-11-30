/**
 * BackgroundManager.swift
 * OrchardGrid Background Execution Manager
 *
 * Ensures continuous background operation across all platforms:
 * - macOS: Power assertions to prevent sleep, disable automatic termination
 * - iOS/iPadOS: Background task scheduling, extended background execution
 */

import Foundation

#if os(macOS)
  import IOKit.pwr_mgt
#elseif os(iOS)
  import BackgroundTasks
  import UIKit
#endif

@Observable
@MainActor
final class BackgroundManager {
  // MARK: - State

  private(set) var isBackgroundEnabled = false
  private(set) var isPreventingSleep = false

  #if os(macOS)
    private var powerAssertionID: IOPMAssertionID = 0
  #elseif os(iOS)
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    static let processingTaskIdentifier = "com.orchardgrid.app.processing"
    static let refreshTaskIdentifier = "com.orchardgrid.app.refresh"
  #endif

  // MARK: - Initialization

  init() {
    #if os(iOS)
      registerBackgroundTasks()
    #endif
  }

  // MARK: - Public API

  /// Enable background execution protection
  func enableBackgroundExecution() {
    guard !isBackgroundEnabled else { return }
    isBackgroundEnabled = true

    #if os(macOS)
      enableMacOSBackground()
    #endif

    Logger.success(.background, "Background execution enabled")
  }

  /// Disable background execution protection
  func disableBackgroundExecution() {
    guard isBackgroundEnabled else { return }
    isBackgroundEnabled = false

    #if os(macOS)
      disableMacOSBackground()
    #elseif os(iOS)
      endBackgroundTask()
    #endif

    Logger.log(.background, "Background execution disabled")
  }

  /// Called when app enters background (iOS only)
  func handleEnterBackground() {
    #if os(iOS)
      guard isBackgroundEnabled else { return }
      beginBackgroundTask()
      scheduleBackgroundTasks()
    #endif
  }

  /// Called when app enters foreground (iOS only)
  func handleEnterForeground() {
    #if os(iOS)
      endBackgroundTask()
    #endif
  }

  /// Prepare for app termination
  func prepareForTermination() {
    Logger.log(.background, "Preparing for termination...")
    disableBackgroundExecution()
  }

  // MARK: - macOS Implementation

  #if os(macOS)
    private func enableMacOSBackground() {
      // Prevent automatic termination
      ProcessInfo.processInfo.disableAutomaticTermination("OrchardGrid active sharing")
      ProcessInfo.processInfo.disableSuddenTermination()

      // Create power assertion to prevent system sleep
      createPowerAssertion()

      Logger.log(.background, "macOS: Disabled automatic termination and sudden termination")
    }

    private func disableMacOSBackground() {
      // Re-enable automatic termination
      ProcessInfo.processInfo.enableAutomaticTermination("OrchardGrid active sharing")
      ProcessInfo.processInfo.enableSuddenTermination()

      // Release power assertion
      releasePowerAssertion()

      Logger.log(.background, "macOS: Re-enabled automatic termination")
    }

    private func createPowerAssertion() {
      guard !isPreventingSleep else { return }

      let reason = "OrchardGrid is sharing compute resources" as CFString
      let result = IOPMAssertionCreateWithName(
        kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
        IOPMAssertionLevel(kIOPMAssertionLevelOn),
        reason,
        &powerAssertionID
      )

      if result == kIOReturnSuccess {
        isPreventingSleep = true
        Logger.success(.background, "macOS: Created power assertion to prevent sleep")
      } else {
        Logger.error(.background, "macOS: Failed to create power assertion: \(result)")
      }
    }

    private func releasePowerAssertion() {
      guard isPreventingSleep else { return }

      let result = IOPMAssertionRelease(powerAssertionID)
      if result == kIOReturnSuccess {
        isPreventingSleep = false
        powerAssertionID = 0
        Logger.log(.background, "macOS: Released power assertion")
      } else {
        Logger.error(.background, "macOS: Failed to release power assertion: \(result)")
      }
    }
  #endif

  // MARK: - iOS Implementation

  #if os(iOS)
    private func registerBackgroundTasks() {
      // Register processing task (for long-running work)
      BGTaskScheduler.shared.register(
        forTaskWithIdentifier: Self.processingTaskIdentifier,
        using: nil
      ) { [weak self] task in
        Task { @MainActor in
          self?.handleProcessingTask(task as! BGProcessingTask)
        }
      }

      // Register refresh task (for periodic check-ins)
      BGTaskScheduler.shared.register(
        forTaskWithIdentifier: Self.refreshTaskIdentifier,
        using: nil
      ) { [weak self] task in
        Task { @MainActor in
          self?.handleRefreshTask(task as! BGAppRefreshTask)
        }
      }

      Logger.log(.background, "iOS: Registered background tasks")
    }

    private func beginBackgroundTask() {
      guard backgroundTaskID == .invalid else { return }

      backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "OrchardGrid") {
        [weak self] in
        Task { @MainActor in
          self?.endBackgroundTask()
        }
      }

      if backgroundTaskID != .invalid {
        Logger.log(.background, "iOS: Started background task")
      }
    }

    private func endBackgroundTask() {
      guard backgroundTaskID != .invalid else { return }

      UIApplication.shared.endBackgroundTask(backgroundTaskID)
      backgroundTaskID = .invalid
      Logger.log(.background, "iOS: Ended background task")
    }

    private func scheduleBackgroundTasks() {
      // Schedule processing task
      let processingRequest = BGProcessingTaskRequest(identifier: Self.processingTaskIdentifier)
      processingRequest.requiresNetworkConnectivity = true
      processingRequest.requiresExternalPower = false

      do {
        try BGTaskScheduler.shared.submit(processingRequest)
        Logger.log(.background, "iOS: Scheduled processing task")
      } catch {
        Logger.error(.background, "iOS: Failed to schedule processing task: \(error)")
      }

      // Schedule refresh task
      let refreshRequest = BGAppRefreshTaskRequest(identifier: Self.refreshTaskIdentifier)
      refreshRequest.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60) // 15 minutes

      do {
        try BGTaskScheduler.shared.submit(refreshRequest)
        Logger.log(.background, "iOS: Scheduled refresh task")
      } catch {
        Logger.error(.background, "iOS: Failed to schedule refresh task: \(error)")
      }
    }

    private func handleProcessingTask(_ task: BGProcessingTask) {
      Logger.log(.background, "iOS: Handling processing task")

      task.expirationHandler = {
        Logger.log(.background, "iOS: Processing task expired")
        task.setTaskCompleted(success: false)
      }

      // Schedule next task
      scheduleBackgroundTasks()

      // Mark as complete after a short delay (the actual work is done by WebSocketClient)
      Task {
        try? await Task.sleep(for: .seconds(5))
        task.setTaskCompleted(success: true)
      }
    }

    private func handleRefreshTask(_ task: BGAppRefreshTask) {
      Logger.log(.background, "iOS: Handling refresh task")

      task.expirationHandler = {
        Logger.log(.background, "iOS: Refresh task expired")
        task.setTaskCompleted(success: false)
      }

      // Schedule next task
      scheduleBackgroundTasks()

      // Complete immediately
      task.setTaskCompleted(success: true)
    }
  #endif
}
