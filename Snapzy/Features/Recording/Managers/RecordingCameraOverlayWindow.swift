import AppKit
import QuartzCore

enum RecordingCameraResizeCursorDirection: Equatable {
  case horizontal
  case vertical

  var cursor: NSCursor {
    switch self {
    case .horizontal: return .resizeLeftRight
    case .vertical: return .resizeUpDown
    }
  }
}

enum RecordingCameraResizeCursorGeometry {
  private static let rectangleEdgeThickness: CGFloat = 8

  static func direction(
    at point: CGPoint,
    in bounds: CGRect,
    shape: CameraOverlayShape
  ) -> RecordingCameraResizeCursorDirection? {
    guard bounds.contains(point) else { return nil }

    if shape == .circle {
      guard RecordingCameraCircleResizeGeometry.isEdgeHit(point, in: bounds) else {
        return nil
      }
      let horizontalDistance = abs(point.x - bounds.midX)
      let verticalDistance = abs(point.y - bounds.midY)
      return horizontalDistance > verticalDistance ? .horizontal : .vertical
    }

    let horizontalEdgeDistance = min(
      point.x - bounds.minX,
      bounds.maxX - point.x
    )
    let verticalEdgeDistance = min(
      point.y - bounds.minY,
      bounds.maxY - point.y
    )
    let nearestEdgeDistance = min(horizontalEdgeDistance, verticalEdgeDistance)
    guard nearestEdgeDistance <= rectangleEdgeThickness else { return nil }
    return horizontalEdgeDistance < verticalEdgeDistance ? .horizontal : .vertical
  }
}

enum RecordingCameraCircleResizeGeometry {
  private static let edgeHitThickness: CGFloat = 24

  static func isEdgeHit(_ point: CGPoint, in bounds: CGRect) -> Bool {
    let radius = min(bounds.width, bounds.height) / 2
    guard radius > 0 else { return false }

    let distance = hypot(point.x - bounds.midX, point.y - bounds.midY)
    return distance >= radius - edgeHitThickness
      && distance <= radius + edgeHitThickness
  }

  static func resizedFrame(
    initialFrame: CGRect,
    startPointer: CGPoint,
    currentPointer: CGPoint,
    recordingRect: CGRect,
    minimumDiameter: CGFloat,
    maximumDiameter: CGFloat
  ) -> CGRect {
    let center = CGPoint(x: initialFrame.midX, y: initialFrame.midY)
    let startRadius = hypot(startPointer.x - center.x, startPointer.y - center.y)
    let currentRadius = hypot(currentPointer.x - center.x, currentPointer.y - center.y)
    let upperBound = max(
      0,
      min(maximumDiameter, recordingRect.width, recordingRect.height)
    )
    let lowerBound = min(minimumDiameter, upperBound)
    let diameter = min(
      upperBound,
      max(lowerBound, initialFrame.width + 2 * (currentRadius - startRadius))
    )
    let centeredFrame = CGRect(
      x: center.x - diameter / 2,
      y: center.y - diameter / 2,
      width: diameter,
      height: diameter
    )
    let x = min(
      max(centeredFrame.minX, recordingRect.minX),
      recordingRect.maxX - diameter
    )
    let y = min(
      max(centeredFrame.minY, recordingRect.minY),
      recordingRect.maxY - diameter
    )
    return CGRect(x: x, y: y, width: diameter, height: diameter)
  }
}

@MainActor
final class RecordingCameraOverlayWindow: NSWindow {
  var onFrameChanged: ((CGRect) -> Void)?

  private let previewView: RecordingCameraPreviewView
  private var recordingRect: CGRect
  private var circleResizeSession: (initialFrame: CGRect, startPointer: CGPoint)?

  init(
    frame: CGRect,
    recordingRect: CGRect,
    shape: CameraOverlayShape,
    previewLayer: CALayer
  ) {
    self.recordingRect = recordingRect
    self.previewView = RecordingCameraPreviewView(
      frame: CGRect(origin: .zero, size: frame.size),
      shape: shape,
      previewLayer: previewLayer
    )

    super.init(
      contentRect: frame,
      styleMask: [.borderless, .resizable],
      backing: .buffered,
      defer: false
    )

    isOpaque = false
    backgroundColor = .clear
    hasShadow = true
    isReleasedWhenClosed = false
    level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 2)
    collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    isMovableByWindowBackground = true
    contentView = previewView
    previewView.onCircleResizeBegan = { [weak self] pointer in
      guard let self else { return }
      self.circleResizeSession = (self.frame, pointer)
    }
    previewView.onCircleResizeChanged = { [weak self] pointer in
      guard let self, let session = self.circleResizeSession else { return }
      let resizedFrame = RecordingCameraCircleResizeGeometry.resizedFrame(
        initialFrame: session.initialFrame,
        startPointer: session.startPointer,
        currentPointer: pointer,
        recordingRect: self.recordingRect,
        minimumDiameter: self.contentMinSize.width,
        maximumDiameter: self.contentMaxSize.width
      )
      self.setFrame(resizedFrame, display: true)
    }
    previewView.onCircleResizeEnded = { [weak self] in
      self?.circleResizeSession = nil
    }
    configureSizing(for: shape)

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(windowFrameChanged),
      name: NSWindow.didMoveNotification,
      object: self
    )
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(windowFrameChanged),
      name: NSWindow.didResizeNotification,
      object: self
    )
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  func update(
    frame: CGRect,
    recordingRect: CGRect,
    shape: CameraOverlayShape
  ) {
    self.recordingRect = recordingRect
    circleResizeSession = nil
    configureSizing(for: shape)
    setFrame(frame, display: true)
    previewView.update(shape: shape)
  }

  @objc private func windowFrameChanged() {
    let clampedFrame = clamped(frame, within: recordingRect)
    if clampedFrame != frame {
      setFrame(clampedFrame, display: true)
    }
    onFrameChanged?(clampedFrame)
  }

  private func clamped(_ frame: CGRect, within rect: CGRect) -> CGRect {
    let x = min(max(frame.minX, rect.minX), rect.maxX - frame.width)
    let y = min(max(frame.minY, rect.minY), rect.maxY - frame.height)
    return CGRect(origin: CGPoint(x: x, y: y), size: frame.size)
  }

  private func configureSizing(for shape: CameraOverlayShape) {
    contentAspectRatio = CGSize(width: shape.aspectRatio, height: 1)
    let maximumWidth = max(
      0,
      min(recordingRect.width * 0.5, recordingRect.height * 0.5 * shape.aspectRatio)
    )
    let minimumWidth = min(120 * max(1, shape.aspectRatio), maximumWidth)
    contentMinSize = CGSize(
      width: minimumWidth,
      height: minimumWidth / shape.aspectRatio
    )
    contentMaxSize = CGSize(
      width: maximumWidth,
      height: maximumWidth / shape.aspectRatio
    )
  }
}

@MainActor
private final class RecordingCameraPreviewView: NSView {
  var onCircleResizeBegan: ((CGPoint) -> Void)?
  var onCircleResizeChanged: ((CGPoint) -> Void)?
  var onCircleResizeEnded: (() -> Void)?

  private let previewLayer: CALayer
  private let borderLayer = CAShapeLayer()
  private var shape: CameraOverlayShape
  private var isResizingCircle = false
  private var cursorTrackingArea: NSTrackingArea?

  init(frame: CGRect, shape: CameraOverlayShape, previewLayer: CALayer) {
    self.previewLayer = previewLayer
    self.shape = shape
    super.init(frame: frame)
    wantsLayer = true
    layer?.backgroundColor = NSColor.black.cgColor
    layer?.addSublayer(previewLayer)
    layer?.addSublayer(borderLayer)
    borderLayer.fillColor = NSColor.clear.cgColor
    borderLayer.strokeColor = NSColor.white.withAlphaComponent(0.72).cgColor
    borderLayer.lineWidth = 2
    updateLayers()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not supported")
  }

  override var mouseDownCanMoveWindow: Bool {
    shape != .circle
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    shape == .circle || super.acceptsFirstMouse(for: event)
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    window?.acceptsMouseMovedEvents = true
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let cursorTrackingArea {
      removeTrackingArea(cursorTrackingArea)
    }
    let trackingArea = NSTrackingArea(
      rect: .zero,
      options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
      owner: self,
      userInfo: nil
    )
    addTrackingArea(trackingArea)
    cursorTrackingArea = trackingArea
  }

  override func mouseEntered(with event: NSEvent) {
    updateCursor(for: event)
  }

  override func mouseMoved(with event: NSEvent) {
    updateCursor(for: event)
  }

  override func mouseDown(with event: NSEvent) {
    guard shape == .circle else {
      super.mouseDown(with: event)
      return
    }

    let point = convert(event.locationInWindow, from: nil)
    guard RecordingCameraCircleResizeGeometry.isEdgeHit(point, in: bounds) else {
      window?.performDrag(with: event)
      return
    }

    isResizingCircle = true
    onCircleResizeBegan?(screenPoint(for: event))
  }

  override func mouseDragged(with event: NSEvent) {
    guard isResizingCircle else {
      super.mouseDragged(with: event)
      return
    }
    onCircleResizeChanged?(screenPoint(for: event))
  }

  override func mouseUp(with event: NSEvent) {
    guard isResizingCircle else {
      super.mouseUp(with: event)
      return
    }
    isResizingCircle = false
    onCircleResizeEnded?()
  }

  override func layout() {
    super.layout()
    updateLayers()
  }

  func update(shape: CameraOverlayShape) {
    self.shape = shape
    isResizingCircle = false
    updateLayers()
  }

  private func screenPoint(for event: NSEvent) -> CGPoint {
    window?.convertPoint(toScreen: event.locationInWindow) ?? NSEvent.mouseLocation
  }

  private func updateCursor(for event: NSEvent) {
    let point = convert(event.locationInWindow, from: nil)
    let direction = RecordingCameraResizeCursorGeometry.direction(
      at: point,
      in: bounds,
      shape: shape
    )
    (direction?.cursor ?? .arrow).set()
  }

  private func updateLayers() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    previewLayer.frame = bounds
    let radius = shape == .circle ? min(bounds.width, bounds.height) / 2 : 18
    layer?.cornerRadius = radius
    layer?.masksToBounds = true
    borderLayer.frame = bounds
    borderLayer.path = CGPath(
      roundedRect: bounds.insetBy(dx: 1, dy: 1),
      cornerWidth: max(0, radius - 1),
      cornerHeight: max(0, radius - 1),
      transform: nil
    )
    CATransaction.commit()
  }
}
