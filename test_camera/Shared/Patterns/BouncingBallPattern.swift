//
//  BouncingBallPattern.swift
//  TestCamera
//
//  Bouncing ball audio/video sync test pattern.
//  Port of patterns/bouncing_ball.py to Swift/Core Graphics.
//
//  A ball sweeps back and forth across a horizontal timeline ruler.
//  Each time it crosses the center mark, a tone burst plays.
//  A pie-chart clock shows elapsed time within the current second.
//

import Foundation
import CoreGraphics
import CoreText

class BouncingBallPattern: PatternRenderer {

    var name: String { "Bouncing Ball A/V Sync" }

    private let toneFreq: Double = 1000.0
    private let burstMs: Double = 30.0
    private let beatPeriod: Double = 1.0

    // Colors
    private let bgColor = (r: CGFloat(0), g: CGFloat(0), b: CGFloat(0))
    private let fgColor = (r: CGFloat(1), g: CGFloat(1), b: CGFloat(1))
    private let accentColor = (r: CGFloat(0), g: CGFloat(0.7), b: CGFloat(0))
    private let rulerColor = (r: CGFloat(0.78), g: CGFloat(0.78), b: CGFloat(0))
    private let titleColor = (r: CGFloat(0.86), g: CGFloat(0.63), b: CGFloat(0))

    func renderFrame(context: CGContext, width: Int, height: Int, time: Double, frameNum: Int) {
        let W = CGFloat(width)
        let H = CGFloat(height)

        // Clear to black
        context.setFillColor(red: 0, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: W, height: H))

        // Note: CGContext origin is bottom-left. We'll work in that coordinate system.
        // Invert Y references from the Python code (which uses top-left origin).

        let marginX = W * 0.05
        let rulerY = H * 0.15          // ruler at 15% from bottom (was 85% from top)
        let rulerH = H * 0.04
        let ballY = H * 0.32           // ball at 32% from bottom (was 68% from top)
        let ballR = CGFloat(max(10, min(width, height)) * 3 / 100)

        let rulerLeft = marginX
        let rulerRight = W - marginX
        let rulerWidth = rulerRight - rulerLeft
        let rulerCenterX = (rulerLeft + rulerRight) / 2

        // --- Ruler ---
        context.setStrokeColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.setLineWidth(2)
        context.move(to: CGPoint(x: rulerLeft, y: rulerY))
        context.addLine(to: CGPoint(x: rulerRight, y: rulerY))
        context.strokePath()

        // Tick marks: 21 divisions (-1.0 to +1.0, step 0.1)
        for i in 0...20 {
            let frac = CGFloat(i) / 20.0
            let x = rulerLeft + frac * rulerWidth
            let val = -1.0 + Double(i) * 0.1

            let isMajor = abs(val) < 0.001 || abs(abs(val) - 1.0) < 0.001
            let tickH = isMajor ? rulerH : rulerH * 0.6
            let tickW: CGFloat = isMajor ? 3 : 1

            if isMajor {
                context.setStrokeColor(red: 1, green: 1, blue: 1, alpha: 1)
            } else {
                context.setStrokeColor(red: rulerColor.r, green: rulerColor.g, blue: rulerColor.b, alpha: 1)
            }
            context.setLineWidth(tickW)
            context.move(to: CGPoint(x: x, y: rulerY - tickH))
            context.addLine(to: CGPoint(x: x, y: rulerY + tickH))
            context.strokePath()
        }

        // Ruler labels
        let smallFontSize = CGFloat(max(12, height * 25 / 1000))
        let smallFont = CTFontCreateWithName("Helvetica" as CFString, smallFontSize, nil)
        let rulerAttrs: [NSAttributedString.Key: Any] = [
            kCTFontAttributeName as NSAttributedString.Key: smallFont,
            kCTForegroundColorAttributeName as NSAttributedString.Key: CGColor(red: rulerColor.r, green: rulerColor.g, blue: rulerColor.b, alpha: 1)
        ]

        let labelY = rulerY - rulerH - smallFontSize - 5
        drawText(context: context, text: "-1", x: rulerLeft, y: labelY, attrs: rulerAttrs)
        drawText(context: context, text: "0", x: rulerCenterX - 5, y: labelY, attrs: rulerAttrs)
        drawText(context: context, text: "1", x: rulerRight - 15, y: labelY, attrs: rulerAttrs)

        // "10ths of a second" labels
        let quarterX = (rulerLeft + rulerCenterX) / 2
        let threeQuarterX = (rulerCenterX + rulerRight) / 2
        drawText(context: context, text: "10ths of a second", x: quarterX - 60, y: labelY, attrs: rulerAttrs)
        drawText(context: context, text: "10ths of a second", x: threeQuarterX - 60, y: labelY, attrs: rulerAttrs)

        // --- Ball position ---
        let cycleT = time.truncatingRemainder(dividingBy: 2.0)
        let ballX: CGFloat
        if cycleT < 1.0 {
            let frac = CGFloat(sin(cycleT * .pi))
            ballX = rulerCenterX + frac * (rulerWidth / 2)
        } else {
            let frac = CGFloat(sin((cycleT - 1.0) * .pi))
            ballX = rulerCenterX - frac * (rulerWidth / 2)
        }

        // Vertical reference line from ball to ruler
        context.setStrokeColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.setLineWidth(2)
        context.move(to: CGPoint(x: ballX, y: ballY - ballR))
        context.addLine(to: CGPoint(x: ballX, y: rulerY))
        context.strokePath()

        // Ball
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fillEllipse(in: CGRect(x: ballX - ballR, y: ballY - ballR, width: ballR * 2, height: ballR * 2))

        // --- Pie chart clock (upper-left area) ---
        let pieCX = W * 0.2
        let pieCY = H * 0.7     // 70% from bottom = 30% from top
        let pieR = CGFloat(min(width, height)) * 0.18

        // White circle
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fillEllipse(in: CGRect(x: pieCX - pieR, y: pieCY - pieR, width: pieR * 2, height: pieR * 2))

        // Green pie slice
        let fracSecond = time.truncatingRemainder(dividingBy: 1.0)
        if fracSecond > 0.001 {
            context.setFillColor(red: accentColor.r, green: accentColor.g, blue: accentColor.b, alpha: 1)
            context.move(to: CGPoint(x: pieCX, y: pieCY))
            // Start at 12 o'clock (90 degrees in CG), sweep clockwise (negative angle)
            let startAngle = CGFloat.pi / 2
            let endAngle = startAngle - CGFloat(fracSecond) * 2 * .pi
            context.addArc(center: CGPoint(x: pieCX, y: pieCY), radius: pieR,
                           startAngle: startAngle, endAngle: endAngle, clockwise: true)
            context.closePath()
            context.fillPath()
        }

        // --- Title ---
        let titleFontSize = CGFloat(max(16, height * 4 / 100))
        let titleFont = CTFontCreateWithName("Helvetica" as CFString, titleFontSize, nil)
        let titleAttrs: [NSAttributedString.Key: Any] = [
            kCTFontAttributeName as NSAttributedString.Key: titleFont,
            kCTForegroundColorAttributeName as NSAttributedString.Key: CGColor(red: titleColor.r, green: titleColor.g, blue: titleColor.b, alpha: 1)
        ]
        drawTextCentered(context: context, text: "Audio/Video Sync Test", y: H - H * 0.07, width: W, attrs: titleAttrs)

        // Time counter
        let timeStr = String(format: "Time: %.2fs", time)
        drawTextCentered(context: context, text: timeStr, y: H - H * 0.07 - titleFontSize - 10, width: W, attrs: rulerAttrs)

        // Frame info (top-left in visual, which is high-Y in CG)
        let grayAttrs: [NSAttributedString.Key: Any] = [
            kCTFontAttributeName as NSAttributedString.Key: smallFont,
            kCTForegroundColorAttributeName as NSAttributedString.Key: CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        ]
        drawText(context: context, text: "Frame: \(frameNum)  FPS: \(kFrameRate)", x: marginX, y: H - H * 0.04, attrs: grayAttrs)
    }

    func generateAudioSamples(buffer: UnsafeMutablePointer<Float>, frameCount: Int, sampleRate: Int, time: Double) {
        // Zero the buffer
        buffer.initialize(repeating: 0, count: frameCount)

        // Generate beat times (every 1 second)
        let endTime = time + Double(frameCount) / Double(sampleRate)
        let firstBeat = floor(time)
        var beatTimes: [Double] = []
        var t = firstBeat
        while t <= endTime + 0.001 {
            if t >= 0 {
                beatTimes.append(t)
            }
            t += beatPeriod
        }

        placeToneBursts(
            buffer: buffer,
            frameCount: frameCount,
            beatTimes: beatTimes,
            startTime: time,
            frequency: toneFreq,
            burstDurationMs: burstMs,
            sampleRate: sampleRate
        )
    }

    // MARK: - Text helpers

    private func drawText(context: CGContext, text: String, x: CGFloat, y: CGFloat, attrs: [NSAttributedString.Key: Any]) {
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let line = CTLineCreateWithAttributedString(attrStr)
        context.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(line, context)
    }

    private func drawTextCentered(context: CGContext, text: String, y: CGFloat, width: CGFloat, attrs: [NSAttributedString.Key: Any]) {
        let attrStr = NSAttributedString(string: text, attributes: attrs)
        let line = CTLineCreateWithAttributedString(attrStr)
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        context.textPosition = CGPoint(x: (width - bounds.width) / 2, y: y)
        CTLineDraw(line, context)
    }
}
