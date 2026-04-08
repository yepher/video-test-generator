//
//  CameraStreamSource.swift
//  TestCameraExtension
//
//  CMIOExtension source stream — delivers frames to consuming apps
//  (FaceTime, Zoom, OBS, etc.).
//  Exposes a custom CMIO property "patt" so the main app can push
//  pattern changes directly to the extension (bypasses sandbox).
//

import Foundation
import CoreMediaIO
import os.log

/// Custom CMIO property for pattern switching.
/// Format: "4cc_XXXX_glob_0000" where XXXX is a 4-char code.
let CMIOExtensionPropertyCustomPropertyData_patt: CMIOExtensionProperty =
    CMIOExtensionProperty(rawValue: "4cc_patt_glob_0000")

class CameraStreamSource: NSObject, CMIOExtensionStreamSource {

    private(set) var stream: CMIOExtensionStream!

    let device: CMIOExtensionDevice
    private let _streamFormat: CMIOExtensionStreamFormat

    /// Current pattern value received from the app via custom property.
    /// Format: "patternType:enableQR" e.g. "smpte_bars:true"
    public var patternProperty: String = "" {
        didSet {
            guard !patternProperty.isEmpty else { return }
            os_log(.info, "TestCameraExt: custom property set to '%{public}@'", patternProperty)
            // Parse and apply to the device
            if let deviceSource = device.source as? CameraDevice {
                deviceSource.applyPatternFromProperty(patternProperty)
            }
        }
    }

    init(localizedName: String, streamID: UUID, streamFormat: CMIOExtensionStreamFormat, device: CMIOExtensionDevice) {
        self.device = device
        self._streamFormat = streamFormat
        super.init()
        self.stream = CMIOExtensionStream(
            localizedName: localizedName,
            streamID: streamID,
            direction: .source,
            clockType: .hostTime,
            source: self
        )
    }

    var formats: [CMIOExtensionStreamFormat] {
        return [_streamFormat]
    }

    var activeFormatIndex: Int = 0 {
        didSet {
            if activeFormatIndex >= 1 {
                os_log(.error, "Invalid active format index")
            }
        }
    }

    var availableProperties: Set<CMIOExtensionProperty> {
        return [.streamActiveFormatIndex, .streamFrameDuration, CMIOExtensionPropertyCustomPropertyData_patt]
    }

    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let streamProperties = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) {
            streamProperties.activeFormatIndex = 0
        }
        if properties.contains(.streamFrameDuration) {
            let frameDuration = CMTime(value: 1, timescale: Int32(kFrameRate))
            streamProperties.frameDuration = frameDuration
        }
        if properties.contains(CMIOExtensionPropertyCustomPropertyData_patt) {
            streamProperties.setPropertyState(
                CMIOExtensionPropertyState(value: patternProperty as NSString),
                forProperty: CMIOExtensionPropertyCustomPropertyData_patt
            )
        }
        return streamProperties
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {
        if let activeFormatIndex = streamProperties.activeFormatIndex {
            self.activeFormatIndex = activeFormatIndex
        }

        // Handle custom "patt" property from the main app
        if let state = streamProperties.propertiesDictionary[CMIOExtensionPropertyCustomPropertyData_patt] {
            if let newValue = state.value as? String {
                os_log(.info, "TestCameraExt: received pattern property: '%{public}@'", newValue)
                self.patternProperty = newValue
            }
        }
    }

    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool {
        return true
    }

    func startStream() throws {
        guard let deviceSource = device.source as? CameraDevice else {
            fatalError("Unexpected source type \(String(describing: device.source))")
        }
        deviceSource.startStreaming()
    }

    func stopStream() throws {
        guard let deviceSource = device.source as? CameraDevice else {
            fatalError("Unexpected source type \(String(describing: device.source))")
        }
        deviceSource.stopStreaming()
    }
}
