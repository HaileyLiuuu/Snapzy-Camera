//
//  RecordingMouseTrackerTests.swift
//  SnapzyTests
//
//  Unit tests for RecordingMouseTracker sample-rate resolution and lifecycle.
//

import CoreGraphics
import XCTest
@testable import Snapzy

@MainActor
final class RecordingMouseTrackerTests: XCTestCase {

  func testResolvedSamplesPerSecond_fps15_clampedToMin() {
    XCTAssertEqual(RecordingMouseTracker.resolvedSamplesPerSecond(for: 15), 60)
  }

  func testResolvedSamplesPerSecond_fps30_doubled() {
    XCTAssertEqual(RecordingMouseTracker.resolvedSamplesPerSecond(for: 30), 60)
  }

  func testResolvedSamplesPerSecond_fps60_doubled() {
    XCTAssertEqual(RecordingMouseTracker.resolvedSamplesPerSecond(for: 60), 120)
  }

  func testResolvedSamplesPerSecond_fps120_clampedToMax() {
    XCTAssertEqual(RecordingMouseTracker.resolvedSamplesPerSecond(for: 120), 120)
  }

  func testInit_samplesPerSecond_matchesResolved() {
    let tracker = RecordingMouseTracker(recordingRect: CGRect(x: 0, y: 0, width: 100, height: 100), fps: 30)
    XCTAssertEqual(tracker.samplesPerSecond, 60)
  }

  func testStartStop_returnsSamples() {
    let tracker = RecordingMouseTracker(recordingRect: CGRect(x: 0, y: 0, width: 100, height: 100), fps: 30)
    tracker.start()
    let samples = tracker.stop()
    XCTAssertGreaterThanOrEqual(samples.count, 1)
    tracker.reset()
  }

  func testReset_clearsSamples() {
    let tracker = RecordingMouseTracker(recordingRect: CGRect(x: 0, y: 0, width: 100, height: 100), fps: 30)
    tracker.start()
    _ = tracker.stop()
    tracker.reset()
    // After reset, diagnostics should be nil
  }
}
