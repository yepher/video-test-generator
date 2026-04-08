//
//  GridChartPattern.swift
//  TestCamera
//
//  Grid/resolution test chart pattern.
//  Port of patterns/grid_chart.py to Swift/Core Graphics.
//

import Foundation
import CoreGraphics
import CoreText

class GridChartPattern: PatternRenderer {

    var name: String { "Grid/Resolution Chart" }

    private var cachedBackground: CGImage?
    private var cachedWidth: Int = 0
    private var cachedHeight: Int = 0

    func renderFrame(context: CGContext, width: Int, height: Int, time: Double, frameNum: Int) {
        if cachedBackground == nil || cachedWidth != width || cachedHeight != height {
            cachedBackground = buildBackground(width: width, height: height)
            cachedWidth = width
            cachedHeight = height
        }

        if let bg = cachedBackground {
            context.draw(bg, in: CGRect(x: 0, y: 0, width: width, height: height))
        }

        drawOverlay(context: context, width: width, height: height, time: time, frameNum: frameNum)
    }

    func generateAudioSamples(buffer: UnsafeMutablePointer<Float>, frameCount: Int, sampleRate: Int, time: Double) {
        // Silence
        buffer.initialize(repeating: 0, count: frameCount)
    }

    private func buildBackground(width: Int, height: Int) -> CGImage? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        let W = CGFloat(width)
        let H = CGFloat(height)
        let cx = W / 2
        let cy = H / 2

        // Black background
        ctx.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))

        // Fine grid
        let majorStep = max(1, height / 10)
        let minorStep = majorStep / 2

        // Minor grid lines
        ctx.setStrokeColor(red: 0.16, green: 0.16, blue: 0.16, alpha: 1)
        ctx.setLineWidth(1)
        for x in stride(from: 0, to: width, by: minorStep) {
            ctx.move(to: CGPoint(x: CGFloat(x), y: 0))
            ctx.addLine(to: CGPoint(x: CGFloat(x), y: H))
        }
        for y in stride(from: 0, to: height, by: minorStep) {
            ctx.move(to: CGPoint(x: 0, y: CGFloat(y)))
            ctx.addLine(to: CGPoint(x: W, y: CGFloat(y)))
        }
        ctx.strokePath()

        // Major grid lines
        ctx.setStrokeColor(red: 0.31, green: 0.31, blue: 0.31, alpha: 1)
        for x in stride(from: 0, to: width, by: majorStep) {
            ctx.move(to: CGPoint(x: CGFloat(x), y: 0))
            ctx.addLine(to: CGPoint(x: CGFloat(x), y: H))
        }
        for y in stride(from: 0, to: height, by: majorStep) {
            ctx.move(to: CGPoint(x: 0, y: CGFloat(y)))
            ctx.addLine(to: CGPoint(x: W, y: CGFloat(y)))
        }
        ctx.strokePath()

        // Concentric circles
        let maxR = min(cx, cy)
        ctx.setStrokeColor(red: 0, green: 0.7, blue: 0, alpha: 1)
        ctx.setLineWidth(1)
        for frac in [0.2, 0.4, 0.6, 0.8, 1.0] {
            let r = maxR * CGFloat(frac)
            ctx.strokeEllipse(in: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
        }

        // Center crosshair
        let crossLen = maxR * 0.15
        ctx.setStrokeColor(red: 1, green: 1, blue: 1, alpha: 1)
        ctx.setLineWidth(2)
        ctx.move(to: CGPoint(x: cx - crossLen, y: cy))
        ctx.addLine(to: CGPoint(x: cx + crossLen, y: cy))
        ctx.move(to: CGPoint(x: cx, y: cy - crossLen))
        ctx.addLine(to: CGPoint(x: cx, y: cy + crossLen))
        ctx.strokePath()

        // Small center circle
        let cr = CGFloat(max(3, height * 5 / 1000))
        ctx.strokeEllipse(in: CGRect(x: cx - cr, y: cy - cr, width: cr * 2, height: cr * 2))

        // Corner resolution wedges
        let wedgeLen = CGFloat(min(width, height)) * 0.12
        ctx.setStrokeColor(red: 0.7, green: 0.7, blue: 0.7, alpha: 1)
        ctx.setLineWidth(1)
        let corners: [(CGFloat, CGFloat, CGFloat, CGFloat)] = [
            (0, 0, 1, 1), (W, 0, -1, 1), (0, H, 1, -1), (W, H, -1, -1)
        ]
        for (ox, oy, dx, dy) in corners {
            for angleOffset in stride(from: -30, through: 30, by: 5) {
                let baseAngle: Double = (dx == dy) ? 45 : -45
                let rad = (baseAngle + Double(angleOffset)) * .pi / 180
                let ex = ox + dx * abs(CGFloat(cos(rad))) * wedgeLen
                let ey = oy + dy * abs(CGFloat(sin(rad))) * wedgeLen
                ctx.move(to: CGPoint(x: ox, y: oy))
                ctx.addLine(to: CGPoint(x: ex, y: ey))
            }
        }
        ctx.strokePath()

        // Safe area outlines (90% and 80%)
        for (pct, gray): (CGFloat, CGFloat) in [(0.9, 0.24), (0.8, 0.20)] {
            let mx = W * (1 - pct) / 2
            let my = H * (1 - pct) / 2
            ctx.setStrokeColor(red: gray, green: gray, blue: gray, alpha: 1)
            ctx.stroke(CGRect(x: mx, y: my, width: W - 2 * mx, height: H - 2 * my))
        }

        // Grayscale ramp along bottom
        let rampH = CGFloat(max(20, height * 3 / 100))
        let nSteps = 32
        let stepW = W / CGFloat(nSteps)
        for i in 0..<nSteps {
            let val = CGFloat(i) / CGFloat(nSteps - 1)
            ctx.setFillColor(red: val, green: val, blue: val, alpha: 1)
            ctx.fill(CGRect(x: CGFloat(i) * stepW, y: 0, width: stepW + 1, height: rampH))
        }

        // Title
        let fontSize = CGFloat(max(14, height * 25 / 1000))
        let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let attrs: [NSAttributedString.Key: Any] = [
            kCTFontAttributeName as NSAttributedString.Key: font,
            kCTForegroundColorAttributeName as NSAttributedString.Key: CGColor(red: 0.78, green: 0.78, blue: 0.78, alpha: 1)
        ]
        let title = NSAttributedString(string: "Resolution & Geometry Chart", attributes: attrs)
        let line = CTLineCreateWithAttributedString(title)
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        ctx.textPosition = CGPoint(x: (W - bounds.width) / 2, y: H - fontSize - 8)
        CTLineDraw(line, ctx)

        // Resolution label
        let resText = NSAttributedString(string: "\(width) x \(height)", attributes: attrs)
        let resLine = CTLineCreateWithAttributedString(resText)
        let resBounds = CTLineGetBoundsWithOptions(resLine, .useOpticalBounds)
        ctx.textPosition = CGPoint(x: (W - resBounds.width) / 2, y: H - 2 * fontSize - 12)
        CTLineDraw(resLine, ctx)

        return ctx.makeImage()
    }

    private func drawOverlay(context: CGContext, width: Int, height: Int, time: Double, frameNum: Int) {
        let fontSize = CGFloat(max(14, height * 2 / 100))
        let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let attrs: [NSAttributedString.Key: Any] = [
            kCTFontAttributeName as NSAttributedString.Key: font,
            kCTForegroundColorAttributeName as NSAttributedString.Key: CGColor(red: 0.78, green: 0.78, blue: 0.78, alpha: 1)
        ]
        let margin = CGFloat(width) * 0.02
        let rampH = CGFloat(max(20, height * 3 / 100))
        let overlayY = rampH + fontSize * 0.3

        // Frame info
        let frameText = NSAttributedString(string: "Frame: \(frameNum)  |  \(width)x\(height) @ \(kFrameRate)fps", attributes: attrs)
        let frameLine = CTLineCreateWithAttributedString(frameText)
        context.textPosition = CGPoint(x: margin, y: overlayY)
        CTLineDraw(frameLine, context)

        // Time
        let timeStr = String(format: "Time: %.2fs", time)
        let timeText = NSAttributedString(string: timeStr, attributes: attrs)
        let timeLine = CTLineCreateWithAttributedString(timeText)
        let timeBounds = CTLineGetBoundsWithOptions(timeLine, .useOpticalBounds)
        context.textPosition = CGPoint(x: CGFloat(width) - margin - timeBounds.width, y: overlayY)
        CTLineDraw(timeLine, context)
    }
}
