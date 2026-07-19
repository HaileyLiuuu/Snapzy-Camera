import AppKit
@preconcurrency import AVFoundation
import QuartzCore

@MainActor
protocol RecordingCameraPreviewSession: AnyObject {
  var previewLayer: CALayer { get }
  func start() async
  func stop()
  func setMirrored(_ mirrored: Bool)
}

@MainActor
protocol RecordingCameraHardware: AnyObject {
  var systemPreferredDeviceID: String? { get }
  func authorizationStatus() -> AVAuthorizationStatus
  func requestAccess() async -> Bool
  func availableDevices() -> [RecordingCameraDevice]
  func makeSession(deviceID: String, mirrored: Bool) throws -> RecordingCameraPreviewSession
}

enum RecordingCameraError: Error, Equatable {
  case permissionDenied
  case noCameraAvailable
  case deviceUnavailable
  case cannotAddDeviceInput
}

@MainActor
final class RecordingCameraController {
  static let shared = RecordingCameraController()

  private let hardware: RecordingCameraHardware
  private let defaults: UserDefaults
  private var previewSession: RecordingCameraPreviewSession?
  private var overlayWindow: RecordingCameraOverlayWindow?
  private var recordingRect: CGRect = .zero
  private var lastConfiguration: RecordingCameraConfiguration?
  private var reconnectingDeviceID: String?
  private var deviceObserverTokens: [NSObjectProtocol] = []
  private var presentationGeneration: UInt = 0

  private(set) var activeDeviceID: String?
  private(set) var requestedDeviceID: String?
  var onOverlayWindowChanged: ((CGWindowID?) -> Void)?

  var overlayWindowID: CGWindowID? {
    overlayWindow.map { CGWindowID($0.windowNumber) }
  }

  init(
    hardware: RecordingCameraHardware? = nil,
    defaults: UserDefaults = .standard
  ) {
    self.hardware = hardware ?? AVFoundationRecordingCameraHardware()
    self.defaults = defaults
    observeDeviceConnections()
  }

  deinit {
    for token in deviceObserverTokens {
      NotificationCenter.default.removeObserver(token)
    }
  }

  func availableDevices() -> [RecordingCameraDevice] {
    hardware.availableDevices()
  }

  func show(
    configuration: RecordingCameraConfiguration,
    in recordingRect: CGRect
  ) async throws {
    presentationGeneration &+= 1
    let generation = presentationGeneration
    try await ensurePermission()
    guard !Task.isCancelled, generation == presentationGeneration else {
      throw CancellationError()
    }

    let devices = hardware.availableDevices()
    guard let deviceID = resolvedDeviceID(
      requestedID: configuration.deviceID,
      devices: devices
    ) else {
      throw RecordingCameraError.noCameraAvailable
    }

    dismissOverlay(
      preserveSelection: false,
      invalidatePendingPresentation: false
    )

    let session = try hardware.makeSession(
      deviceID: deviceID,
      mirrored: configuration.mirrored
    )
    let layout = storedLayout()
    let frame = layout.frame(in: recordingRect, shape: configuration.shape)
    let window = RecordingCameraOverlayWindow(
      frame: frame,
      recordingRect: recordingRect,
      shape: configuration.shape,
      previewLayer: session.previewLayer
    )
    window.onFrameChanged = { [weak self] frame in
      guard let self else { return }
      self.storeLayout(CameraOverlayLayout(frame: frame, in: self.recordingRect))
    }

    self.recordingRect = recordingRect
    self.previewSession = session
    self.overlayWindow = window
    self.activeDeviceID = deviceID
    self.requestedDeviceID = configuration.deviceID
    self.lastConfiguration = configuration
    self.reconnectingDeviceID = nil

    await session.start()
    guard !Task.isCancelled,
          generation == presentationGeneration,
          previewSession === session,
          overlayWindow === window
    else {
      session.stop()
      window.close()
      if generation == presentationGeneration {
        dismissOverlay(preserveSelection: false)
      }
      throw CancellationError()
    }
    window.orderFrontRegardless()
    onOverlayWindowChanged?(overlayWindowID)
  }

  func update(
    configuration: RecordingCameraConfiguration,
    recordingRect: CGRect
  ) {
    self.recordingRect = recordingRect
    self.lastConfiguration = configuration
    previewSession?.setMirrored(configuration.mirrored)
    overlayWindow?.update(
      frame: storedLayout().frame(in: recordingRect, shape: configuration.shape),
      recordingRect: recordingRect,
      shape: configuration.shape
    )
  }

  func hide() {
    dismissOverlay(preserveSelection: false)
    lastConfiguration = nil
    reconnectingDeviceID = nil
  }

  func handleDeviceDisconnected(id: String) {
    guard activeDeviceID == id else { return }
    reconnectingDeviceID = id
    dismissOverlay(preserveSelection: true)
  }

  func handleDeviceConnected(id: String) async {
    guard reconnectingDeviceID == id,
          hardware.availableDevices().contains(where: { $0.id == id }),
          let configuration = lastConfiguration
    else {
      return
    }

    let rememberedRequest = requestedDeviceID
    do {
      try await show(
        configuration: RecordingCameraConfiguration(
          deviceID: id,
          shape: configuration.shape,
          mirrored: configuration.mirrored
        ),
        in: recordingRect
      )
      requestedDeviceID = rememberedRequest
      lastConfiguration = configuration
    } catch {
      reconnectingDeviceID = id
    }
  }

  private func dismissOverlay(
    preserveSelection: Bool,
    invalidatePendingPresentation: Bool = true
  ) {
    if invalidatePendingPresentation {
      presentationGeneration &+= 1
    }
    previewSession?.stop()
    previewSession = nil
    overlayWindow?.close()
    overlayWindow = nil
    activeDeviceID = nil
    onOverlayWindowChanged?(nil)
    if !preserveSelection {
      requestedDeviceID = nil
    }
  }

  private func observeDeviceConnections() {
    let center = NotificationCenter.default
    deviceObserverTokens.append(center.addObserver(
      forName: AVCaptureDevice.wasDisconnectedNotification,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      guard let device = notification.object as? AVCaptureDevice else { return }
      Task { @MainActor in
        self?.handleDeviceDisconnected(id: device.uniqueID)
      }
    })
    deviceObserverTokens.append(center.addObserver(
      forName: AVCaptureDevice.wasConnectedNotification,
      object: nil,
      queue: .main
    ) { [weak self] notification in
      guard let device = notification.object as? AVCaptureDevice else { return }
      Task { @MainActor in
        await self?.handleDeviceConnected(id: device.uniqueID)
      }
    })
  }

  private func ensurePermission() async throws {
    switch hardware.authorizationStatus() {
    case .authorized:
      return
    case .notDetermined:
      guard await hardware.requestAccess() else {
        throw RecordingCameraError.permissionDenied
      }
    case .denied, .restricted:
      throw RecordingCameraError.permissionDenied
    @unknown default:
      throw RecordingCameraError.permissionDenied
    }
  }

  private func resolvedDeviceID(
    requestedID: String,
    devices: [RecordingCameraDevice]
  ) -> String? {
    if requestedID != RecordingCameraDevice.systemPreferredID,
       devices.contains(where: { $0.id == requestedID }) {
      return requestedID
    }

    if let preferredID = hardware.systemPreferredDeviceID,
       devices.contains(where: { $0.id == preferredID }) {
      return preferredID
    }

    return devices.first(where: \RecordingCameraDevice.isContinuityCamera)?.id
      ?? devices.first?.id
  }

  private func storedLayout() -> CameraOverlayLayout {
    guard let data = defaults.data(forKey: PreferencesKeys.recordingCameraLayout),
          let layout = try? JSONDecoder().decode(CameraOverlayLayout.self, from: data)
    else {
      return .default
    }
    return layout
  }

  private func storeLayout(_ layout: CameraOverlayLayout) {
    guard let data = try? JSONEncoder().encode(layout) else { return }
    defaults.set(data, forKey: PreferencesKeys.recordingCameraLayout)
  }
}

@MainActor
private final class AVFoundationRecordingCameraHardware: RecordingCameraHardware {
  var systemPreferredDeviceID: String? {
    AVCaptureDevice.systemPreferredCamera?.uniqueID
  }

  func authorizationStatus() -> AVAuthorizationStatus {
    AVCaptureDevice.authorizationStatus(for: .video)
  }

  func requestAccess() async -> Bool {
    await AVCaptureDevice.requestAccess(for: .video)
  }

  func availableDevices() -> [RecordingCameraDevice] {
    discoveredDevices().map {
      RecordingCameraDevice(
        id: $0.uniqueID,
        displayName: $0.localizedName,
        isContinuityCamera: $0.isContinuityCamera
      )
    }
  }

  func makeSession(deviceID: String, mirrored: Bool) throws -> RecordingCameraPreviewSession {
    guard let device = discoveredDevices().first(where: { $0.uniqueID == deviceID }) else {
      throw RecordingCameraError.deviceUnavailable
    }
    return try AVFoundationRecordingCameraPreviewSession(
      device: device,
      mirrored: mirrored
    )
  }

  private func discoveredDevices() -> [AVCaptureDevice] {
    let deviceTypes: [AVCaptureDevice.DeviceType]
    if #available(macOS 14.0, *) {
      deviceTypes = [.builtInWideAngleCamera, .external, .continuityCamera, .deskViewCamera]
    } else {
      deviceTypes = [.builtInWideAngleCamera, .externalUnknown, .deskViewCamera]
    }

    var devices = AVCaptureDevice.DiscoverySession(
      deviceTypes: deviceTypes,
      mediaType: .video,
      position: .unspecified
    ).devices

    if let preferred = AVCaptureDevice.systemPreferredCamera,
       !devices.contains(where: { $0.uniqueID == preferred.uniqueID }) {
      devices.insert(preferred, at: 0)
    }

    var seen = Set<String>()
    return devices.filter { seen.insert($0.uniqueID).inserted }
  }
}

@MainActor
private final class AVFoundationRecordingCameraPreviewSession: RecordingCameraPreviewSession {
  let previewLayer: CALayer

  private let captureSession: AVCaptureSession
  private let videoPreviewLayer: AVCaptureVideoPreviewLayer
  private let sessionQueue = DispatchQueue(
    label: "com.trongduong.snapzy.camera.session",
    qos: .userInitiated
  )

  init(device: AVCaptureDevice, mirrored: Bool) throws {
    let captureSession = AVCaptureSession()
    captureSession.beginConfiguration()
    captureSession.sessionPreset = .high

    let input = try AVCaptureDeviceInput(device: device)
    guard captureSession.canAddInput(input) else {
      captureSession.commitConfiguration()
      throw RecordingCameraError.cannotAddDeviceInput
    }
    captureSession.addInput(input)
    captureSession.commitConfiguration()

    let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
    previewLayer.videoGravity = .resizeAspectFill
    self.captureSession = captureSession
    self.videoPreviewLayer = previewLayer
    self.previewLayer = previewLayer
    setMirrored(mirrored)
  }

  func start() async {
    let captureSession = captureSession
    await withCheckedContinuation { continuation in
      sessionQueue.async {
        if !captureSession.isRunning {
          captureSession.startRunning()
        }
        continuation.resume()
      }
    }
  }

  func stop() {
    let captureSession = captureSession
    sessionQueue.async {
      guard captureSession.isRunning else { return }
      captureSession.stopRunning()
    }
  }

  func setMirrored(_ mirrored: Bool) {
    guard let connection = videoPreviewLayer.connection,
          connection.isVideoMirroringSupported
    else {
      return
    }
    connection.automaticallyAdjustsVideoMirroring = false
    connection.isVideoMirrored = mirrored
  }
}
