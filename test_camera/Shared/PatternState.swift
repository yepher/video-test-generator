//
//  PatternState.swift
//  TestCamera
//
//  Codable state shared between app and extension.
//  Primary: UserDefaults via shared App Group container (Apple recommended).
//  Fallback: File at /var/tmp/ + Darwin notification (cross-user).
//

import Foundation
import CoreFoundation
import os.log

/// Darwin notification name for pattern changes
let kPatternChangedDarwinName = "com.yepher.vidtiming.testcamera.patternChanged" as CFString

/// File path for shared state — /var/tmp/ is world-writable and persistent (fallback)
let kPatternStateFilePath = "/var/tmp/com.yepher.vidtiming.testcamera.state.json"

/// UserDefaults key for shared state via App Group
let kPatternStateDefaultsKey = "patternState"

/// Available test patterns
enum PatternType: String, Codable, CaseIterable {
    case bouncingBall = "bouncing_ball"
    case smpteBars = "smpte_bars"
    case gridChart = "grid_chart"
    case countdown = "countdown"

    var displayName: String {
        switch self {
        case .bouncingBall: return "Bouncing Ball A/V Sync"
        case .smpteBars: return "SMPTE Color Bars"
        case .gridChart: return "Grid / Resolution Chart"
        case .countdown: return "Countdown Leader"
        }
    }

    var description: String {
        switch self {
        case .bouncingBall: return "Ball sweeps across timeline ruler with tone bursts for A/V sync testing"
        case .smpteBars: return "Standard SMPTE RP 219 color bars for color calibration"
        case .gridChart: return "Fine grid, circles, and wedges for resolution and geometry testing"
        case .countdown: return "Classic film-style countdown (10 to 0) with sweep hand and beeps"
        }
    }
}

/// Shared state between app and camera extension
struct PatternState: Codable {
    var patternType: PatternType
    var width: Int
    var height: Int
    var fps: Int
    var enableQR: Bool

    init(
        patternType: PatternType = .bouncingBall,
        width: Int = Int(kFixedCamWidth),
        height: Int = Int(kFixedCamHeight),
        fps: Int = kFrameRate,
        enableQR: Bool = true
    ) {
        self.patternType = patternType
        self.width = width
        self.height = height
        self.fps = fps
        self.enableQR = enableQR
    }

    /// Save state to shared App Group UserDefaults, file, and signal via Darwin notification
    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }

        // 1. Primary: Write to shared App Group UserDefaults
        if let sharedDefaults = UserDefaults(suiteName: kAppGroupIdentifier) {
            sharedDefaults.set(data, forKey: kPatternStateDefaultsKey)
            sharedDefaults.synchronize()
            os_log(.info, "PatternState: saved to App Group UserDefaults (%{public}@)", kAppGroupIdentifier)
        } else {
            os_log(.error, "PatternState: FAILED to open App Group UserDefaults (%{public}@)", kAppGroupIdentifier)
        }

        // 2. Fallback: Write to /var/tmp/ file (world-readable, works across users)
        let url = URL(fileURLWithPath: kPatternStateFilePath)
        do {
            try data.write(to: url, options: .atomic)
            chmod(kPatternStateFilePath, 0o644)
            os_log(.info, "PatternState: saved to file %{public}@", kPatternStateFilePath)
        } catch {
            os_log(.error, "PatternState: failed to write state file: %{public}@", error.localizedDescription)
        }

        // 3. Signal via Darwin notification center (cross-process, cross-user)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(kPatternChangedDarwinName),
            nil,
            nil,
            true
        )
        os_log(.info, "PatternState: posted Darwin notification")
    }

    /// Load state — tries App Group UserDefaults first, then file fallback
    static func load() -> PatternState {
        // 1. Try shared App Group UserDefaults
        if let sharedDefaults = UserDefaults(suiteName: kAppGroupIdentifier),
           let data = sharedDefaults.data(forKey: kPatternStateDefaultsKey),
           let state = try? JSONDecoder().decode(PatternState.self, from: data) {
            os_log(.debug, "PatternState: loaded from App Group UserDefaults")
            return state
        }

        // 2. Fallback: Try /var/tmp/ file
        let url = URL(fileURLWithPath: kPatternStateFilePath)
        if let data = try? Data(contentsOf: url),
           let state = try? JSONDecoder().decode(PatternState.self, from: data) {
            os_log(.debug, "PatternState: loaded from file fallback")
            return state
        }

        os_log(.info, "PatternState: no saved state found, using defaults")
        return PatternState()
    }

    /// Register a Darwin notification observer. The callback fires when save() is called.
    /// The callback has no parameters — call PatternState.load() inside it.
    static func observeChanges(callback: @escaping CFNotificationCallback) {
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            nil,
            callback,
            kPatternChangedDarwinName,
            nil,
            .deliverImmediately
        )
    }
}
