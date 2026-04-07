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


def generate_ltc(
    duration: float,
    fps: int,
    sample_rate: int = 48000,
    amplitude: float = 0.5,
) -> np.ndarray:
    """Generate an LTC (Linear Timecode / SMPTE timecode) audio signal.

    LTC encodes SMPTE timecode (HH:MM:SS:FF) as a bi-phase modulated audio
    signal. Each frame is encoded as 80 bits, transmitted using a Manchester-
    like biphase mark code where:
      - A '0' bit has one transition (at the start of the bit cell)
      - A '1' bit has two transitions (start and middle of the bit cell)

    Args:
        duration: total duration in seconds.
        fps: video frame rate (must be 24, 25, or 30).
        sample_rate: audio sample rate.
        amplitude: signal amplitude [0, 1].

    Returns:
        Mono float32 audio array containing LTC signal.
    """
    total_samples = int(duration * sample_rate)
    audio = np.zeros(total_samples, dtype=np.float32)

    total_frames = int(duration * fps)
    samples_per_frame = sample_rate / fps
    samples_per_bit = samples_per_frame / 80  # 80 bits per LTC frame

    for frame_idx in range(total_frames):
        # Calculate timecode for this frame
        total_secs = frame_idx // fps
        ff = frame_idx % fps
        ss = total_secs % 60
        mm = (total_secs // 60) % 60
        hh = (total_secs // 3600) % 24

        # Build the 80-bit LTC word
        bits = _build_ltc_word(hh, mm, ss, ff)

        # Encode each bit using biphase mark code
        frame_start_sample = int(frame_idx * samples_per_frame)

        current_polarity = 1.0
        for bit_idx, bit_val in enumerate(bits):
            bit_start = frame_start_sample + int(bit_idx * samples_per_bit)
            bit_mid = frame_start_sample + int((bit_idx + 0.5) * samples_per_bit)
            bit_end = frame_start_sample + int((bit_idx + 1) * samples_per_bit)

            # Clamp to array bounds
            bit_start = min(bit_start, total_samples)
            bit_mid = min(bit_mid, total_samples)
            bit_end = min(bit_end, total_samples)

            if bit_val == 0:
                # Transition at start only: first half one polarity, stays same
                current_polarity = -current_polarity
                audio[bit_start:bit_end] = current_polarity * amplitude
            else:
                # Transition at start AND middle
                current_polarity = -current_polarity
                audio[bit_start:bit_mid] = current_polarity * amplitude
                current_polarity = -current_polarity
                audio[bit_mid:bit_end] = current_polarity * amplitude

    return audio


def _build_ltc_word(hh: int, mm: int, ss: int, ff: int) -> list:
    """Build an 80-bit LTC word for the given timecode.

    LTC bit layout (80 bits):
      0-3:   Frame units (BCD)
      4-7:   User bits field 1
      8-9:   Frame tens (BCD, 2 bits)
      10:    Drop frame flag (0 for non-drop)
      11:    Color frame flag (0)
      12-15: User bits field 2
      16-19: Seconds units (BCD)
      20-23: User bits field 3
      24-26: Seconds tens (BCD, 3 bits)
      27:    Biphase correction bit (parity)
      28-31: User bits field 4
      32-35: Minutes units (BCD)
      36-39: User bits field 5
      40-42: Minutes tens (BCD, 3 bits)
      43:    Binary group flag bit
      44-47: User bits field 6
      48-51: Hours units (BCD)
      52-55: User bits field 7
      56-57: Hours tens (BCD, 2 bits)
      58:    Binary group flag bit
      59:    Polarity correction bit
      60-63: User bits field 8
      64-79: Sync word (0011 1111 1111 1101)
    """
    bits = [0] * 80

    # Frame units (bits 0-3)
    fu = ff % 10
    bits[0] = (fu >> 0) & 1
    bits[1] = (fu >> 1) & 1
    bits[2] = (fu >> 2) & 1
    bits[3] = (fu >> 3) & 1

    # User bits 1 (bits 4-7): zero
    # Frame tens (bits 8-9)
    ft = ff // 10
    bits[8] = (ft >> 0) & 1
    bits[9] = (ft >> 1) & 1

    # Drop frame (bit 10): 0
    # Color frame (bit 11): 0
    # User bits 2 (bits 12-15): zero

    # Seconds units (bits 16-19)
    su = ss % 10
    bits[16] = (su >> 0) & 1
    bits[17] = (su >> 1) & 1
    bits[18] = (su >> 2) & 1
    bits[19] = (su >> 3) & 1

    # User bits 3 (bits 20-23): zero
    # Seconds tens (bits 24-26)
    st = ss // 10
    bits[24] = (st >> 0) & 1
    bits[25] = (st >> 1) & 1
    bits[26] = (st >> 2) & 1

    # Biphase correction (bit 27): compute later
    # User bits 4 (bits 28-31): zero

    # Minutes units (bits 32-35)
    mu = mm % 10
    bits[32] = (mu >> 0) & 1
    bits[33] = (mu >> 1) & 1
    bits[34] = (mu >> 2) & 1
    bits[35] = (mu >> 3) & 1

    # User bits 5 (bits 36-39): zero
    # Minutes tens (bits 40-42)
    mt = mm // 10
    bits[40] = (mt >> 0) & 1
    bits[41] = (mt >> 1) & 1
    bits[42] = (mt >> 2) & 1

    # Binary group flag (bit 43): 0
    # User bits 6 (bits 44-47): zero

    # Hours units (bits 48-51)
    hu = hh % 10
    bits[48] = (hu >> 0) & 1
    bits[49] = (hu >> 1) & 1
    bits[50] = (hu >> 2) & 1
    bits[51] = (hu >> 3) & 1

    # User bits 7 (bits 52-55): zero
    # Hours tens (bits 56-57)
    ht = hh // 10
    bits[56] = (ht >> 0) & 1
    bits[57] = (ht >> 1) & 1

    # Binary group flag (bit 58): 0

    # Polarity correction (bit 59): set so total '1' count is even
    ones_count = sum(bits[0:59])
    bits[59] = ones_count % 2  # make total even

    # User bits 8 (bits 60-63): zero

    # Sync word (bits 64-79): 0011 1111 1111 1101
    sync = [0, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 1]
    bits[64:80] = sync

    return bits


def audio_to_wav_bytes(
    audio: np.ndarray,
    sample_rate: int = 48000,
    ltc_audio: np.ndarray = None,
) -> bytes:
    """Convert float32 audio array(s) to 16-bit PCM WAV file bytes.

    Args:
        audio: mono float32 audio array (pattern audio / channel 1).
        sample_rate: audio sample rate.
        ltc_audio: optional mono float32 LTC array (channel 2).
                   If provided, output is stereo with audio on left
                   and LTC on right.

    Returns:
        WAV file as bytes.
    """
    import struct
    import io

    if ltc_audio is not None:
        # Stereo: pattern audio (L) + LTC (R)
        # Ensure same length
        max_len = max(len(audio), len(ltc_audio))
        left = np.zeros(max_len, dtype=np.float32)
        right = np.zeros(max_len, dtype=np.float32)
        left[:len(audio)] = audio
        right[:len(ltc_audio)] = ltc_audio

        # Interleave L/R samples
        pcm_left = (left * 32767).astype(np.int16)
        pcm_right = (right * 32767).astype(np.int16)
        interleaved = np.empty(max_len * 2, dtype=np.int16)
        interleaved[0::2] = pcm_left
        interleaved[1::2] = pcm_right
        raw = interleaved.tobytes()
        n_channels = 2
    else:
        # Mono
        pcm = (audio * 32767).astype(np.int16)
        raw = pcm.tobytes()
        n_channels = 1

    # Build WAV in memory
    buf = io.BytesIO()
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
