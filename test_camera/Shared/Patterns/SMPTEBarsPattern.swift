//
//  SMPTEBarsPattern.swift
//  TestCamera
//
//  SMPTE RP 219 color bars test pattern.
//  Port of patterns/smpte_bars.py to Swift/Core Graphics.
//

import Foundation
import CoreGraphics
import CoreText

class SMPTEBarsPattern: PatternRenderer {

    var name: String { "SMPTE Color Bars" }

    // Cache the static background as a CGImage
    private var cachedBackground: CGImage?
    private var cachedWidth: Int = 0
    private var cachedHeight: Int = 0

    // SMPTE bar colors (top section, L to R): 75% gray, yellow, cyan, green, magenta, red, blue
    private let topBars: [(CGFloat, CGFloat, CGFloat)] = [
        (0.75, 0.75, 0.75), (0.75, 0.75, 0.0), (0.0, 0.75, 0.75), (0.0, 0.75, 0.0),
        (0.75, 0.0, 0.75), (0.75, 0.0, 0.0), (0.0, 0.0, 0.75)
    ]

    // Middle castellations (reverse subset)
    private let midBars: [(CGFloat, CGFloat, CGFloat)] = [
        (0.0, 0.0, 0.75), (0.075, 0.075, 0.075), (0.75, 0.0, 0.75), (0.075, 0.075, 0.075),
        (0.0, 0.75, 0.75), (0.075, 0.075, 0.075), (0.75, 0.75, 0.75)
    ]

    // PLUGE colors
    private let plugeLeft: [(CGFloat, CGFloat, CGFloat)] = [
        (0.0, 0.13, 0.30),   // -I
        (0.75, 0.75, 0.75),  // 75% white
        (0.20, 0.0, 0.42)    // +Q
    ]

    func renderFrame(context: CGContext, width: Int, height: Int, time: Double, frameNum: Int) {
        // Draw cached background or build it
        if cachedBackground == nil || cachedWidth != width || cachedHeight != height {
            cachedBackground = buildBackground(width: width, height: height)
            cachedWidth = width
            cachedHeight = height
        }

        if let bg = cachedBackground {
            context.draw(bg, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        // Draw dynamic overlay: timestamp and frame counter
        drawOverlay(context: context, width: width, height: height, time: time, frameNum: frameNum)
    }

    func generateAudioSamples(buffer: UnsafeMutablePointer<Float>, frameCount: Int, sampleRate: Int, time: Double) {
        // Continuous 1 kHz tone at -20 dBFS
        let amplitude = Float(pow(10.0, -20.0 / 20.0))
        generateContinuousTone(
            buffer: buffer,
            frameCount: frameCount,
            frequency: 1000.0,
            sampleRate: sampleRate,
            amplitude: amplitude,
            startTime: time
        )
    }

    // MARK: - Private

    private func buildBackground(width: Int, height: Int) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        let W = CGFloat(width)
        let H = CGFloat(height)
        let topH = H * 0.67
        let midH = H * 0.08
        let barW = W / 7.0

        // Top bars
        for (i, color) in topBars.enumerated() {
            ctx.setFillColor(red: color.0, green: color.1, blue: color.2, alpha: 1.0)
            ctx.fill(CGRect(x: CGFloat(i) * barW, y: H - topH, width: barW + 1, height: topH))
        }

        // Middle castellations
        let midY = H - topH - midH
        for (i, color) in midBars.enumerated() {
            ctx.setFillColor(red: color.0, green: color.1, blue: color.2, alpha: 1.0)
            ctx.fill(CGRect(x: CGFloat(i) * barW, y: midY, width: barW + 1, height: midH))
        }

        // Bottom PLUGE
        let botH = midY
        // First 3 bars: -I, White, +Q
        for (i, color) in plugeLeft.enumerated() {
            ctx.setFillColor(red: color.0, green: color.1, blue: color.2, alpha: 1.0)
            ctx.fill(CGRect(x: CGFloat(i) * barW, y: 0, width: barW + 1, height: botH))
        }

        // Remaining 4 bars: black with PLUGE inserts
        let blackX = 3.0 * barW
        let blackW = W - blackX
        ctx.setFillColor(red: 0.075, green: 0.075, blue: 0.075, alpha: 1.0)
        ctx.fill(CGRect(x: blackX, y: 0, width: blackW, height: botH))

        // PLUGE inserts
        let insertW = blackW / 7.0
        let inserts: [(CGFloat, CGFloat, CGFloat, Int)] = [
            (0.0, 0.0, 0.0, 1),           // sub-black
            (0.075, 0.075, 0.075, 2),      // black
            (0.114, 0.114, 0.114, 3),      // super-white
            (0.075, 0.075, 0.075, 4),      // black
        ]
        for (r, g, b, idx) in inserts {
            ctx.setFillColor(red: r, green: g, blue: b, alpha: 1.0)
            ctx.fill(CGRect(x: blackX + CGFloat(idx) * insertW, y: 0, width: insertW + 1, height: botH))
        }

        // Title label
        let titleFont = CTFontCreateWithName("Helvetica" as CFString, CGFloat(height) * 0.02, nil)
        let titleAttrs: [NSAttributedString.Key: Any] = [
            kCTFontAttributeName as NSAttributedString.Key: titleFont,
            kCTForegroundColorAttributeName as NSAttributedString.Key: CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        ]
        let title = NSAttributedString(string: "SMPTE Color Bars", attributes: titleAttrs)
        let line = CTLineCreateWithAttributedString(title)
        let titleBounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        ctx.textPosition = CGPoint(x: (W - titleBounds.width) / 2, y: H - CGFloat(height) * 0.03)
        CTLineDraw(line, ctx)

        return ctx.makeImage()
    }

    private func drawOverlay(context: CGContext, width: Int, height: Int, time: Double, frameNum: Int) {
        let fontSize = CGFloat(max(14, height) * 2 / 100)
        let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let color = CGColor(red: 0.78, green: 0.78, blue: 0.78, alpha: 1.0)
        let attrs: [NSAttributedString.Key: Any] = [
            kCTFontAttributeName as NSAttributedString.Key: font,
            kCTForegroundColorAttributeName as NSAttributedString.Key: color
        ]
        let margin = CGFloat(width) * 0.02

        // Frame info (bottom-left)
        let frameText = NSAttributedString(string: "Frame: \(frameNum)  |  \(width)x\(height) @ \(kFrameRate)fps", attributes: attrs)
        let frameLine = CTLineCreateWithAttributedString(frameText)
        context.textPosition = CGPoint(x: margin, y: fontSize * 0.5)
        CTLineDraw(frameLine, context)

        // Time (bottom-right)
        let timeStr = String(format: "Time: %.2fs", time)
        let timeText = NSAttributedString(string: timeStr, attributes: attrs)
        let timeLine = CTLineCreateWithAttributedString(timeText)
        let timeBounds = CTLineGetBoundsWithOptions(timeLine, .useOpticalBounds)
        context.textPosition = CGPoint(x: CGFloat(width) - margin - timeBounds.width, y: fontSize * 0.5)
        CTLineDraw(timeLine, context)
    }
}
