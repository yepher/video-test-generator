//
//  CountdownPattern.swift
//  TestCamera
//
//  Classic film-style countdown leader (10 to 0) with sweep hand,
//  color-coded seconds, beeps at each second, and a 2-pop flash.
//  Port of patterns/countdown.py to Swift/Core Graphics.
//

import Foundation
import CoreGraphics
import CoreText

class CountdownPattern: PatternRenderer {

    var name: String { "Countdown Leader" }

    private let beepFreq: Double = 1000.0
    private let popFreq: Double = 1000.0

    // Color per countdown number (ring accent)
    private let countdownColors: [Int: (CGFloat, CGFloat, CGFloat)] = [
        10: (0.16, 0.16, 0.16),
        9:  (0.0, 0.24, 0.0),
        8:  (0.0, 0.0, 0.31),
        7:  (0.24, 0.0, 0.24),
        6:  (0.31, 0.16, 0.0),
        5:  (0.0, 0.24, 0.24),
        4:  (0.24, 0.24, 0.0),
        3:  (0.31, 0.0, 0.0),
        2:  (1.0, 1.0, 1.0),
        1:  (0.16, 0.16, 0.16),
        0:  (0.0, 0.0, 0.0),
    ]

    func renderFrame(context: CGContext, width: Int, height: Int, time: Double, frameNum: Int) {
        let W = CGFloat(width)
        let H = CGFloat(height)
        let cx = W / 2
        let cy = H / 2
        let fps = kFrameRate

        let countdownStart = min(10, Int(30.0)) // assume max 30s duration
        let currentSecond = Int(time)
        let count = countdownStart - currentSecond
        let frac = time - Double(currentSecond)

        // Flash frame at count=2
        let isFlash = (count == 2 && frac < 2.0 / Double(fps))

        // Background
        if isFlash {
            context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        } else {
            context.setFillColor(red: 0.08, green: 0.08, blue: 0.08, alpha: 1)
        }
        context.fill(CGRect(x: 0, y: 0, width: W, height: H))

        // Colors based on flash state
        let fg: (CGFloat, CGFloat, CGFloat) = isFlash || count == 2 ? (0, 0, 0) : (1, 1, 1)
        let ringColor: (CGFloat, CGFloat, CGFloat)
        if isFlash || count == 2 {
            ringColor = (0, 0, 0)
        } else if let c = countdownColors[count], c != (0, 0, 0) && c != (0.16, 0.16, 0.16) {
            ringColor = c
        } else {
            ringColor = (0.39, 0.39, 0.39)
        }

        // Outer ring
        let ringR = min(cx, cy) * 0.75
        let ringW = CGFloat(max(4, height * 6 / 1000))
        context.setStrokeColor(red: ringColor.0, green: ringColor.1, blue: ringColor.2, alpha: 1)
        context.setLineWidth(ringW)
        context.strokeEllipse(in: CGRect(x: cx - ringR, y: cy - ringR, width: ringR * 2, height: ringR * 2))

        // Inner ring
        let innerR = ringR * 0.85
        context.setLineWidth(max(2, ringW / 2))
        context.strokeEllipse(in: CGRect(x: cx - innerR, y: cy - innerR, width: innerR * 2, height: innerR * 2))

        // Crosshairs
        context.setLineWidth(max(1, ringW / 3))
        context.move(to: CGPoint(x: cx - ringR, y: cy))
        context.addLine(to: CGPoint(x: cx + ringR, y: cy))
        context.move(to: CGPoint(x: cx, y: cy - ringR))
        context.addLine(to: CGPoint(x: cx, y: cy + ringR))
        context.strokePath()

        // Sweep wedge (filled pie)
        if !isFlash {
            let startAngle = CGFloat.pi / 2  // 12 o'clock
            let endAngle = startAngle - CGFloat(frac) * 2 * .pi

            context.setFillColor(red: ringColor.0, green: ringColor.1, blue: ringColor.2, alpha: 0.6)
            context.move(to: CGPoint(x: cx, y: cy))
            context.addArc(center: CGPoint(x: cx, y: cy), radius: innerR,
                           startAngle: startAngle, endAngle: endAngle, clockwise: true)
            context.closePath()
            context.fillPath()
        }

        // Sweep hand line
        let handAngle = CGFloat.pi / 2 - CGFloat(frac) * 2 * .pi
        let handLen = ringR * 0.95
        let hx = cx + handLen * cos(handAngle)
        let hy = cy + handLen * sin(handAngle)
        context.setStrokeColor(red: 0.78, green: 0.78, blue: 0.78, alpha: 1)
        context.setLineWidth(CGFloat(max(2, height * 4 / 1000)))
        context.move(to: CGPoint(x: cx, y: cy))
        context.addLine(to: CGPoint(x: hx, y: hy))
        context.strokePath()

        // Countdown number
        if count >= 0 {
            let numStr = "\(count)"
            let numFontSize = CGFloat(min(width, height)) * 0.35
            let numFont = CTFontCreateWithName("Helvetica-Bold" as CFString, numFontSize, nil)
            let numAttrs: [NSAttributedString.Key: Any] = [
                kCTFontAttributeName as NSAttributedString.Key: numFont,
                kCTForegroundColorAttributeName as NSAttributedString.Key: CGColor(red: fg.0, green: fg.1, blue: fg.2, alpha: 1)
            ]
            let attrStr = NSAttributedString(string: numStr, attributes: numAttrs)
            let line = CTLineCreateWithAttributedString(attrStr)
            let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
            context.textPosition = CGPoint(
                x: cx - bounds.width / 2,
                y: cy - bounds.height / 2
            )
            CTLineDraw(line, context)
        }

        // Frame info (bottom-left)
        let smallFontSize = CGFloat(max(12, height * 2 / 100))
        let smallFont = CTFontCreateWithName("Helvetica" as CFString, smallFontSize, nil)
        let infoAttrs: [NSAttributedString.Key: Any] = [
            kCTFontAttributeName as NSAttributedString.Key: smallFont,
            kCTForegroundColorAttributeName as NSAttributedString.Key: CGColor(red: 0.5, green: 0.5, blue: 0.5, alpha: 1)
        ]
        let infoText = NSAttributedString(string: "Frame \(frameNum)  |  \(width)x\(height) @ \(kFrameRate)fps", attributes: infoAttrs)
        let infoLine = CTLineCreateWithAttributedString(infoText)
        context.textPosition = CGPoint(x: 10, y: smallFontSize * 0.5)
        CTLineDraw(infoLine, context)

        // Time (bottom-right)
        let timeStr = String(format: "%.2fs", time)
        let timeText = NSAttributedString(string: timeStr, attributes: infoAttrs)
        let timeLine = CTLineCreateWithAttributedString(timeText)
        let timeBounds = CTLineGetBoundsWithOptions(timeLine, .useOpticalBounds)
        context.textPosition = CGPoint(x: W - timeBounds.width - 10, y: smallFontSize * 0.5)
        CTLineDraw(timeLine, context)
    }

    func generateAudioSamples(buffer: UnsafeMutablePointer<Float>, frameCount: Int, sampleRate: Int, time: Double) {
        buffer.initialize(repeating: 0, count: frameCount)

        let endTime = time + Double(frameCount) / Double(sampleRate)
        let firstBeat = floor(time)

        var t = firstBeat
        while t <= endTime + 0.001 {
            if t >= 0 {
                let countdownStart = 10
                let count = countdownStart - Int(t)

                let burstMs: Double
                let amplitude: Float
                if count == 2 {
                    burstMs = 80.0
                    amplitude = 0.9
                } else if count >= 0 {
                    burstMs = 30.0
                    amplitude = 0.7
                } else {
                    t += 1.0
                    continue
                }

                placeToneBursts(
                    buffer: buffer,
                    frameCount: frameCount,
                    beatTimes: [t],
                    startTime: time,
                    frequency: count == 2 ? popFreq : beepFreq,
                    burstDurationMs: burstMs,
                    sampleRate: sampleRate,
                    amplitude: amplitude
                )
            }
            t += 1.0
        }
    }
}
