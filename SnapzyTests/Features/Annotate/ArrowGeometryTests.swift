//
//  ArrowGeometryTests.swift
//  SnapzyTests
//
//  Unit tests for ArrowGeometry path sampling, bounds, and transforms.
//

import CoreGraphics
import XCTest
@testable import Snapzy

final class ArrowGeometryTests: XCTestCase {

  // MARK: - sampledPoints / deduplication

  func testStraightLine_pointsAreStartAndEnd() {
    let geo = ArrowGeometry(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 0), style: .straight)
    XCTAssertEqual(geo.sampledPoints(), [CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 0)])
  }

  func testStraightLine_deduplicatesCoincidentPoints() {
    let geo = ArrowGeometry(start: CGPoint(x: 10, y: 10), end: CGPoint(x: 10, y: 10), style: .straight)
    XCTAssertEqual(geo.sampledPoints(), [CGPoint(x: 10, y: 10)])
  }

  func testCurvedRight_defaultControlPoint_offsetBelowMidpoint() {
    let geo = ArrowGeometry(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 0), style: .curvedRight)
    let control = geo.resolvedControlPoint!
    XCTAssertEqual(control.x, 50, accuracy: 0.001)
    XCTAssertLessThan(control.y, 0)
    XCTAssertEqual(geo.bendDirection, .alternate)
  }

  func testCurvedLeft_defaultControlPoint_offsetAboveMidpoint() {
    let geo = ArrowGeometry(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 0), style: .curvedLeft)
    let control = geo.resolvedControlPoint!
    XCTAssertEqual(control.x, 50, accuracy: 0.001)
    XCTAssertGreaterThan(control.y, 0)
    XCTAssertEqual(geo.bendDirection, .primary)
  }

  func testCurvedRight_sampledPoints_nonTrivial() {
    let geo = ArrowGeometry(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 100), style: .curvedRight)
    let points = geo.sampledPoints()
    XCTAssertEqual(points.count, 17)
    XCTAssertEqual(points.first, geo.start)
    XCTAssertEqual(points.last, geo.end)
  }

  // MARK: - isRenderable

  func testStraightLine_differentPoints_isRenderable() {
    let geo = ArrowGeometry(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 10, y: 10), style: .straight)
    XCTAssertTrue(geo.isRenderable)
  }

  func testStraightLine_samePoint_isNotRenderable() {
    let geo = ArrowGeometry(start: CGPoint(x: 5, y: 5), end: CGPoint(x: 5, y: 5), style: .straight)
    XCTAssertFalse(geo.isRenderable)
  }

  // MARK: - tangentAngleAtEnd

  func testTangentAngle_straight() {
    let geo = ArrowGeometry(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 0), style: .straight)
    XCTAssertEqual(geo.tangentAngleAtEnd(), 0, accuracy: 0.001)
  }

  func testTangentAngle_straightUp() {
    let geo = ArrowGeometry(start: CGPoint(x: 0, y: 100), end: CGPoint(x: 0, y: 0), style: .straight)
    XCTAssertEqual(geo.tangentAngleAtEnd(), -.pi / 2, accuracy: 0.001)
  }

  // MARK: - bounds

  func testBounds_straight() {
    let geo = ArrowGeometry(start: CGPoint(x: 10, y: 20), end: CGPoint(x: 50, y: 80), style: .straight)
    let b = geo.bounds()
    XCTAssertEqual(b.minX, 10, accuracy: 0.001)
    XCTAssertEqual(b.minY, 20, accuracy: 0.001)
    XCTAssertGreaterThanOrEqual(b.width, 1)
    XCTAssertGreaterThanOrEqual(b.height, 1)
  }

  func testBounds_zeroSize_enforcesMinimum() {
    let geo = ArrowGeometry(start: CGPoint(x: 5, y: 5), end: CGPoint(x: 5, y: 5), style: .straight)
    let b = geo.bounds()
    XCTAssertEqual(b.width, 1, accuracy: 0.001)
    XCTAssertEqual(b.height, 1, accuracy: 0.001)
  }

  // MARK: - translatedBy

  func testTranslatedBy() {
    let geo = ArrowGeometry(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 100), style: .curvedRight)
    let moved = geo.translatedBy(dx: 10, dy: -5)
    XCTAssertEqual(moved.start, CGPoint(x: 10, y: -5))
    XCTAssertEqual(moved.end, CGPoint(x: 110, y: 95))
  }

  // MARK: - remapped

  func testRemapped() {
    let geo = ArrowGeometry(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 100), style: .straight)
    let remapped = geo.remapped(from: CGRect(x: 0, y: 0, width: 100, height: 100), to: CGRect(x: 0, y: 0, width: 200, height: 200))
    XCTAssertEqual(remapped.start, CGPoint(x: 0, y: 0))
    XCTAssertEqual(remapped.end, CGPoint(x: 200, y: 200))
  }

  // MARK: - withStyle

  func testWithStyle() {
    let geo = ArrowGeometry(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 10, y: 10), style: .straight)
    let curved = geo.withStyle(.curvedRight)
    XCTAssertEqual(curved.style, .curvedRight)
    XCTAssertEqual(curved.start, geo.start)
    XCTAssertEqual(curved.end, geo.end)
  }

  func testWithStyle_preservesAlternateBendBetweenCurvedStyles() {
    let geo = ArrowGeometry(
      start: CGPoint(x: 0, y: 0),
      end: CGPoint(x: 100, y: 30),
      style: .curvedLeft
    )
    let curvedRight = geo.withStyle(.curvedRight)
    XCTAssertEqual(curvedRight.style, .curvedRight)
    XCTAssertEqual(curvedRight.bendDirection, .alternate)
  }

  func testWithBendDirection_mirrorsRemappedCurveControlPointAcrossBaseline() throws {
    let original = ArrowGeometry(
      start: CGPoint(x: 0, y: 0),
      end: CGPoint(x: 100, y: 0),
      style: .curvedLeft,
      controlPoint: CGPoint(x: 30, y: 50)
    )
    let remapped = original.remapped(
      from: CGRect(x: 0, y: 0, width: 100, height: 50),
      to: CGRect(x: 10, y: 20, width: 180, height: 90)
    )
    let control = try XCTUnwrap(remapped.resolvedControlPoint)

    let flipped = remapped.withBendDirection(.alternate)
    let flippedControl = try XCTUnwrap(flipped.resolvedControlPoint)

    XCTAssertEqual(flipped.bendDirection, .alternate)
    XCTAssertEqual(flipped.style, .curvedRight)
    XCTAssertEqual(
      baselineProgress(flippedControl, start: remapped.start, end: remapped.end),
      baselineProgress(control, start: remapped.start, end: remapped.end),
      accuracy: 0.001
    )
    XCTAssertEqual(
      signedPerpendicularDistance(flippedControl, start: remapped.start, end: remapped.end),
      -signedPerpendicularDistance(control, start: remapped.start, end: remapped.end),
      accuracy: 0.001
    )
  }

  private func signedPerpendicularDistance(_ point: CGPoint, start: CGPoint, end: CGPoint) -> CGFloat {
    let dx = end.x - start.x
    let dy = end.y - start.y
    let length = max(hypot(dx, dy), 0.0001)
    let normal = CGPoint(x: -dy / length, y: dx / length)
    return (point.x - start.x) * normal.x + (point.y - start.y) * normal.y
  }

  private func baselineProgress(_ point: CGPoint, start: CGPoint, end: CGPoint) -> CGFloat {
    let dx = end.x - start.x
    let dy = end.y - start.y
    let lengthSquared = max(dx * dx + dy * dy, 0.0001)
    return ((point.x - start.x) * dx + (point.y - start.y) * dy) / lengthSquared
  }

  // MARK: - arrowType & backwards compatibility

  func testArrowType_defaultsToTapered() {
    let geo = ArrowGeometry(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 100), style: .straight)
    XCTAssertEqual(geo.arrowType, .tapered)
  }

  func testArrowType_withArrowType() {
    let geo = ArrowGeometry(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 100), style: .straight)
    let classic = geo.withArrowType(.classic)
    XCTAssertEqual(classic.arrowType, .classic)
    XCTAssertEqual(classic.start, geo.start)
    XCTAssertEqual(classic.end, geo.end)
    XCTAssertEqual(classic.style, geo.style)

    let outlined = geo.withArrowType(.outlined)
    XCTAssertEqual(outlined.arrowType, .outlined)
  }

  func testArrowType_translatedBy_preservesArrowType() {
    let geo = ArrowGeometry(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 100), style: .straight, arrowType: .classic)
    let translated = geo.translatedBy(dx: 10, dy: 10)
    XCTAssertEqual(translated.arrowType, .classic)
  }

  func testArrowType_remapped_preservesArrowType() {
    let geo = ArrowGeometry(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 100), style: .straight, arrowType: .classic)
    let remapped = geo.remapped(from: CGRect(x: 0, y: 0, width: 100, height: 100), to: CGRect(x: 0, y: 0, width: 200, height: 200))
    XCTAssertEqual(remapped.arrowType, .classic)
  }

  func testArrowType_persistence_roundtrips() {
    let geo = ArrowGeometry(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 100), style: .straight, arrowType: .classic)
    let persisted = PersistedArrowGeometry(geometry: geo)
    XCTAssertEqual(persisted.arrowType, "classic")
    
    let restored = persisted.arrowGeometry
    XCTAssertEqual(restored.arrowType, .classic)
  }

  func testArrowType_persistence_backwardCompatibility() {
    // A persisted geometry without arrowType (from older versions of the app)
    let persisted = PersistedArrowGeometry(geometry: ArrowGeometry(start: .zero, end: .zero, style: .straight))
    // Simulate older save where arrowType field is missing/nil
    var dictionaryRepresentation = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(persisted), options: []) as! [String: Any]
    dictionaryRepresentation.removeValue(forKey: "arrowType")
    
    let serializedData = try! JSONSerialization.data(withJSONObject: dictionaryRepresentation, options: [])
    let decoded = try! JSONDecoder().decode(PersistedArrowGeometry.self, from: serializedData)
    
    XCTAssertNil(decoded.arrowType)
    XCTAssertEqual(decoded.arrowGeometry.arrowType, .outlined) // Backwards compatible default
  }

  func testWithStyle_mirrorsControlPointBetweenCurvedStyles() {
    let geo = ArrowGeometry(
      start: CGPoint(x: 0, y: 0),
      end: CGPoint(x: 100, y: 0),
      style: .curvedLeft,
      controlPoint: CGPoint(x: 30, y: 50)
    )
    let curvedRight = geo.withStyle(.curvedRight)
    XCTAssertEqual(curvedRight.style, .curvedRight)
    XCTAssertEqual(curvedRight.bendDirection, .alternate)
    
    let control = curvedRight.resolvedControlPoint!
    // The control point should be mirrored across the baseline (y = 0)
    XCTAssertEqual(control.x, 30, accuracy: 0.001)
    XCTAssertEqual(control.y, -50, accuracy: 0.001)
  }

  func testWithStyle_straightToCurved_computesDefaultControlPoint() {
    let geo = ArrowGeometry(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 0), style: .straight)
    let curved = geo.withStyle(.curvedRight)
    XCTAssertEqual(curved.style, .curvedRight)
    XCTAssertNotNil(curved.resolvedControlPoint)
  }
}
