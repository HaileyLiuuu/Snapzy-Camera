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

  func testElbow_defaultControlPoint_horizontalDominant() {
    let geo = ArrowGeometry(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 30), style: .elbow)
    let points = geo.sampledPoints()
    XCTAssertEqual(points.count, 3)
    XCTAssertEqual(points[0], CGPoint(x: 0, y: 0))
    XCTAssertEqual(points[1], CGPoint(x: 100, y: 0))
    XCTAssertEqual(points[2], CGPoint(x: 100, y: 30))
  }

  func testElbow_defaultControlPoint_verticalDominant() {
    let geo = ArrowGeometry(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 20, y: 100), style: .elbow)
    let points = geo.sampledPoints()
    XCTAssertEqual(points.count, 3)
    XCTAssertEqual(points[0], CGPoint(x: 0, y: 0))
    XCTAssertEqual(points[1], CGPoint(x: 0, y: 100))
    XCTAssertEqual(points[2], CGPoint(x: 20, y: 100))
  }

  func testCurve_defaultControlPoint_offsetAboveMidpoint() {
    let geo = ArrowGeometry(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 0), style: .curve)
    let control = geo.resolvedControlPoint!
    XCTAssertEqual(control.x, 50, accuracy: 0.001)
    XCTAssertGreaterThan(control.y, 0)
  }

  func testCurve_sampledPoints_nonTrivial() {
    let geo = ArrowGeometry(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 100), style: .curve)
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
    let geo = ArrowGeometry(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 100), style: .curve)
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
    let elbow = geo.withStyle(.elbow)
    XCTAssertEqual(elbow.style, .elbow)
    XCTAssertEqual(elbow.start, geo.start)
    XCTAssertEqual(elbow.end, geo.end)
  }
}
