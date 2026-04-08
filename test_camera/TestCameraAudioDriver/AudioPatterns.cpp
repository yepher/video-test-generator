//
//  AudioPatterns.cpp
//  TestCameraAudioDriver
//
//  Audio generation matching each video test pattern.
//  Port of ToneBurst.swift to C++ for use in the HAL plugin.
//

#include "AudioPatterns.h"
#include <math.h>
#include <string.h>

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

// ============================================================================
// Helper: Generate a Hann-windowed tone burst into a buffer
// ============================================================================

static void toneBurst(float *buffer, uint32_t offset, uint32_t maxFrames,
                      double frequency, double durationMs,
                      double sampleRate, float amplitude, double *phase)
{
    uint32_t nSamples = (uint32_t)(sampleRate * durationMs / 1000.0);
    if (offset >= maxFrames) return;

    uint32_t end = offset + nSamples;
    if (end > maxFrames) end = maxFrames;

    for (uint32_t i = offset; i < end; i++) {
        uint32_t burstIdx = i - offset;
        double t = (double)burstIdx / sampleRate;
        float sine = (float)sin(2.0 * M_PI * frequency * t);

        // Hann window envelope
        float envelope = (float)(0.5 * (1.0 - cos(2.0 * M_PI * (double)burstIdx / (double)nSamples)));

        buffer[i] += sine * envelope * amplitude;
    }
}

// ============================================================================
// Bouncing Ball: 30ms 1kHz tone bursts at each integer second
// ============================================================================

void generateBouncingBallAudio(float *buffer, uint32_t frameCount,
                                AudioGenContext *ctx)
{
    memset(buffer, 0, frameCount * sizeof(float));

    double startTime = ctx->streamTime;
    double endTime = startTime + (double)frameCount / ctx->sampleRate;
    double burstDurationMs = 30.0;
    double burstDurationSec = burstDurationMs / 1000.0;

    // Check each integer second that might overlap this buffer
    int firstBeat = (int)floor(startTime);
    if (firstBeat < 0) firstBeat = 0;
    int lastBeat = (int)floor(endTime) + 1;

    for (int beat = firstBeat; beat <= lastBeat; beat++) {
        double beatTime = (double)beat;
        double beatEnd = beatTime + burstDurationSec;

        // Skip if burst doesn't overlap our buffer
        if (beatEnd < startTime || beatTime >= endTime) continue;

        // Calculate sample offset in our buffer
        int sampleOffset = (int)((beatTime - startTime) * ctx->sampleRate);
        if (sampleOffset < 0) sampleOffset = 0;
        if ((uint32_t)sampleOffset >= frameCount) continue;

        toneBurst(buffer, (uint32_t)sampleOffset, frameCount,
                  1000.0, burstDurationMs, ctx->sampleRate, 0.8, &ctx->phase);
    }

    // Clip
    for (uint32_t i = 0; i < frameCount; i++) {
        if (buffer[i] > 1.0f) buffer[i] = 1.0f;
        if (buffer[i] < -1.0f) buffer[i] = -1.0f;
    }
}

// ============================================================================
// SMPTE Bars: continuous 1kHz at -20dBFS (amplitude ~0.1)
// ============================================================================

void generateSMPTEBarsAudio(float *buffer, uint32_t frameCount,
                             AudioGenContext *ctx)
{
    double frequency = 1000.0;
    float amplitude = 0.1f;  // -20 dBFS

    for (uint32_t i = 0; i < frameCount; i++) {
        buffer[i] = (float)sin(ctx->phase) * amplitude;
        ctx->phase += 2.0 * M_PI * frequency / ctx->sampleRate;

        // Keep phase in [0, 2*PI] to avoid precision loss
        if (ctx->phase >= 2.0 * M_PI) {
            ctx->phase -= 2.0 * M_PI;
        }
    }
}

// ============================================================================
// Grid Chart: silence
// ============================================================================

void generateGridChartAudio(float *buffer, uint32_t frameCount,
                             AudioGenContext *ctx)
{
    memset(buffer, 0, frameCount * sizeof(float));
}

// ============================================================================
// Countdown: beep at each second, 2-pop at t=2s
// ============================================================================

void generateCountdownAudio(float *buffer, uint32_t frameCount,
                             AudioGenContext *ctx)
{
    memset(buffer, 0, frameCount * sizeof(float));

    double startTime = ctx->streamTime;
    double endTime = startTime + (double)frameCount / ctx->sampleRate;

    // Countdown goes 10, 9, 8, ... 2, 1, 0
    // Beep at each second mark, louder at 2 (the "2-pop")
    int firstBeat = (int)floor(startTime);
    if (firstBeat < 0) firstBeat = 0;
    int lastBeat = (int)floor(endTime) + 1;

    for (int beat = firstBeat; beat <= lastBeat; beat++) {
        double beatTime = (double)beat;

        // Which countdown number is this?
        // Countdown is modulo 11 (10 down to 0, then repeats)
        int countdownNum = 10 - (beat % 11);

        double burstDurationMs;
        float amplitude;
        double frequency;

        if (countdownNum == 2) {
            // 2-pop: louder, shorter burst
            burstDurationMs = 33.3;  // Exactly 1 frame at 30fps
            amplitude = 0.9f;
            frequency = 1000.0;
        } else if (countdownNum == 0) {
            // Zero: silence
            continue;
        } else {
            // Regular beep
            burstDurationMs = 30.0;
            amplitude = 0.6f;
            frequency = 800.0;
        }

        double beatEnd = beatTime + burstDurationMs / 1000.0;
        if (beatEnd < startTime || beatTime >= endTime) continue;

        int sampleOffset = (int)((beatTime - startTime) * ctx->sampleRate);
        if (sampleOffset < 0) sampleOffset = 0;
        if ((uint32_t)sampleOffset >= frameCount) continue;

        toneBurst(buffer, (uint32_t)sampleOffset, frameCount,
                  frequency, burstDurationMs, ctx->sampleRate, amplitude, &ctx->phase);
    }

    // Clip
    for (uint32_t i = 0; i < frameCount; i++) {
        if (buffer[i] > 1.0f) buffer[i] = 1.0f;
        if (buffer[i] < -1.0f) buffer[i] = -1.0f;
    }
}

// ============================================================================
// Main dispatch
// ============================================================================

void generatePatternAudio(float *buffer, uint32_t frameCount,
                           AudioGenContext *ctx)
{
    switch (ctx->patternID) {
        case 0:  // kPattern_BouncingBall
            generateBouncingBallAudio(buffer, frameCount, ctx);
            break;
        case 1:  // kPattern_SMPTEBars
            generateSMPTEBarsAudio(buffer, frameCount, ctx);
            break;
        case 2:  // kPattern_GridChart
            generateGridChartAudio(buffer, frameCount, ctx);
            break;
        case 3:  // kPattern_Countdown
            generateCountdownAudio(buffer, frameCount, ctx);
            break;
        default:
            memset(buffer, 0, frameCount * sizeof(float));
            break;
    }
}
