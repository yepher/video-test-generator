//
//  Config.swift
//  TestCamera
//
//  Shared constants between the main app and camera extension.
//

import Foundation

let kFrameRate: Int = 30
let kCameraName = "Test Camera"
let kFixedCamWidth: Int32 = 1920
let kFixedCamHeight: Int32 = 1080

// App group identifier for sharing state between app and extension.
// Must match the CMIOExtensionMachServiceName in the extension's Info.plist.
let kAppGroupIdentifier = "group.com.yepher.vidtiming.testcamera"

// UserDefaults key for the shared pattern state
let kPatternStateKey = "currentPatternState"

// Mmap path for HAL plugin communication
let kAudioStatePath = "/tmp/com.testcamera.audio.state"
