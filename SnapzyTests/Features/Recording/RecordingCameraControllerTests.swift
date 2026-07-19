import AVFoundation
import QuartzCore
import XCTest
@testable import Snapzy

@MainActor
final class RecordingCameraControllerTests: XCTestCase {

  func testShowUsesExplicitlySelectedAvailableCamera() async throws {
    let hardware = FakeRecordingCameraHardware(
      devices: [
        RecordingCameraDevice(id: "iphone", displayName: "Test iPhone", isContinuityCamera: true),
        RecordingCameraDevice(id: "usb", displayName: "USB Camera", isContinuityCamera: false),
      ],
      systemPreferredDeviceID: "iphone"
    )
    let controller = RecordingCameraController(
      hardware: hardware,
      defaults: UserDefaultsFactory.make()
    )

    try await controller.show(
      configuration: RecordingCameraConfiguration(
        deviceID: "usb",
        shape: .widescreen,
        mirrored: false
      ),
      in: CGRect(x: 0, y: 0, width: 1200, height: 800)
    )

    XCTAssertEqual(controller.activeDeviceID, "usb")
    XCTAssertEqual(hardware.createdSessionDeviceIDs, ["usb"])
    XCTAssertTrue(hardware.sessions[0].running)
    controller.hide()
  }

  func testDisconnectedCameraHidesOverlayAndReconnectsSameDevice() async throws {
    let hardware = FakeRecordingCameraHardware(
      devices: [
        RecordingCameraDevice(id: "iphone", displayName: "Test iPhone", isContinuityCamera: true),
      ],
      systemPreferredDeviceID: "iphone"
    )
    let controller = RecordingCameraController(
      hardware: hardware,
      defaults: UserDefaultsFactory.make()
    )
    let configuration = RecordingCameraConfiguration(
      deviceID: "iphone",
      shape: .circle,
      mirrored: true
    )
    try await controller.show(
      configuration: configuration,
      in: CGRect(x: 0, y: 0, width: 1200, height: 800)
    )

    hardware.devices = []
    controller.handleDeviceDisconnected(id: "iphone")

    XCTAssertNil(controller.activeDeviceID)
    XCTAssertEqual(controller.requestedDeviceID, "iphone")
    XCTAssertFalse(hardware.sessions[0].running)

    hardware.devices = [
      RecordingCameraDevice(id: "iphone", displayName: "Test iPhone", isContinuityCamera: true),
    ]
    await controller.handleDeviceConnected(id: "iphone")

    XCTAssertEqual(controller.activeDeviceID, "iphone")
    XCTAssertEqual(hardware.createdSessionDeviceIDs, ["iphone", "iphone"])
    XCTAssertTrue(hardware.sessions[1].running)
    controller.hide()
  }

  func testMissingSelectionFallsBackToSystemPreferredCamera() async throws {
    let hardware = FakeRecordingCameraHardware(
      devices: [
        RecordingCameraDevice(id: "usb", displayName: "USB Camera", isContinuityCamera: false),
        RecordingCameraDevice(id: "iphone", displayName: "iPhone", isContinuityCamera: true),
      ],
      systemPreferredDeviceID: "usb"
    )
    let controller = RecordingCameraController(hardware: hardware, defaults: UserDefaultsFactory.make())

    try await controller.show(
      configuration: RecordingCameraConfiguration(deviceID: "missing", shape: .classic, mirrored: false),
      in: CGRect(x: 0, y: 0, width: 800, height: 600)
    )

    XCTAssertEqual(controller.activeDeviceID, "usb")
    controller.hide()
  }

  func testFallsBackToContinuityCameraWhenSystemPreferenceIsUnavailable() async throws {
    let hardware = FakeRecordingCameraHardware(
      devices: [
        RecordingCameraDevice(id: "usb", displayName: "USB Camera", isContinuityCamera: false),
        RecordingCameraDevice(id: "iphone", displayName: "iPhone", isContinuityCamera: true),
      ],
      systemPreferredDeviceID: "missing"
    )
    let controller = RecordingCameraController(hardware: hardware, defaults: UserDefaultsFactory.make())

    try await controller.show(
      configuration: RecordingCameraConfiguration(
        deviceID: RecordingCameraDevice.systemPreferredID,
        shape: .widescreen,
        mirrored: false
      ),
      in: CGRect(x: 0, y: 0, width: 800, height: 600)
    )

    XCTAssertEqual(controller.activeDeviceID, "iphone")
    controller.hide()
  }

  func testDeniedPermissionDoesNotCreateSession() async {
    let hardware = FakeRecordingCameraHardware(
      devices: [RecordingCameraDevice(id: "iphone", displayName: "iPhone", isContinuityCamera: true)],
      systemPreferredDeviceID: "iphone",
      authorizationStatus: .denied
    )
    let controller = RecordingCameraController(hardware: hardware, defaults: UserDefaultsFactory.make())

    do {
      try await controller.show(
        configuration: RecordingCameraConfiguration(deviceID: "iphone", shape: .circle, mirrored: false),
        in: CGRect(x: 0, y: 0, width: 800, height: 600)
      )
      XCTFail("Expected camera permission denial")
    } catch {
      XCTAssertEqual(error as? RecordingCameraError, .permissionDenied)
      XCTAssertTrue(hardware.createdSessionDeviceIDs.isEmpty)
      XCTAssertNil(controller.activeDeviceID)
    }
  }

  func testHidingWhileCameraStartsDoesNotReviveTheSession() async throws {
    let hardware = FakeRecordingCameraHardware(
      devices: [RecordingCameraDevice(id: "iphone", displayName: "iPhone", isContinuityCamera: true)],
      systemPreferredDeviceID: "iphone",
      suspendSessionStart: true
    )
    let controller = RecordingCameraController(
      hardware: hardware,
      defaults: UserDefaultsFactory.make()
    )

    let showTask = Task {
      try await controller.show(
        configuration: RecordingCameraConfiguration(
          deviceID: "iphone",
          shape: .circle,
          mirrored: false
        ),
        in: CGRect(x: 0, y: 0, width: 800, height: 600)
      )
    }

    while hardware.sessions.isEmpty || !hardware.sessions[0].isWaitingToStart {
      await Task.yield()
    }
    let session = try XCTUnwrap(hardware.sessions.first)

    controller.hide()
    session.finishStarting()

    do {
      try await showTask.value
      XCTFail("Expected the stale camera presentation to be cancelled")
    } catch is CancellationError {
      // Expected: hiding invalidates the in-flight camera presentation.
    }

    XCTAssertFalse(session.running)
    XCTAssertNil(controller.activeDeviceID)
    XCTAssertNil(controller.overlayWindowID)
  }
}

@MainActor
private final class FakeRecordingCameraHardware: RecordingCameraHardware {
  var devices: [RecordingCameraDevice]
  let systemPreferredDeviceID: String?
  let cameraAuthorizationStatus: AVAuthorizationStatus
  let suspendSessionStart: Bool
  private(set) var sessions: [FakeRecordingCameraPreviewSession] = []
  private(set) var createdSessionDeviceIDs: [String] = []

  init(
    devices: [RecordingCameraDevice],
    systemPreferredDeviceID: String?,
    authorizationStatus: AVAuthorizationStatus = .authorized,
    suspendSessionStart: Bool = false
  ) {
    self.devices = devices
    self.systemPreferredDeviceID = systemPreferredDeviceID
    self.cameraAuthorizationStatus = authorizationStatus
    self.suspendSessionStart = suspendSessionStart
  }

  func authorizationStatus() -> AVAuthorizationStatus { cameraAuthorizationStatus }

  func requestAccess() async -> Bool { true }

  func availableDevices() -> [RecordingCameraDevice] { devices }

  func makeSession(deviceID: String, mirrored: Bool) throws -> RecordingCameraPreviewSession {
    createdSessionDeviceIDs.append(deviceID)
    let session = FakeRecordingCameraPreviewSession(suspendStart: suspendSessionStart)
    session.mirrored = mirrored
    sessions.append(session)
    return session
  }
}

@MainActor
private final class FakeRecordingCameraPreviewSession: RecordingCameraPreviewSession {
  let previewLayer = CALayer()
  private(set) var running = false
  private(set) var isWaitingToStart = false
  var mirrored = false
  private let suspendStart: Bool
  private var startContinuation: CheckedContinuation<Void, Never>?

  init(suspendStart: Bool = false) {
    self.suspendStart = suspendStart
  }

  func start() async {
    if suspendStart {
      isWaitingToStart = true
      await withCheckedContinuation { continuation in
        startContinuation = continuation
      }
      isWaitingToStart = false
    }
    running = true
  }
  func stop() { running = false }
  func setMirrored(_ mirrored: Bool) { self.mirrored = mirrored }

  func finishStarting() {
    startContinuation?.resume()
    startContinuation = nil
  }
}
