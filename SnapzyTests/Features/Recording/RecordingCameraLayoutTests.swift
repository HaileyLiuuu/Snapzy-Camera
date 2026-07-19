import AppKit
import QuartzCore
import XCTest
@testable import Snapzy

final class RecordingCameraLayoutTests: XCTestCase {

  func testDefaultWidescreenLayoutAnchorsAtBottomRight() {
    let recordingRect = CGRect(x: 0, y: 0, width: 1200, height: 800)

    let frame = CameraOverlayLayout.default.frame(
      in: recordingRect,
      shape: .widescreen
    )

    XCTAssertEqual(frame.width, 300, accuracy: 0.001)
    XCTAssertEqual(frame.height, 168.75, accuracy: 0.001)
    XCTAssertEqual(frame.maxX, recordingRect.maxX - 24, accuracy: 0.001)
    XCTAssertEqual(frame.minY, recordingRect.minY + 24, accuracy: 0.001)
  }

  func testMovedLayoutRestoresRelativePositionInDifferentRecordingRect() {
    let originalRect = CGRect(x: 0, y: 0, width: 1200, height: 800)
    let layout = CameraOverlayLayout(
      frame: CGRect(x: 100, y: 200, width: 320, height: 180),
      in: originalRect
    )

    let restored = layout.frame(
      in: CGRect(x: -500, y: 0, width: 800, height: 600),
      shape: .widescreen
    )

    XCTAssertEqual(restored.width, 800 * (320.0 / 1200.0), accuracy: 0.001)
    XCTAssertEqual(restored.midX, -500 + 800 * (260.0 / 1200.0), accuracy: 0.001)
    XCTAssertEqual(restored.midY, 600 * (290.0 / 800.0), accuracy: 0.001)
  }

  func testRestoredLayoutStaysInsideRecordingRectAndAtMostHalfSize() {
    let recordingRect = CGRect(x: 0, y: 0, width: 1000, height: 600)
    let layout = CameraOverlayLayout(
      normalizedCenterX: 1,
      normalizedCenterY: 1,
      normalizedWidth: 0.9
    )

    let frame = layout.frame(in: recordingRect, shape: .widescreen)

    XCTAssertEqual(frame.width, 500, accuracy: 0.001)
    XCTAssertLessThanOrEqual(frame.maxX, recordingRect.maxX)
    XCTAssertLessThanOrEqual(frame.maxY, recordingRect.maxY)
  }

  func testEveryShapeUsesItsExpectedAspectRatio() {
    let recordingRect = CGRect(x: 0, y: 0, width: 1200, height: 800)

    for shape in CameraOverlayShape.allCases {
      let frame = CameraOverlayLayout.default.frame(in: recordingRect, shape: shape)
      XCTAssertEqual(frame.width / frame.height, shape.aspectRatio, accuracy: 0.001)
    }
  }

  func testEveryShapeKeepsItsShortestEdgeAtLeast120Points() {
    let recordingRect = CGRect(x: 0, y: 0, width: 1200, height: 800)
    let undersizedLayout = CameraOverlayLayout(
      normalizedCenterX: 0.5,
      normalizedCenterY: 0.5,
      normalizedWidth: 0.01
    )

    for shape in CameraOverlayShape.allCases {
      let frame = undersizedLayout.frame(in: recordingRect, shape: shape)
      XCTAssertGreaterThanOrEqual(min(frame.width, frame.height), 120)
    }
  }

  func testCircleVisibleEdgeIsAResizeHitArea() {
    let bounds = CGRect(x: 0, y: 0, width: 240, height: 240)

    XCTAssertTrue(
      RecordingCameraCircleResizeGeometry.isEdgeHit(
        CGPoint(x: 238, y: 120),
        in: bounds
      )
    )
    XCTAssertFalse(
      RecordingCameraCircleResizeGeometry.isEdgeHit(
        CGPoint(x: 120, y: 120),
        in: bounds
      )
    )
    XCTAssertTrue(
      RecordingCameraCircleResizeGeometry.isEdgeHit(
        CGPoint(x: 220, y: 220),
        in: bounds
      )
    )
  }

  func testCircleEdgeDragResizesAboutItsCenter() {
    let initialFrame = CGRect(x: 700, y: 300, width: 240, height: 240)
    let center = CGPoint(x: initialFrame.midX, y: initialFrame.midY)

    let resized = RecordingCameraCircleResizeGeometry.resizedFrame(
      initialFrame: initialFrame,
      startPointer: CGPoint(x: center.x + 120, y: center.y),
      currentPointer: CGPoint(x: center.x + 150, y: center.y),
      recordingRect: CGRect(x: 0, y: 0, width: 1200, height: 800),
      minimumDiameter: 120,
      maximumDiameter: 400
    )

    XCTAssertEqual(resized.width, 300, accuracy: 0.001)
    XCTAssertEqual(resized.height, 300, accuracy: 0.001)
    XCTAssertEqual(resized.midX, initialFrame.midX, accuracy: 0.001)
    XCTAssertEqual(resized.midY, initialFrame.midY, accuracy: 0.001)
  }

  func testCircleCanGrowToConfiguredMaximumNearRecordingBoundary() {
    let recordingRect = CGRect(x: 0, y: 0, width: 1000, height: 800)
    let initialFrame = CGRect(x: 736, y: 24, width: 240, height: 240)

    let resized = RecordingCameraCircleResizeGeometry.resizedFrame(
      initialFrame: initialFrame,
      startPointer: CGPoint(x: initialFrame.maxX, y: initialFrame.midY),
      currentPointer: CGPoint(x: initialFrame.maxX + 80, y: initialFrame.midY),
      recordingRect: recordingRect,
      minimumDiameter: 120,
      maximumDiameter: 400
    )

    XCTAssertEqual(resized.width, 400, accuracy: 0.001)
    XCTAssertEqual(resized.height, 400, accuracy: 0.001)
    XCTAssertTrue(recordingRect.contains(resized))
  }

  func testResizeCursorDirectionExistsOnlyOnShapeEdges() {
    let boundsByShape: [(CameraOverlayShape, CGRect)] = [
      (.widescreen, CGRect(x: 0, y: 0, width: 240, height: 135)),
      (.circle, CGRect(x: 0, y: 0, width: 240, height: 240)),
      (.classic, CGRect(x: 0, y: 0, width: 240, height: 180)),
    ]

    for (shape, bounds) in boundsByShape {
      XCTAssertEqual(
        RecordingCameraResizeCursorGeometry.direction(
          at: CGPoint(x: bounds.midX, y: bounds.maxY - 1),
          in: bounds,
          shape: shape
        ),
        .vertical
      )
      XCTAssertEqual(
        RecordingCameraResizeCursorGeometry.direction(
          at: CGPoint(x: bounds.minX + 1, y: bounds.midY),
          in: bounds,
          shape: shape
        ),
        .horizontal
      )
      XCTAssertNil(RecordingCameraResizeCursorGeometry.direction(
        at: CGPoint(x: bounds.midX, y: bounds.midY),
        in: bounds,
        shape: shape
      ))
      XCTAssertNil(RecordingCameraResizeCursorGeometry.direction(
        at: CGPoint(x: bounds.maxX + 10, y: bounds.midY),
        in: bounds,
        shape: shape
      ))
    }
  }

  func testPreviewShowsResizeCursorAtEdgeAndArrowInside() throws {
    defer { NSCursor.arrow.set() }

    for shape in CameraOverlayShape.allCases {
      let height = 240 / shape.aspectRatio
      let window = RecordingCameraOverlayWindow(
        frame: CGRect(x: 300, y: 200, width: 240, height: height),
        recordingRect: CGRect(x: 0, y: 0, width: 1000, height: 800),
        shape: shape,
        previewLayer: CALayer()
      )
      let previewView = try XCTUnwrap(window.contentView)

      previewView.mouseMoved(with: try mouseEvent(
        .mouseMoved,
        location: CGPoint(x: 120, y: height - 1),
        in: window
      ))
      XCTAssertTrue(NSCursor.current === NSCursor.resizeUpDown)

      previewView.mouseMoved(with: try mouseEvent(
        .mouseMoved,
        location: CGPoint(x: 120, y: height / 2),
        in: window
      ))
      XCTAssertTrue(NSCursor.current === NSCursor.arrow)
    }
  }

  func testCircleWindowReceivesEdgeDragAndResizes() throws {
    let initialFrame = CGRect(x: 300, y: 200, width: 240, height: 240)
    let window = RecordingCameraOverlayWindow(
      frame: initialFrame,
      recordingRect: CGRect(x: 0, y: 0, width: 1000, height: 800),
      shape: .circle,
      previewLayer: CALayer()
    )
    let previewView = try XCTUnwrap(window.contentView)

    XCTAssertFalse(previewView.mouseDownCanMoveWindow)
    previewView.mouseDown(with: try mouseEvent(
      .leftMouseDown,
      location: CGPoint(x: 238, y: 120),
      in: window
    ))
    previewView.mouseDragged(with: try mouseEvent(
      .leftMouseDragged,
      location: CGPoint(x: 268, y: 120),
      in: window
    ))
    previewView.mouseUp(with: try mouseEvent(
      .leftMouseUp,
      location: CGPoint(x: 268, y: 120),
      in: window
    ))

    XCTAssertEqual(window.frame.width, 300, accuracy: 0.001)
    XCTAssertEqual(window.frame.height, 300, accuracy: 0.001)
  }

  func testRectangleShapesKeepNativeWindowDragging() throws {
    for shape in [CameraOverlayShape.widescreen, .classic] {
      let window = RecordingCameraOverlayWindow(
        frame: CGRect(x: 300, y: 200, width: 240, height: 240 / shape.aspectRatio),
        recordingRect: CGRect(x: 0, y: 0, width: 1000, height: 800),
        shape: shape,
        previewLayer: CALayer()
      )

      XCTAssertTrue(try XCTUnwrap(window.contentView).mouseDownCanMoveWindow)
    }
  }

  private func mouseEvent(
    _ type: NSEvent.EventType,
    location: CGPoint,
    in window: NSWindow
  ) throws -> NSEvent {
    try XCTUnwrap(NSEvent.mouseEvent(
      with: type,
      location: location,
      modifierFlags: [],
      timestamp: 0,
      windowNumber: window.windowNumber,
      context: nil,
      eventNumber: 0,
      clickCount: 1,
      pressure: 1
    ))
  }
}
