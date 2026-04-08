//
//  AudioPatterns.h
//  TestCameraAudioDriver
//
//  Audio generation functions matching each video test pattern.
//  Called from the HAL plugin's DoIOOperation to fill audio buffers.
//

#ifndef AudioPatterns_h
#define AudioPatterns_h

#include <stdint.h>

// ============================================================================
// Audio generation context (maintains state across buffer boundaries)
// ============================================================================

struct AudioGenContext {
    double phase;           // Phase accumulator (0 to 2*PI)
    double sampleRate;      // Sample rate (48000)
    int patternID;          // Current pattern
    double streamTime;      // Time offset from stream start
};

// ============================================================================
// Per-pattern audio generation
// ============================================================================

/// Bouncing Ball: tone bursts at each beat (1 per second)
/// Generates 30ms 1kHz tone bursts at integer second boundaries
void generateBouncingBallAudio(float *buffer, uint32_t frameCount,
                                AudioGenContext *ctx);

/// SMPTE Color Bars: continuous 1kHz tone at -20dBFS
void generateSMPTEBarsAudio(float *buffer, uint32_t frameCount,
                             AudioGenContext *ctx);

/// Grid Chart: silence
void generateGridChartAudio(float *buffer, uint32_t frameCount,
                             AudioGenContext *ctx);

/// Countdown: beep at each second, double-beep at 2 (2-pop)
void generateCountdownAudio(float *buffer, uint32_t frameCount,
                             AudioGenContext *ctx);

/// Main dispatch: generate audio for the current pattern
void generatePatternAudio(float *buffer, uint32_t frameCount,
                           AudioGenContext *ctx);

#endif /* AudioPatterns_h */
