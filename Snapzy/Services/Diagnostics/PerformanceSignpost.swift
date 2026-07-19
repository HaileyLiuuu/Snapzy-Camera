//
//  PerformanceSignpost.swift
//  Snapzy
//
//  Helper for performance measurements using OSSignposter.
//

import Foundation
import os

@available(macOS 12.0, *)
nonisolated private let poster = OSSignposter(subsystem: "com.snapzy.perf", category: "annotate-return")

enum PerfSignpost {
  #if DEBUG
  @available(macOS 12.0, *)
  struct Interval {
    let name: StaticString
    let state: OSSignpostIntervalState
  }
  #endif

  nonisolated static func beginInterval(_ name: StaticString) -> Any? {
    #if DEBUG
    if #available(macOS 12.0, *) {
      if UserDefaults.standard.bool(forKey: "perf.signposts") {
        let state = poster.beginInterval(name)
        return Interval(name: name, state: state)
      }
    }
    #endif
    return nil
  }

  nonisolated static func endInterval(_ interval: Any?) {
    #if DEBUG
    if #available(macOS 12.0, *) {
      if let iv = interval as? Interval {
        poster.endInterval(iv.name, iv.state)
      }
    }
    #endif
  }

  nonisolated static func event(_ name: StaticString) {
    #if DEBUG
    if #available(macOS 12.0, *) {
      if UserDefaults.standard.bool(forKey: "perf.signposts") {
        poster.emitEvent(name)
      }
    }
    #endif
  }

  @discardableResult
  nonisolated static func measure<T>(_ name: StaticString, _ body: () -> T) -> T {
    #if DEBUG
    if #available(macOS 12.0, *) {
      if UserDefaults.standard.bool(forKey: "perf.signposts") {
        let start = CFAbsoluteTimeGetCurrent()
        let state = poster.beginInterval(name)
        defer {
          poster.endInterval(name, state)
          let elapsed = (CFAbsoluteTimeGetCurrent() - start) * 1000
          DiagnosticLogger.shared.log(.debug, .ui, "Performance [\(name)]: \(String(format: "%.2f", elapsed))ms")
        }
        return body()
      }
    }
    #endif
    return body()
  }
}
