//
//  CaptureSignposts.swift
//  Snapzy
//
//  Lightweight os_signpost wrapper for capture-path instrumentation.
//  Active in DEBUG builds; opt-in in release via SNAPZY_PERF_SIGNPOSTS=1.
//  All calls no-op when disabled (~1-5 ns nil-check overhead).
//
//  USAGE: View in Instruments → Points of Interest / Animation Hitches.
//  Subsystem: "com.snapzy.capture"   Categories: activation | render | execute
//

import OSLog
import QuartzCore

/// Static signpost wrapper for Snapzy capture performance measurement.
/// All methods are @MainActor — capture is always initiated on the main actor.
@MainActor
enum CaptureSignposts {

  static let enabled: Bool = {
    #if DEBUG
    return true
    #else
    return ProcessInfo.processInfo.environment["SNAPZY_PERF_SIGNPOSTS"] == "1"
    #endif
  }()

  private static let activationLog = OSSignposter(
    subsystem: "com.snapzy.capture", category: "activation")
  private static let renderLog = OSSignposter(
    subsystem: "com.snapzy.capture", category: "render")
  private static let executeLog = OSSignposter(
    subsystem: "com.snapzy.capture", category: "execute")

  // MARK: - Activation interval: hotkey → overlay visible

  // Single in-flight capture guaranteed by isAreaSelectionActive guard.
  private static var _activationState: OSSignpostIntervalState? = nil

  static func beginActivation() {
    guard enabled else { return }
    _activationState = activationLog.beginInterval("hotkey-to-overlay")
  }

  static func endActivation() {
    guard enabled, let state = _activationState else { return }
    activationLog.endInterval("hotkey-to-overlay", state)
    _activationState = nil
  }

  /// Discard an activation interval that will never reach the overlay (early return:
  /// capture already active, save-dir permission missing). Prevents the abandoned
  /// interval from being silently overwritten by the next hotkey press.
  static func abandonActivation() {
    _activationState = nil
  }

  /// Point-in-time event within the activation interval.
  static func activationEvent(_ name: StaticString) {
    guard enabled else { return }
    activationLog.emitEvent(name)
  }

  // MARK: - Frozen snapshot interval

  private static var _frozenSnapshotState: OSSignpostIntervalState? = nil

  static func beginFrozenSnapshot() {
    guard enabled else { return }
    _frozenSnapshotState = activationLog.beginInterval("frozen-snapshot-prepare")
  }

  static func endFrozenSnapshot() {
    guard enabled, let state = _frozenSnapshotState else { return }
    activationLog.endInterval("frozen-snapshot-prepare", state)
    _frozenSnapshotState = nil
  }

  // MARK: - Shareable-content fetch interval

  private static var _shareableContentState: OSSignpostIntervalState? = nil

  static func beginShareableContentFetch() {
    guard enabled else { return }
    _shareableContentState = activationLog.beginInterval("shareable-content-fetch")
  }

  static func endShareableContentFetch() {
    guard enabled, let state = _shareableContentState else { return }
    activationLog.endInterval("shareable-content-fetch", state)
    _shareableContentState = nil
  }

  // MARK: - Render: mouse-move → CA commit

  /// Call immediately before CATransaction.begin() in renderManualSelection.
  /// Returns current media time (cheap; caller passes it back to commitFrame).
  static func renderFrameStart() -> CFTimeInterval {
    return CACurrentMediaTime()
  }

  /// Call after CATransaction.commit() in renderManualSelection.
  /// Emits a point-in-time event; intervals would add too much overhead per frame.
  static func renderFrameCommit(startTime: CFTimeInterval) {
    guard enabled else { return }
    renderLog.emitEvent("frame-commit")
  }

  // MARK: - Capture execute interval: completeSelection → clipboard

  private static var _executeState: OSSignpostIntervalState? = nil

  static func beginExecute() {
    guard enabled else { return }
    _executeState = executeLog.beginInterval("capture-execute")
  }

  static func endExecute() {
    guard enabled, let state = _executeState else { return }
    executeLog.endInterval("capture-execute", state)
    _executeState = nil
  }

  /// Point-in-time event within the execute interval (e.g. "clipboard-set").
  static func executeEvent(_ name: StaticString) {
    guard enabled else { return }
    executeLog.emitEvent(name)
  }
}
