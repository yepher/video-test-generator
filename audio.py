"""Audio generation utilities for test patterns."""

import numpy as np


def tone_burst(
    frequency: float = 1000.0,
    duration_ms: float = 30.0,
    sample_rate: int = 48000,
    amplitude: float = 0.8,
) -> np.ndarray:
    """Generate a short sine tone burst with a smooth envelope.

    Returns a mono float32 array in [-1, 1].
    """
    n_samples = int(sample_rate * duration_ms / 1000.0)
    t = np.arange(n_samples, dtype=np.float32) / sample_rate

    # Sine wave
    wave = np.sin(2.0 * np.pi * frequency * t).astype(np.float32)

    # Smooth Hann envelope to avoid clicks
    envelope = np.hanning(n_samples).astype(np.float32)

    return wave * envelope * amplitude


def place_tone_bursts(
    beat_times: list,
    duration: float,
    sample_rate: int = 48000,
    frequency: float = 1000.0,
    burst_duration_ms: float = 30.0,
    amplitude: float = 0.8,
) -> np.ndarray:
    """Place tone bursts at specified times into a silent audio track.

    Args:
        beat_times: list of times (seconds) where tone bursts should occur.
        duration: total audio duration in seconds.
        sample_rate: audio sample rate.
        frequency: tone frequency in Hz.
        burst_duration_ms: duration of each burst in ms.
        amplitude: peak amplitude [0, 1].

    Returns:
        Mono float32 audio array.
    """
    total_samples = int(duration * sample_rate)
    audio = np.zeros(total_samples, dtype=np.float32)
    burst = tone_burst(frequency, burst_duration_ms, sample_rate, amplitude)
    burst_len = len(burst)

    for t in beat_times:
        start = int(t * sample_rate)
        if start < 0:
            continue
        end = min(start + burst_len, total_samples)
        n = end - start
        if n > 0:
            audio[start:end] += burst[:n]

    # Clip to prevent overflow
    np.clip(audio, -1.0, 1.0, out=audio)
    return audio


def audio_to_wav_bytes(audio: np.ndarray, sample_rate: int = 48000) -> bytes:
    """Convert float32 audio array to 16-bit PCM WAV file bytes."""
    import struct
    import io

    # Convert to 16-bit PCM
    pcm = (audio * 32767).astype(np.int16)
    raw = pcm.tobytes()

    # Build WAV in memory
    buf = io.BytesIO()
    n_channels = 1
    sample_width = 2  # 16-bit
    data_size = len(raw)
    file_size = 36 + data_size

    # RIFF header
    buf.write(b"RIFF")
    buf.write(struct.pack("<I", file_size))
    buf.write(b"WAVE")

    # fmt chunk
    buf.write(b"fmt ")
    buf.write(struct.pack("<I", 16))  # chunk size
    buf.write(struct.pack("<H", 1))   # PCM format
    buf.write(struct.pack("<H", n_channels))
    buf.write(struct.pack("<I", sample_rate))
    buf.write(struct.pack("<I", sample_rate * n_channels * sample_width))  # byte rate
    buf.write(struct.pack("<H", n_channels * sample_width))  # block align
    buf.write(struct.pack("<H", sample_width * 8))  # bits per sample

    # data chunk
    buf.write(b"data")
    buf.write(struct.pack("<I", data_size))
    buf.write(raw)

    return buf.getvalue()
