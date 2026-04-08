//
//  PatternRenderer.swift
//  TestCamera
//
//  Protocol that all test patterns implement. Provides both video frame
//  rendering (via Core Graphics) and audio sample generation.
//

import Foundation
import CoreGraphics

/// Protocol for test pattern renderers.
///
/// Each pattern implements frame rendering into a CGContext and audio
/// sample generation. Both methods receive the current time so they
/// stay in sync.
protocol PatternRenderer {

    /// Human-readable name of this pattern.
    var name: String { get }

    /// Render one video frame into the provided CGContext.
    ///
    /// - Parameters:
    ///   - context: The CGContext backed by a CVPixelBuffer (BGRA, premultiplied alpha).
    ///   - width: Frame width in pixels.
    ///   - height: Frame height in pixels.
    ///   - time: Current time in seconds since stream start.
    ///   - frameNum: Current frame number (0-based).
    func renderFrame(context: CGContext, width: Int, height: Int, time: Double, frameNum: Int)

    /// Generate audio samples for the current time window.
    ///
    /// - Parameters:
    ///   - buffer: Pointer to a Float buffer to fill with samples in [-1, 1].
    ///   - frameCount: Number of audio frames (samples) to generate.
    ///   - sampleRate: Audio sample rate (e.g. 48000).
    ///   - time: Start time of this audio buffer in seconds.
    func generateAudioSamples(buffer: UnsafeMutablePointer<Float>, frameCount: Int, sampleRate: Int, time: Double)
}

/// Factory to create a pattern renderer for a given pattern type.
func createPatternRenderer(for type: PatternType) -> PatternRenderer {
    switch type {
    case .bouncingBall: return BouncingBallPattern()
    case .smpteBars: return SMPTEBarsPattern()
    case .gridChart: return GridChartPattern()
    case .countdown: return CountdownPattern()
    }
}
