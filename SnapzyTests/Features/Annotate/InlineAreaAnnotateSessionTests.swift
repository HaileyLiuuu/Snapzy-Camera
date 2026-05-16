//
//  InlineAreaAnnotateSessionTests.swift
//  SnapzyTests
//
//  Unit tests for InlineAreaAnnotateSession coordinate conversion helpers.
//

import CoreGraphics
import XCTest
@testable import Snapzy

final class InlineAreaAnnotateSessionTests: XCTestCase {

  // MARK: - desktopFrame

  func testDesktopFrame_unionsScreenFrames() {
    let frames = [
      CGRect(x: 0, y: 0, width: 1000, height: 600),
      CGRect(x: 1000, y: 100, width: 800, height: 500)
    ]
    let desktop = InlineAreaAnnotateSession.desktopFrame(for: frames)
    XCTAssertEqual(desktop.minX, 0)
    XCTAssertEqual(desktop.maxX, 1800)
    XCTAssertEqual(desktop.minY, 0)
    XCTAssertEqual(desktop.maxY, 600)
  }

  // MARK: - localFrame / screenRect / localRect

  func testLocalFrame_convertsScreenToLocal() {
    let desktop = CGRect(x: 0, y: 0, width: 2000, height: 1200)
    let screen = CGRect(x: 1000, y: 100, width: 800, height: 500)
    let local = InlineAreaAnnotateSession.localFrame(for: screen, in: desktop)
    XCTAssertEqual(local.minX, 1000)
    XCTAssertEqual(local.minY, 600) // desktop.maxY - screen.maxY = 1200 - 600
    XCTAssertEqual(local.width, 800)
    XCTAssertEqual(local.height, 500)
  }

  func testScreenRect_convertsLocalToScreen() {
    let desktop = CGRect(x: 0, y: 0, width: 2000, height: 1200)
    let local = CGRect(x: 1000, y: 600, width: 800, height: 500)
    let screen = InlineAreaAnnotateSession.screenRect(for: local, in: desktop)
    XCTAssertEqual(screen.minX, 1000)
    XCTAssertEqual(screen.minY, 100) // desktop.maxY - local.maxY = 1200 - 1100
    XCTAssertEqual(screen.width, 800)
    XCTAssertEqual(screen.height, 500)
  }

  func testLocalRect_roundTrips() {
    let desktop = CGRect(x: 0, y: 0, width: 2000, height: 1200)
    let screen = CGRect(x: 500, y: 200, width: 400, height: 300)
    let local = InlineAreaAnnotateSession.localFrame(for: screen, in: desktop)
    let back = InlineAreaAnnotateSession.screenRect(for: local, in: desktop)
    XCTAssertEqual(back.minX, screen.minX, accuracy: 0.001)
    XCTAssertEqual(back.minY, screen.minY, accuracy: 0.001)
    XCTAssertEqual(back.width, screen.width, accuracy: 0.001)
    XCTAssertEqual(back.height, screen.height, accuracy: 0.001)
  }

  // MARK: - displayIDsIntersecting

  func testDisplayIDsIntersecting_findsIntersecting() {
    let frames: [CGDirectDisplayID: CGRect] = [
      1: CGRect(x: 0, y: 0, width: 1000, height: 600),
      2: CGRect(x: 1000, y: 0, width: 800, height: 600)
    ]
    let rect = CGRect(x: 1100, y: 100, width: 200, height: 200)
    let ids = InlineAreaAnnotateSession.displayIDsIntersecting(rect, screenFramesByDisplayID: frames)
    XCTAssertEqual(ids.count, 1)
    XCTAssertTrue(ids.contains(2))
  }

  func testDisplayIDsIntersecting_emptyWhenNoOverlap() {
    let frames: [CGDirectDisplayID: CGRect] = [
      1: CGRect(x: 0, y: 0, width: 100, height: 100)
    ]
    let rect = CGRect(x: 200, y: 200, width: 50, height: 50)
    let ids = InlineAreaAnnotateSession.displayIDsIntersecting(rect, screenFramesByDisplayID: frames)
    XCTAssertTrue(ids.isEmpty)
  }

  // MARK: - primaryDisplayID

  func testPrimaryDisplayID_returnsLargestOverlap() {
    let frames: [CGDirectDisplayID: CGRect] = [
      1: CGRect(x: 0, y: 0, width: 1000, height: 600),
      2: CGRect(x: 1000, y: 0, width: 800, height: 600)
    ]
    let rect = CGRect(x: 1050, y: 100, width: 400, height: 400)
    let id = InlineAreaAnnotateSession.primaryDisplayID(
      for: rect,
      screenFramesByDisplayID: frames,
      fallback: 99
    )
    XCTAssertEqual(id, 2)
  }

  func testPrimaryDisplayID_usesFallbackWhenNoOverlap() {
    let frames: [CGDirectDisplayID: CGRect] = [
      1: CGRect(x: 0, y: 0, width: 100, height: 100)
    ]
    let rect = CGRect(x: 200, y: 200, width: 50, height: 50)
    let id = InlineAreaAnnotateSession.primaryDisplayID(
      for: rect,
      screenFramesByDisplayID: frames,
      fallback: 99
    )
    XCTAssertEqual(id, 99)
  }
}
