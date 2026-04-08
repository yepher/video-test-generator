//
//  ViewController.swift
//  TestCamera
//
//  UI for selecting test patterns, previewing the current pattern,
//  and activating/deactivating the camera system extension.
//  Uses CMIO custom property to push pattern changes to the extension.
//

import Cocoa
import SystemExtensions
import CoreMediaIO
import AVFoundation
import os.log

class ViewController: NSViewController {

    // MARK: - UI elements (created programmatically)

    private var activateButton: NSButton!
    private var deactivateButton: NSButton!
    private var patternPopup: NSPopUpButton!
    private var qrCheckbox: NSButton!
    private var statusLabel: NSTextField!
    private var previewImageView: NSImageView!

    private var previewTimer: Timer?
    private var previewRenderer: PatternRenderer = BouncingBallPattern()
    private var previewFrameNum: Int = 0
    private var previewStartTime: Date = Date()
    private var activating: Bool = false

    // CMIO property communication
    private var sourceStream: CMIOStreamID?

    // MARK: - Lifecycle

    override func loadView() {
        let mainView = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 560))
        self.view = mainView

        let margin: CGFloat = 20
        var y: CGFloat = mainView.bounds.height - margin

        // Title
        let titleLabel = NSTextField(labelWithString: "Test Camera")
        titleLabel.font = NSFont.boldSystemFont(ofSize: 20)
        titleLabel.frame = NSRect(x: margin, y: y - 28, width: 300, height: 28)
        mainView.addSubview(titleLabel)
        y -= 50

        // Activate / Deactivate buttons
        activateButton = NSButton(title: "Activate Camera", target: self, action: #selector(activate(_:)))
        activateButton.bezelStyle = .rounded
        activateButton.frame = NSRect(x: margin, y: y - 30, width: 150, height: 30)
        mainView.addSubview(activateButton)

        deactivateButton = NSButton(title: "Deactivate Camera", target: self, action: #selector(deactivate(_:)))
        deactivateButton.bezelStyle = .rounded
        deactivateButton.frame = NSRect(x: margin + 160, y: y - 30, width: 170, height: 30)
        mainView.addSubview(deactivateButton)
        y -= 44

        // Pattern selector
        let patternLabel = NSTextField(labelWithString: "Pattern:")
        patternLabel.font = NSFont.systemFont(ofSize: 13)
        patternLabel.frame = NSRect(x: margin, y: y - 22, width: 60, height: 22)
        mainView.addSubview(patternLabel)

        patternPopup = NSPopUpButton(frame: NSRect(x: margin + 65, y: y - 24, width: 280, height: 26))
        patternPopup.target = self
        patternPopup.action = #selector(patternChanged(_:))
        mainView.addSubview(patternPopup)
        y -= 36

        // QR toggle
        qrCheckbox = NSButton(checkboxWithTitle: "Enable QR Code Overlay", target: self, action: #selector(qrToggled(_:)))
        qrCheckbox.frame = NSRect(x: margin, y: y - 22, width: 250, height: 22)
        mainView.addSubview(qrCheckbox)
        y -= 36

        // Status label
        statusLabel = NSTextField(labelWithString: "Click 'Activate Camera' to register the virtual camera.")
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 4
        statusLabel.frame = NSRect(x: margin, y: y - 50, width: 580, height: 50)
        mainView.addSubview(statusLabel)
        y -= 56

        // Preview image
        let previewLabel = NSTextField(labelWithString: "Preview:")
        previewLabel.font = NSFont.systemFont(ofSize: 13)
        previewLabel.frame = NSRect(x: margin, y: y - 22, width: 80, height: 22)
        mainView.addSubview(previewLabel)
        y -= 28

        previewImageView = NSImageView(frame: NSRect(x: margin, y: margin, width: 480, height: y - margin))
        previewImageView.imageScaling = .scaleProportionallyUpOrDown
        previewImageView.wantsLayer = true
        previewImageView.layer?.backgroundColor = NSColor.black.cgColor
        previewImageView.layer?.cornerRadius = 4
        mainView.addSubview(previewImageView)
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        setupPatternMenu()
        loadCurrentState()
        startPreview()

        // Make CMIO devices visible (required to discover our virtual camera)
        makeDevicesVisible()

        // Try to connect to the virtual camera immediately
        connectToVirtualCamera()

        // Also listen for device connections (in case extension activates later)
        registerForDeviceNotifications()
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        previewTimer?.invalidate()
    }

    // MARK: - System Extension Activation

    private class func _extensionBundle() -> Bundle {
        let extensionsDirectoryURL = URL(fileURLWithPath: "Contents/Library/SystemExtensions", relativeTo: Bundle.main.bundleURL)
        let extensionURLs: [URL]
        do {
            extensionURLs = try FileManager.default.contentsOfDirectory(at: extensionsDirectoryURL,
                                                                        includingPropertiesForKeys: nil,
                                                                        options: .skipsHiddenFiles)
        } catch let error {
            fatalError("Failed to get the contents of \(extensionsDirectoryURL.absoluteString): \(error.localizedDescription)")
        }

        guard let extensionURL = extensionURLs.first else {
            fatalError("Failed to find any system extensions")
        }
        guard let extensionBundle = Bundle(url: extensionURL) else {
            fatalError("Failed to find any system extensions")
        }
        return extensionBundle
    }

    @objc func activate(_ sender: Any? = nil) {
        guard let extensionIdentifier = ViewController._extensionBundle().bundleIdentifier else {
            showStatus("Error: Could not find extension bundle identifier")
            return
        }
        activating = true
        showStatus("Activating camera extension: \(extensionIdentifier)...")
        let activationRequest = OSSystemExtensionRequest.activationRequest(forExtensionWithIdentifier: extensionIdentifier, queue: .main)
        activationRequest.delegate = self
        OSSystemExtensionManager.shared.submitRequest(activationRequest)
    }

    @objc func deactivate(_ sender: Any? = nil) {
        guard let extensionIdentifier = ViewController._extensionBundle().bundleIdentifier else {
            showStatus("Error: Could not find extension bundle identifier")
            return
        }
        activating = false
        showStatus("Deactivating camera extension...")
        let deactivationRequest = OSSystemExtensionRequest.deactivationRequest(forExtensionWithIdentifier: extensionIdentifier, queue: .main)
        deactivationRequest.delegate = self
        OSSystemExtensionManager.shared.submitRequest(deactivationRequest)
    }

    // MARK: - Pattern Menu

    private func setupPatternMenu() {
        patternPopup.removeAllItems()
        for patternType in PatternType.allCases {
            patternPopup.addItem(withTitle: patternType.displayName)
            patternPopup.lastItem?.tag = PatternType.allCases.firstIndex(of: patternType)!
        }
    }

    private func loadCurrentState() {
        let state = PatternState.load()
        if let idx = PatternType.allCases.firstIndex(of: state.patternType) {
            patternPopup.selectItem(at: idx)
        }
        qrCheckbox.state = state.enableQR ? .on : .off
        previewRenderer = createPatternRenderer(for: state.patternType)
    }

    // MARK: - Actions

    @objc func patternChanged(_ sender: NSPopUpButton) {
        let idx = sender.indexOfSelectedItem
        guard idx >= 0 && idx < PatternType.allCases.count else { return }

        let selectedType = PatternType.allCases[idx]
        let enableQR = qrCheckbox.state == .on

        // Save to file (for initial load on extension restart)
        var state = PatternState.load()
        state.patternType = selectedType
        state.save()

        // Push to extension immediately via CMIO custom property
        pushPatternToExtension(patternType: selectedType, enableQR: enableQR)

        // Update preview
        previewRenderer = createPatternRenderer(for: selectedType)
        previewFrameNum = 0
        previewStartTime = Date()

        showStatus("Pattern: \(selectedType.displayName)")
    }

    @objc func qrToggled(_ sender: NSButton) {
        let enableQR = sender.state == .on

        var state = PatternState.load()
        state.enableQR = enableQR
        state.save()

        // Push to extension immediately via CMIO custom property
        let idx = patternPopup.indexOfSelectedItem
        if idx >= 0 && idx < PatternType.allCases.count {
            let selectedType = PatternType.allCases[idx]
            pushPatternToExtension(patternType: selectedType, enableQR: enableQR)
        }
    }

    // MARK: - CMIO Custom Property (App → Extension communication)

    /// Push pattern change to extension via CMIO custom property.
    /// This bypasses sandbox and user boundaries — the extension receives it
    /// in setStreamProperties().
    private func pushPatternToExtension(patternType: PatternType, enableQR: Bool) {
        // Try to connect if we haven't yet
        if sourceStream == nil {
            connectToVirtualCamera()
        }

        guard let streamId = sourceStream else {
            os_log(.info, "TestCamera: no stream connection to extension yet")
            return
        }

        let value = "\(patternType.rawValue):\(enableQR)"
        setPatternProperty(streamId: streamId, newValue: value)
        os_log(.info, "TestCamera: pushed pattern '%{public}@' to extension", value)
    }

    /// Allow CMIO to discover screen-capture / virtual camera devices
    func makeDevicesVisible() {
        var prop = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        var allow: UInt32 = 1
        let dataSize: UInt32 = 4
        let zero: UInt32 = 0
        CMIOObjectSetPropertyData(CMIOObjectID(kCMIOObjectSystemObject), &prop, zero, nil, dataSize, &allow)
    }

    /// Find our virtual camera by name and get its source stream
    func connectToVirtualCamera() {
        if let device = getDevice(name: kCameraName),
           let deviceObjectId = getCMIODevice(uid: device.uniqueID) {
            let streamIds = getInputStreams(deviceId: deviceObjectId)
            if let firstStream = streamIds.first {
                sourceStream = firstStream
                os_log(.info, "TestCamera: connected to virtual camera stream")

                // Push current state immediately
                let idx = patternPopup?.indexOfSelectedItem ?? 0
                if idx >= 0 && idx < PatternType.allCases.count {
                    let patternType = PatternType.allCases[idx]
                    let enableQR = qrCheckbox?.state == .on
                    pushPatternToExtension(patternType: patternType, enableQR: enableQR)
                }
            }
        }
    }

    /// Listen for device connections so we can connect when the extension activates
    func registerForDeviceNotifications() {
        NotificationCenter.default.addObserver(forName: .AVCaptureDeviceWasConnected, object: nil, queue: .main) { [weak self] _ in
            if self?.sourceStream == nil {
                self?.connectToVirtualCamera()
            }
        }
    }

    // MARK: - CMIO Property Helpers

    func getDevice(name: String) -> AVCaptureDevice? {
        let devices: [AVCaptureDevice]
        if #available(macOS 14.0, *) {
            devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.external], mediaType: .video, position: .unspecified).devices
        } else {
            devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.externalUnknown], mediaType: .video, position: .unspecified).devices
        }
        return devices.first { $0.localizedName == name }
    }

    func getCMIODevice(uid: String) -> CMIOObjectID? {
        var dataSize: UInt32 = 0
        var devices = [CMIOObjectID]()
        var dataUsed: UInt32 = 0
        var opa = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        CMIOObjectGetPropertyDataSize(CMIOObjectPropertySelector(kCMIOObjectSystemObject), &opa, 0, nil, &dataSize)
        let nDevices = Int(dataSize) / MemoryLayout<CMIOObjectID>.size
        devices = [CMIOObjectID](repeating: 0, count: nDevices)
        CMIOObjectGetPropertyData(CMIOObjectPropertySelector(kCMIOObjectSystemObject), &opa, 0, nil, dataSize, &dataUsed, &devices)
        for deviceObjectID in devices {
            opa.mSelector = CMIOObjectPropertySelector(kCMIODevicePropertyDeviceUID)
            CMIOObjectGetPropertyDataSize(deviceObjectID, &opa, 0, nil, &dataSize)
            var value: Unmanaged<CFString>?
            CMIOObjectGetPropertyData(deviceObjectID, &opa, 0, nil, dataSize, &dataUsed, &value)
            if let cfString = value?.takeRetainedValue(), String(cfString as NSString) == uid {
                return deviceObjectID
            }
        }
        return nil
    }

    func getInputStreams(deviceId: CMIODeviceID) -> [CMIOStreamID] {
        var dataSize: UInt32 = 0
        var dataUsed: UInt32 = 0
        var opa = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyStreams),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        CMIOObjectGetPropertyDataSize(deviceId, &opa, 0, nil, &dataSize)
        let numberStreams = Int(dataSize) / MemoryLayout<CMIOStreamID>.size
        var streamIds = [CMIOStreamID](repeating: 0, count: numberStreams)
        CMIOObjectGetPropertyData(deviceId, &opa, 0, nil, dataSize, &dataUsed, &streamIds)
        return streamIds
    }

    func setPatternProperty(streamId: CMIOStreamID, newValue: String) {
        let selector = CustomFourCharCode("patt").code
        var address = CMIOObjectPropertyAddress(
            mSelector: selector,
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        let exists = CMIOObjectHasProperty(streamId, &address)
        if exists {
            var settable: DarwinBoolean = false
            CMIOObjectIsPropertySettable(streamId, &address, &settable)
            if settable == false {
                os_log(.error, "TestCamera: pattern property not settable")
                return
            }
            var dataSize: UInt32 = 0
            CMIOObjectGetPropertyDataSize(streamId, &address, 0, nil, &dataSize)
            let cfString = newValue as CFString
            var value: Unmanaged<CFString> = Unmanaged.passRetained(cfString)
            CMIOObjectSetPropertyData(streamId, &address, 0, nil, dataSize, &value)
        } else {
            os_log(.error, "TestCamera: pattern property not found on stream")
        }
    }

    // MARK: - Preview

    private func startPreview() {
        previewStartTime = Date()
        previewFrameNum = 0
        previewTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 10.0, repeats: true) { [weak self] _ in
            self?.renderPreviewFrame()
        }
    }

    private func renderPreviewFrame() {
        let previewWidth = 480
        let previewHeight = 270

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: previewWidth,
            height: previewHeight,
            bitsPerComponent: 8,
            bytesPerRow: previewWidth * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return }

        let time = Date().timeIntervalSince(previewStartTime)

        previewRenderer.renderFrame(
            context: context,
            width: previewWidth,
            height: previewHeight,
            time: time,
            frameNum: previewFrameNum
        )

        if let cgImage = context.makeImage() {
            previewImageView.image = NSImage(cgImage: cgImage, size: NSSize(width: previewWidth, height: previewHeight))
        }

        previewFrameNum += 1
    }

    // MARK: - Status

    private func showStatus(_ text: String) {
        os_log(.info, "TestCamera: %{public}@", text)
        statusLabel.stringValue = text
    }
}

// MARK: - OSSystemExtensionRequestDelegate

extension ViewController: OSSystemExtensionRequestDelegate {

    func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties,
                 withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        showStatus("Replacing extension version \(existing.bundleShortVersion) with \(ext.bundleShortVersion)")
        return .replace
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        showStatus("Extension needs user approval. Check System Settings > General > Login Items & Extensions > Camera Extensions.")
    }

    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        if result == .completed {
            if activating {
                showStatus("Camera activated! Select 'Test Camera' in any video app.")
                // Connect to the newly activated camera
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                    self?.connectToVirtualCamera()
                }
            } else {
                showStatus("Camera deactivated.")
                sourceStream = nil
            }
        } else {
            if activating {
                showStatus("Please reboot to finish activating the camera.")
            } else {
                showStatus("Please reboot to finish deactivating the camera.")
            }
        }
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        let nsError = error as NSError
        if activating {
            showStatus("Failed to activate: \(nsError.localizedDescription). Try running from /Applications.")
        } else {
            showStatus("Failed to deactivate: \(nsError.localizedDescription)")
        }
    }
}

// MARK: - CMIO Helpers

struct CustomFourCharCode {
    let code: FourCharCode
    init(_ string: String) {
        var code: FourCharCode = 0
        if string.count == 4 && string.utf8.count == 4 {
            for byte in string.utf8 { code = code << 8 + FourCharCode(byte) }
        } else {
            code = 0x3F3F3F3F // "????" fallback
        }
        self.code = code
    }
}
