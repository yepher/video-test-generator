//
//  CameraDevice.swift
//  TestCameraExtension
//
//  CMIOExtension device source. Manages the virtual camera device,
//  runs a timer to generate frames, and renders test patterns.
//  Pattern changes arrive via CMIO custom property from the main app.
//

import Foundation
import CoreMediaIO
import CoreGraphics
import CoreImage
import IOKit.audio
import os.log

class CameraDevice: NSObject, CMIOExtensionDeviceSource {

    private(set) var device: CMIOExtensionDevice!

    var _streamSource: CameraStreamSource!
    var _streamSink: CameraStreamSink!
    private var _streamingCounter: UInt32 = 0
    private var _streamingSinkCounter: UInt32 = 0

    private var _timer: DispatchSourceTimer?
    private let _timerQueue = DispatchQueue(
        label: "testCameraTimerQueue",
        qos: .userInteractive,
        attributes: [],
        autoreleaseFrequency: .workItem,
        target: .global(qos: .userInteractive)
    )

    private var _videoDescription: CMFormatDescription!
    private var _bufferPool: CVPixelBufferPool!
    private var _bufferAuxAttributes: NSDictionary!

    // Pattern rendering — guarded by _patternLock for thread safety
    private let _patternLock = NSLock()
    private var _currentRenderer: PatternRenderer = BouncingBallPattern()
    private var _currentPatternType: PatternType = .bouncingBall
    private var _currentEnableQR: Bool = true

    private var startTime: UInt64 = 0
    private var frameCounter: Int = 0

    init(localizedName: String) {
        super.init()

        let deviceID = UUID()
        self.device = CMIOExtensionDevice(
            localizedName: localizedName,
            deviceID: deviceID,
            legacyDeviceID: deviceID.uuidString,
            source: self
        )

        let dims = CMVideoDimensions(width: kFixedCamWidth, height: kFixedCamHeight)
        CMVideoFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            codecType: kCVPixelFormatType_32BGRA,
            width: dims.width,
            height: dims.height,
            extensions: nil,
            formatDescriptionOut: &_videoDescription
        )

        let pixelBufferAttributes: NSDictionary = [
            kCVPixelBufferWidthKey: dims.width,
            kCVPixelBufferHeightKey: dims.height,
            kCVPixelBufferPixelFormatTypeKey: _videoDescription.mediaSubType,
            kCVPixelBufferIOSurfacePropertiesKey: [:]
        ]
        CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, pixelBufferAttributes, &_bufferPool)

        let streamFormat = CMIOExtensionStreamFormat(
            formatDescription: _videoDescription,
            maxFrameDuration: CMTime(value: 1, timescale: Int32(kFrameRate)),
            minFrameDuration: CMTime(value: 1, timescale: Int32(kFrameRate)),
            validFrameDurations: nil
        )
        _bufferAuxAttributes = [kCVPixelBufferPoolAllocationThresholdKey: 5]

        let videoID = UUID()
        _streamSource = CameraStreamSource(
            localizedName: "TestCamera.Video",
            streamID: videoID,
            streamFormat: streamFormat,
            device: device
        )

        let videoSinkID = UUID()
        _streamSink = CameraStreamSink(
            localizedName: "TestCamera.Video.Sink",
            streamID: videoSinkID,
            streamFormat: streamFormat,
            device: device
        )

        do {
            try device.addStream(_streamSource.stream)
            try device.addStream(_streamSink.stream)
        } catch {
            fatalError("Failed to add stream: \(error.localizedDescription)")
        }

        os_log(.info, "TestCameraExt: initialized with default pattern (bouncing ball)")
    }

    /// Called from CameraStreamSource when the app writes a custom CMIO property.
    /// This is the primary IPC mechanism — bypasses sandbox and user boundaries.
    /// Format: "patternRawValue:enableQR" e.g. "smpte_bars:true"
    func applyPatternFromProperty(_ value: String) {
        let parts = value.split(separator: ":")
        guard parts.count >= 1 else { return }

        let patternRaw = String(parts[0])

        _patternLock.lock()
        let enableQR = parts.count >= 2 ? String(parts[1]) == "true" : _currentEnableQR

        if let newPattern = PatternType(rawValue: patternRaw) {
            if newPattern != _currentPatternType {
                os_log(.info, "TestCameraExt: CMIO property → SWITCHING to %{public}@", newPattern.rawValue)
                _currentPatternType = newPattern
                _currentRenderer = createPatternRenderer(for: newPattern)
                frameCounter = 0
            }
            _currentEnableQR = enableQR
        } else {
            os_log(.error, "TestCameraExt: unknown pattern type '%{public}@'", patternRaw)
        }
        _patternLock.unlock()
    }

    // MARK: - Properties

    var availableProperties: Set<CMIOExtensionProperty> {
        return [.deviceTransportType, .deviceModel]
    }

    func deviceProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionDeviceProperties {
        let props = CMIOExtensionDeviceProperties(dictionary: [:])
        if properties.contains(.deviceTransportType) {
            props.transportType = kIOAudioDeviceTransportTypeVirtual
        }
        if properties.contains(.deviceModel) {
            props.model = "Test Camera Model"
        }
        return props
    }

    func setDeviceProperties(_ deviceProperties: CMIOExtensionDeviceProperties) throws {}

    // MARK: - Streaming

    func startStreaming() {
        guard _bufferPool != nil else { return }

        _streamingCounter += 1
        startTime = mach_absolute_time()
        frameCounter = 0

        _patternLock.lock()
        let patternName = _currentPatternType.rawValue
        _patternLock.unlock()
        os_log(.info, "TestCameraExt: startStreaming with pattern %{public}@", patternName)

        _timer = DispatchSource.makeTimerSource(flags: .strict, queue: _timerQueue)
        _timer!.schedule(deadline: .now(), repeating: 1.0 / Double(kFrameRate), leeway: .seconds(0))

        _timer!.setEventHandler { [weak self] in
            self?.generateFrame()
        }

        _timer!.setCancelHandler {}
        _timer!.resume()
    }

    func stopStreaming() {
        if _streamingCounter > 1 {
            _streamingCounter -= 1
        } else {
            _streamingCounter = 0
            _timer?.cancel()
            _timer = nil
        }
    }

    private func generateFrame() {
        // If the main app is pushing frames via the sink, let those through instead
        if sinkStarted { return }

        var pixelBuffer: CVPixelBuffer?
        let err = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(
            kCFAllocatorDefault, _bufferPool, _bufferAuxAttributes, &pixelBuffer
        )
        guard err == 0, let pixelBuffer = pixelBuffer else {
            os_log(.error, "Failed to create pixel buffer: %d", err)
            return
        }

        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)

        // Calculate time
        let time = Double(frameCounter) / Double(kFrameRate)

        // Snapshot current renderer + settings under lock
        _patternLock.lock()
        let renderer = _currentRenderer
        let enableQR = _currentEnableQR
        let patternName = renderer.name
        _patternLock.unlock()

        // Render frame into pixel buffer
        CVPixelBufferLockBaseAddress(pixelBuffer, [])

        if let pixelData = CVPixelBufferGetBaseAddress(pixelBuffer) {
            let rgbColorSpace = CGColorSpaceCreateDeviceRGB()
            if let context = CGContext(
                data: pixelData,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                space: rgbColorSpace,
                bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
            ) {
                // Render the test pattern
                renderer.renderFrame(
                    context: context,
                    width: width,
                    height: height,
                    time: time,
                    frameNum: frameCounter
                )

                // Composite QR code
                if enableQR {
                    compositeQRCode(
                        context: context,
                        width: width,
                        height: height,
                        frameNum: frameCounter,
                        time: time,
                        fps: kFrameRate,
                        patternName: patternName
                    )
                }
            }
        }

        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

        // Create sample buffer and send
        var sampleBuffer: CMSampleBuffer!
        var timingInfo = CMSampleTimingInfo()
        timingInfo.presentationTimeStamp = CMClockGetTime(CMClockGetHostTimeClock())

        let sampleErr = CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: _videoDescription,
            sampleTiming: &timingInfo,
            sampleBufferOut: &sampleBuffer
        )

        if sampleErr == 0 {
            _streamSource.stream.send(
                sampleBuffer,
                discontinuity: [],
                hostTimeInNanoseconds: UInt64(timingInfo.presentationTimeStamp.seconds * Double(NSEC_PER_SEC))
            )
        }

        frameCounter += 1
    }

    // MARK: - Sink (for main app to push frames)

    var sinkStarted = false
    var lastTimingInfo = CMSampleTimingInfo()

    func consumeBuffer(_ client: CMIOExtensionClient) {
        guard sinkStarted else { return }
        _streamSink.stream.consumeSampleBuffer(from: client) { [weak self] sbuf, seq, discontinuity, hasMore, err in
            guard let self = self, let sbuf = sbuf else { return }
            self.lastTimingInfo.presentationTimeStamp = CMClockGetTime(CMClockGetHostTimeClock())
            if self._streamingCounter > 0 {
                self._streamSource.stream.send(
                    sbuf,
                    discontinuity: [],
                    hostTimeInNanoseconds: UInt64(sbuf.presentationTimeStamp.seconds * Double(NSEC_PER_SEC))
                )
            }
            let output = CMIOExtensionScheduledOutput(
                sequenceNumber: seq,
                hostTimeInNanoseconds: UInt64(self.lastTimingInfo.presentationTimeStamp.seconds * Double(NSEC_PER_SEC))
            )
            self._streamSink.stream.notifyScheduledOutputChanged(output)
            self.consumeBuffer(client)
        }
    }

    func startStreamingSink(client: CMIOExtensionClient) {
        _streamingSinkCounter += 1
        sinkStarted = true
        consumeBuffer(client)
    }

    func stopStreamingSink() {
        sinkStarted = false
        if _streamingSinkCounter > 1 {
            _streamingSinkCounter -= 1
        } else {
            _streamingSinkCounter = 0
        }
    }
}
