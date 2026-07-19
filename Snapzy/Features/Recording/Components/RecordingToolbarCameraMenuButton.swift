import AVFoundation
import SwiftUI

@MainActor
struct ToolbarCameraMenuButton: View {
  @ObservedObject var state: RecordingToolbarState
  @State private var isHovered = false
  @State private var showPermissionDeniedAlert = false

  var body: some View {
    Menu {
      cameraSelectionItems

      Divider()

      Menu(L10n.Camera.shape) {
        ForEach(CameraOverlayShape.allCases, id: \.self) { shape in
          Button {
            selectShape(shape)
          } label: {
            menuItemLabel(
              title: shape.displayName,
              isSelected: state.cameraShape == shape
            )
          }
        }
      }

      Button {
        toggleMirroring()
      } label: {
        menuItemLabel(
          title: L10n.Camera.mirrored,
          isSelected: state.cameraMirrored
        )
      }
    } label: {
      ToolbarIconButtonLabel(
        systemName: state.captureCamera ? "video.fill" : "video.slash.fill",
        isHovered: isHovered
      )
    }
    .menuStyle(.borderlessButton)
    .menuIndicator(.hidden)
    .buttonStyle(.plain)
    .frame(
      width: ToolbarConstants.iconButtonSize,
      height: ToolbarConstants.iconButtonSize
    )
    .onHover { isHovered = $0 }
    .help(state.captureCamera ? L10n.Camera.on : L10n.Camera.off)
    .accessibilityLabel(L10n.Camera.options)
    .accessibilityHint(L10n.Camera.chooseInput)
    .alert(L10n.Camera.accessRequiredTitle, isPresented: $showPermissionDeniedAlert) {
      Button(L10n.Common.openSystemSettings) {
        openCameraSettings()
      }
      Button(L10n.Common.cancel, role: .cancel) {}
    } message: {
      Text(L10n.Camera.permissionMessage)
    }
  }

  @ViewBuilder
  private var cameraSelectionItems: some View {
    Button {
      disableCamera()
    } label: {
      menuItemLabel(title: L10n.Camera.doNotUse, isSelected: !state.captureCamera)
    }

    Divider()

    Button {
      selectCamera(deviceID: RecordingCameraDevice.systemPreferredID)
    } label: {
      menuItemLabel(
        title: L10n.Camera.systemPreferred,
        isSelected: state.captureCamera
          && state.cameraDeviceID == RecordingCameraDevice.systemPreferredID
      )
    }

    let devices = RecordingCameraController.shared.availableDevices()
    if devices.isEmpty {
      Text(L10n.Camera.noCameraAvailable)
    } else {
      ForEach(devices) { device in
        Button {
          selectCamera(deviceID: device.id)
        } label: {
          menuItemLabel(
            title: device.displayName,
            isSelected: state.captureCamera && state.cameraDeviceID == device.id
          )
        }
      }
    }
  }

  @ViewBuilder
  private func menuItemLabel(title: String, isSelected: Bool) -> some View {
    if isSelected {
      Label(title, systemImage: "checkmark")
    } else {
      Text(title)
    }
  }

  private func selectCamera(deviceID: String) {
    switch AVCaptureDevice.authorizationStatus(for: .video) {
    case .notDetermined:
      Task {
        let granted = await AVCaptureDevice.requestAccess(for: .video)
        await MainActor.run {
          if granted {
            enableCamera(deviceID: deviceID)
          } else {
            showPermissionDeniedAlert = true
          }
        }
      }
    case .authorized:
      enableCamera(deviceID: deviceID)
    case .denied, .restricted:
      showPermissionDeniedAlert = true
    @unknown default:
      showPermissionDeniedAlert = true
    }
  }

  private func enableCamera(deviceID: String) {
    state.cameraDeviceID = deviceID
    state.captureCamera = true
    UserDefaults.standard.set(deviceID, forKey: PreferencesKeys.recordingCameraDeviceID)
    UserDefaults.standard.set(true, forKey: PreferencesKeys.recordingCaptureCamera)
    state.onCameraConfigurationChanged?()
  }

  private func disableCamera() {
    state.captureCamera = false
    UserDefaults.standard.set(false, forKey: PreferencesKeys.recordingCaptureCamera)
    state.onCameraConfigurationChanged?()
  }

  private func selectShape(_ shape: CameraOverlayShape) {
    state.cameraShape = shape
    UserDefaults.standard.set(shape.rawValue, forKey: PreferencesKeys.recordingCameraShape)
    state.onCameraConfigurationChanged?()
  }

  private func toggleMirroring() {
    state.cameraMirrored.toggle()
    UserDefaults.standard.set(state.cameraMirrored, forKey: PreferencesKeys.recordingCameraMirrored)
    state.onCameraConfigurationChanged?()
  }

  private func openCameraSettings() {
    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") {
      NSWorkspace.shared.open(url)
    }
  }
}
