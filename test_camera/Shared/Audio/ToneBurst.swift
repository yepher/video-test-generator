//
//  ToneBurst.swift
//  TestCamera
//
//  Audio generation utilities: tone bursts, continuous tones, silence.
//  Port of the Python audio.py module to Swift.
//

import Foundation
import Accelerate

/// Generate a short sine tone burst with a Hann window envelope.
///
/// - Parameters:
///   - buffer: Output buffer to write samples into.
///   - offset: Starting index in the buffer.
///   - frequency: Tone frequency in Hz.
///   - durationMs: Burst duration in milliseconds.
///   - sampleRate: Audio sample rate.
///   - amplitude: Peak amplitude [0, 1].
/// - Returns: Number of samples written.
@discardableResult
func generateToneBurst(
    buffer: UnsafeMutablePointer<Float>,
    offset: Int,
    frequency: Double,
    durationMs: Double = 30.0,
    sampleRate: Int,
    amplitude: Float = 0.8
) -> Int {
    let nSamples = Int(Double(sampleRate) * durationMs / 1000.0)

    for i in 0..<nSamples {
        let t = Double(i) / Double(sampleRate)
        let sine = Float(sin(2.0 * .pi * frequency * t))

        // Hann window envelope
        let envelope = Float(0.5 * (1.0 - cos(2.0 * .pi * Double(i) / Double(nSamples))))

        buffer[offset + i] += sine * envelope * amplitude
    }

    return nSamples
}

/// Fill a buffer with a continuous sine tone.
///
/// - Parameters:
///   - buffer: Output buffer to fill.
///   - frameCount: Number of samples to generate.
///   - frequency: Tone frequency in Hz.
///   - sampleRate: Audio sample rate.
///   - amplitude: Peak amplitude [0, 1].
///   - startTime: Start time in seconds (for phase continuity).
func generateContinuousTone(
    buffer: UnsafeMutablePointer<Float>,
    frameCount: Int,
    frequency: Double,
    sampleRate: Int,
    amplitude: Float = 0.1,
    startTime: Double
) {
    for i in 0..<frameCount {
        let t = startTime + Double(i) / Double(sampleRate)
        buffer[i] = Float(sin(2.0 * .pi * frequency * t)) * amplitude
    }
}

/// Place tone bursts at beat times within an audio buffer.
///
/// - Parameters:
///   - buffer: Output buffer (should be zeroed first).
///   - frameCount: Buffer length in samples.
///   - beatTimes: Array of times (seconds) where bursts should occur.
///   - startTime: Start time of this buffer in seconds.
///   - frequency: Tone frequency in Hz.
///   - burstDurationMs: Duration of each burst in ms.
///   - sampleRate: Audio sample rate.
///   - amplitude: Peak amplitude.
func placeToneBursts(
    buffer: UnsafeMutablePointer<Float>,
    frameCount: Int,
    beatTimes: [Double],
    startTime: Double,
    frequency: Double = 1000.0,
    burstDurationMs: Double = 30.0,
    sampleRate: Int,
    amplitude: Float = 0.8
) {
    let endTime = startTime + Double(frameCount) / Double(sampleRate)
    let burstSamples = Int(Double(sampleRate) * burstDurationMs / 1000.0)

    for beatTime in beatTimes {
        // Check if this burst overlaps our buffer window
        let burstEnd = beatTime + Double(burstSamples) / Double(sampleRate)
        if burstEnd < startTime || beatTime >= endTime {
            continue
        }

        // Calculate where in our buffer this burst starts
        let sampleOffset = Int((beatTime - startTime) * Double(sampleRate))
        if sampleOffset >= frameCount { continue }

        let writeOffset = max(0, sampleOffset)
        let burstStart = max(0, -sampleOffset)
        let remaining = frameCount - writeOffset
        let count = min(burstSamples - burstStart, remaining)

        if count <= 0 { continue }

        // Generate the burst portion that falls in our buffer
        for i in 0..<count {
            let burstIdx = burstStart + i
            let t = Double(burstIdx) / Double(sampleRate)
            let sine = Float(sin(2.0 * .pi * frequency * t))
            let envelope = Float(0.5 * (1.0 - cos(2.0 * .pi * Double(burstIdx) / Double(burstSamples))))
            buffer[writeOffset + i] += sine * envelope * amplitude
        }
    }

    // Clip to [-1, 1]
    for i in 0..<frameCount {
        buffer[i] = max(-1.0, min(1.0, buffer[i]))
    }
}
