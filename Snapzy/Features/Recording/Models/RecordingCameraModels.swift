import CoreGraphics
import Foundation

enum CameraOverlayShape: String, CaseIterable, Codable {
  case widescreen
  case circle
  case classic

  var aspectRatio: CGFloat {
    switch self {
    case .widescreen: return 16.0 / 9.0
    case .circle: return 1.0
    case .classic: return 4.0 / 3.0
    }
  }

  var displayName: String {
    switch self {
    case .widescreen: return L10n.Camera.shapeWidescreen
    case .circle: return L10n.Camera.shapeCircle
    case .classic: return L10n.Camera.shapeClassic
    }
  }
}

struct CameraOverlayLayout: Codable, Equatable {
  static let `default` = CameraOverlayLayout(
    normalizedCenterX: 0,
    normalizedCenterY: 0,
    normalizedWidth: 0,
    usesDefaultPlacement: true
  )

  var normalizedCenterX: CGFloat
  var normalizedCenterY: CGFloat
  var normalizedWidth: CGFloat
  var usesDefaultPlacement: Bool

  init(
    normalizedCenterX: CGFloat,
    normalizedCenterY: CGFloat,
    normalizedWidth: CGFloat,
    usesDefaultPlacement: Bool = false
  ) {
    self.normalizedCenterX = normalizedCenterX
    self.normalizedCenterY = normalizedCenterY
    self.normalizedWidth = normalizedWidth
    self.usesDefaultPlacement = usesDefaultPlacement
  }

  init(frame: CGRect, in recordingRect: CGRect) {
    guard recordingRect.width > 0, recordingRect.height > 0 else {
      self = .default
      return
    }

    self.init(
      normalizedCenterX: (frame.midX - recordingRect.minX) / recordingRect.width,
      normalizedCenterY: (frame.midY - recordingRect.minY) / recordingRect.height,
      normalizedWidth: frame.width / recordingRect.width
    )
  }

  func frame(in recordingRect: CGRect, shape: CameraOverlayShape) -> CGRect {
    if usesDefaultPlacement {
      return Self.defaultFrame(in: recordingRect, shape: shape)
    }

    let proposedWidth = recordingRect.width * normalizedWidth
    let width = Self.constrainedWidth(
      proposedWidth,
      in: recordingRect,
      shape: shape
    )
    let height = width / shape.aspectRatio
    let center = CGPoint(
      x: recordingRect.minX + recordingRect.width * normalizedCenterX,
      y: recordingRect.minY + recordingRect.height * normalizedCenterY
    )
    return Self.clamped(
      CGRect(
      x: center.x - width / 2,
      y: center.y - height / 2,
      width: width,
      height: height
      ),
      within: recordingRect
    )
  }

  private static func defaultFrame(
    in recordingRect: CGRect,
    shape: CameraOverlayShape
  ) -> CGRect {
    let edgeInset: CGFloat = 24
    let preferredWidth = min(360, max(200, recordingRect.width * 0.25))
    let availableWidth = max(0, recordingRect.width - edgeInset * 2)
    let availableHeight = max(0, recordingRect.height - edgeInset * 2)
    var width = min(
      Self.constrainedWidth(preferredWidth, in: recordingRect, shape: shape),
      availableWidth
    )
    var height = width / shape.aspectRatio

    if height > availableHeight {
      height = availableHeight
      width = height * shape.aspectRatio
    }

    return CGRect(
      x: recordingRect.maxX - edgeInset - width,
      y: recordingRect.minY + edgeInset,
      width: width,
      height: height
    )
  }

  private static func constrainedWidth(
    _ proposedWidth: CGFloat,
    in recordingRect: CGRect,
    shape: CameraOverlayShape
  ) -> CGFloat {
    let maximumWidth = max(
      0,
      min(recordingRect.width * 0.5, recordingRect.height * 0.5 * shape.aspectRatio)
    )
    let minimumWidth = min(120 * max(1, shape.aspectRatio), maximumWidth)
    return min(maximumWidth, max(minimumWidth, proposedWidth))
  }

  private static func clamped(_ frame: CGRect, within recordingRect: CGRect) -> CGRect {
    guard !recordingRect.isEmpty else { return frame }
    let x = min(max(frame.minX, recordingRect.minX), recordingRect.maxX - frame.width)
    let y = min(max(frame.minY, recordingRect.minY), recordingRect.maxY - frame.height)
    return CGRect(origin: CGPoint(x: x, y: y), size: frame.size)
  }
}

struct RecordingCameraDevice: Identifiable, Equatable {
  static let systemPreferredID = "__system_preferred_camera__"

  let id: String
  let displayName: String
  let isContinuityCamera: Bool
}

struct RecordingCameraConfiguration: Equatable {
  let deviceID: String
  let shape: CameraOverlayShape
  let mirrored: Bool
}
