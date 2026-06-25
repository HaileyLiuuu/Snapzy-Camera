//
//  AppStatusBarControllerTests.swift
//  SnapzyTests
//
//  Unit tests for AppStatusBarController activation policy.
//

import AppKit
import XCTest
@testable import Snapzy

@MainActor
final class AppStatusBarControllerTests: XCTestCase {
  private var controller: AppStatusBarController!
  private var initialPolicy: NSApplication.ActivationPolicy!

  override func setUp() {
    super.setUp()
    controller = AppStatusBarController.shared
    initialPolicy = NSApp.activationPolicy()
  }

  override func tearDown() {
    // Restore initial state
    NSApp.setActivationPolicy(initialPolicy)
    controller.didElevateForSettingsForTesting = false
    controller.trackedPreferencesWindowForTesting = nil
    super.tearDown()
  }

  func testWindowDidClose_revertsActivationPolicyWhenNoOtherVisibleWindows() {
    // 1. Setup initial elevated state
    controller.didElevateForSettingsForTesting = true
    NSApp.setActivationPolicy(.regular)

    // 2. Create a mock closing window and make it visible
    let closingWindow = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )
    closingWindow.title = "Settings"
    closingWindow.orderFront(nil)
    controller.trackedPreferencesWindowForTesting = closingWindow

    // 3. Post notification/Simulate close
    let notification = Notification(
      name: NSWindow.willCloseNotification,
      object: closingWindow
    )
    controller.simulateWindowDidClose(notification: notification)

    // 4. Verify that activation policy reverted to .accessory
    XCTAssertEqual(NSApp.activationPolicy(), .accessory)
    XCTAssertFalse(controller.didElevateForSettingsForTesting)
    XCTAssertNil(controller.trackedPreferencesWindowForTesting)

    // 5. Cleanup window to prevent leakage
    closingWindow.close()
  }
}
