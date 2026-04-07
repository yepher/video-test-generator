"""FFmpeg-based video renderer that combines frames + audio into a video file."""

import subprocess
import sys
import tempfile
import os

from PIL import Image
import numpy as np

from audio import audio_to_wav_bytes, generate_ltc
from qr_overlay import composite_qr


# Codec presets: maps codec name -> FFmpeg args
CODEC_PRESETS = {
    "h264": ["-c:v", "libx264", "-preset", "medium", "-crf", "18", "-pix_fmt", "yuv420p"],
    "h265": ["-c:v", "libx265", "-preset", "medium", "-crf", "20", "-pix_fmt", "yuv420p"],
    "prores": ["-c:v", "prores_ks", "-profile:v", "3", "-pix_fmt", "yuv422p10le"],
    "utvideo": ["-c:v", "utvideo", "-pix_fmt", "yuv422p"],
}


def find_ffmpeg() -> str:
    """Locate the ffmpeg binary."""
    # Check common Homebrew paths first
    for path in ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg"]:
        if os.path.isfile(path):
            return path
    # Fall back to PATH
    return "ffmpeg"


def _format_timecode(frame_num: int, fps: int) -> str:
    """Convert a frame number to SMPTE timecode HH:MM:SS:FF."""
    total_seconds = frame_num // fps
    ff = frame_num % fps
    ss = total_seconds % 60
    mm = (total_seconds // 60) % 60
    hh = total_seconds // 3600
    return f"{hh:02d}:{mm:02d}:{ss:02d}:{ff:02d}"


def render_video(
    pattern,
    output_path: str,
    codec: str = "h264",
    sample_rate: int = 48000,
    verbose: bool = False,
    enable_qr: bool = True,
    enable_timecode: bool = True,
    enable_ltc: bool = True,
    qr_position: str = "bottom-right",
):
    """Render a test pattern to a video file.

    Args:
        pattern: a TestPattern instance (already configured with w/h/fps/duration).
        output_path: path to output video file.
        codec: codec preset name (h264, h265, prores, utvideo).
        sample_rate: audio sample rate.
        verbose: print progress info.
        enable_qr: composite QR codes with timing data onto each frame.
        enable_timecode: write SMPTE timecode metadata into the container.
        enable_ltc: generate LTC (Linear Timecode) on right audio channel.
        qr_position: QR code corner placement.
    """
    ffmpeg = find_ffmpeg()
    width = pattern.width
    height = pattern.height
    fps = pattern.fps
    duration = pattern.duration
    total_frames = int(duration * fps)

    if codec not in CODEC_PRESETS:
        raise ValueError(f"Unknown codec '{codec}'. Available: {list(CODEC_PRESETS.keys())}")

    # Get pattern name for QR payload
    pattern_name = ""
    try:
        pattern_name = pattern.metadata().name
    except Exception:
        pass

    # Generate audio and write to temp WAV
    if verbose:
        print("Generating audio track...")
    audio_data = pattern.generate_audio(duration, sample_rate)

    # Generate LTC timecode audio for right channel
    ltc_audio = None
    if enable_ltc:
        if verbose:
            print("Generating LTC timecode audio (right channel)...")
        ltc_audio = generate_ltc(duration, fps, sample_rate)

    wav_bytes = audio_to_wav_bytes(audio_data, sample_rate, ltc_audio=ltc_audio)

    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tmp_wav:
        tmp_wav.write(wav_bytes)
        wav_path = tmp_wav.name

    try:
        # Build FFmpeg command
        codec_args = CODEC_PRESETS[codec]

        # SMPTE timecode: embed as a timecode metadata stream
        timecode_input_args = []
        timecode_output_args = []
        if enable_timecode:
            # Create a timecode data stream input and map it
            timecode_input_args = [
                "-f", "lavfi",
                "-i", f"testsrc=size=2x2:rate={fps},format=rgb24",
            ]
            timecode_output_args = [
                "-map", "0:v",       # video from raw frames
                "-map", "1:a",       # audio from WAV
                "-metadata:s:v:0", "timecode=00:00:00:00",
            ]
        else:
            timecode_output_args = [
                "-map", "0:v",
                "-map", "1:a",
            ]

        cmd = [
            ffmpeg,
            "-y",                          # overwrite output
            "-f", "rawvideo",              # input format: raw frames
            "-vcodec", "rawvideo",
            "-pix_fmt", "rgb24",
            "-s", f"{width}x{height}",
            "-r", str(fps),
            "-i", "-",                     # video from stdin
            "-i", wav_path,                # audio from file
            *timecode_output_args,
            *codec_args,
            "-c:a", "aac", "-b:a", "192k",  # audio codec
            "-shortest",
            output_path,
        ]

        if verbose:
            features = []
            if enable_timecode:
                features.append("SMPTE timecode")
            if enable_qr:
                features.append(f"QR codes ({qr_position})")
            if enable_ltc:
                features.append("LTC audio (right channel)")
            feat_str = ", ".join(features) if features else "none"
            print(f"Embedded data: {feat_str}")
            print(f"Running: {' '.join(cmd)}")
            print(f"Rendering {total_frames} frames at {width}x{height} @ {fps}fps...")

        stderr_mode = None if verbose else subprocess.DEVNULL
        proc = subprocess.Popen(
            cmd,
            stdin=subprocess.PIPE,
            stderr=stderr_mode,
        )

        # Feed frames
        for frame_num in range(total_frames):
            t = frame_num / fps
            img = pattern.generate_frame(t, frame_num)

            # Ensure correct size and mode
            if img.size != (width, height):
                img = img.resize((width, height))
            if img.mode != "RGB":
                img = img.convert("RGB")

            # Composite QR code with timing data
            if enable_qr:
                img = composite_qr(
                    frame=img,
                    frame_num=frame_num,
                    t=t,
                    fps=fps,
                    pattern_name=pattern_name,
                    position=qr_position,
                )

            proc.stdin.write(img.tobytes())

            if verbose and frame_num % fps == 0:
                elapsed = frame_num / fps
                tc = _format_timecode(frame_num, fps)
                print(f"  {elapsed:.0f}s / {duration:.0f}s ({frame_num}/{total_frames} frames)  TC: {tc}")

        proc.stdin.close()
        proc.wait()

        if proc.returncode != 0:
            print(f"FFmpeg exited with code {proc.returncode}", file=sys.stderr)
            sys.exit(1)

        if verbose:
            print(f"Done! Output: {output_path}")

    finally:
        os.unlink(wav_path)
