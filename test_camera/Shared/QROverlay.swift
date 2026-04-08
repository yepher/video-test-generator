//
//  QROverlay.swift
//  TestCamera
//
//  Generates QR codes with timing data and composites them onto CGContext frames.
//  Uses CIFilter for QR generation — no third-party dependencies.
//

import Foundation
import CoreGraphics
import CoreImage

/// Generate a QR code CGImage encoding the given JSON payload string.
///
/// - Parameters:
///   - payload: The string data to encode in the QR code.
///   - size: Target size in pixels for the QR code.
/// - Returns: A CGImage of the QR code, or nil on failure.
func generateQRCode(payload: String, size: Int) -> CGImage? {
    guard let data = payload.data(using: .utf8) else { return nil }

    guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
    filter.setValue(data, forKey: "inputMessage")
    filter.setValue("M", forKey: "inputCorrectionLevel") // Medium error correction

    guard let ciImage = filter.outputImage else { return nil }

    // Scale the tiny QR to the target size (nearest neighbor for sharp pixels)
    let scaleX = CGFloat(size) / ciImage.extent.width
    let scaleY = CGFloat(size) / ciImage.extent.height
    let scaled = ciImage.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))

    let context = CIContext(options: [.useSoftwareRenderer: true])
    return context.createCGImage(scaled, from: scaled.extent)
}

/// Build a compact JSON timing payload for a frame.
///
/// - Parameters:
///   - frameNum: Current frame number.
///   - time: Current time in seconds.
///   - fps: Frames per second.
///   - width: Video width.
///   - height: Video height.
///   - patternName: Name of the current pattern.
/// - Returns: JSON string like {"f":45,"t":1.5,"fps":30,"res":"1920x1080","pat":"..."}
func buildQRPayload(frameNum: Int, time: Double, fps: Int, width: Int, height: Int, patternName: String) -> String {
    let t = String(format: "%.4f", time)
    return "{\"f\":\(frameNum),\"t\":\(t),\"fps\":\(fps),\"res\":\"\(width)x\(height)\",\"pat\":\"\(patternName)\"}"
}

/// Composite a QR code onto a CGContext in the bottom-right corner.
///
/// - Parameters:
///   - context: The CGContext to draw into.
///   - width: Frame width.
///   - height: Frame height.
///   - frameNum: Current frame number.
///   - time: Current time in seconds.
///   - fps: Frames per second.
///   - patternName: Name of the current pattern.
///   - qrSize: Size of the QR code in pixels (default: ~8% of min dimension).
///   - margin: Margin from edges in pixels.
func compositeQRCode(
    context: CGContext,
    width: Int,
    height: Int,
    frameNum: Int,
    time: Double,
    fps: Int,
    patternName: String,
    qrSize: Int? = nil,
    margin: Int? = nil
) {
    let size = qrSize ?? max(60, min(width, height) * 8 / 100)
    let m = margin ?? max(4, height / 100)

    let payload = buildQRPayload(
        frameNum: frameNum,
        time: time,
        fps: fps,
        width: width,
        height: height,
        patternName: patternName
    )

    guard let qrImage = generateQRCode(payload: payload, size: size) else { return }

    // Bottom-right corner (CGContext has origin at bottom-left)
    let x = width - size - m
    let y = m  // bottom-right in CG coordinates
    context.draw(qrImage, in: CGRect(x: x, y: y, width: size, height: size))
}
