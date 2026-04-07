#!/usr/bin/env python3
"""Generate test pattern videos with synchronized audio.

Usage:
    python generate.py --pattern bouncing_ball --duration 10 --fps 30 --output test.mp4
    python generate.py --pattern bouncing_ball --codec prores --output test.mov
    python generate.py --list
"""

import argparse
import sys

from patterns import get_pattern, list_patterns
from renderer import render_video, CODEC_PRESETS


def parse_resolution(s: str) -> tuple:
    """Parse 'WIDTHxHEIGHT' string."""
    parts = s.lower().split("x")
    if len(parts) != 2:
        raise argparse.ArgumentTypeError(f"Resolution must be WxH, got '{s}'")
    return int(parts[0]), int(parts[1])


def main():
    parser = argparse.ArgumentParser(
        description="Generate test pattern videos with synchronized audio.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  python generate.py --pattern bouncing_ball --duration 10 --output sync_test.mp4
  python generate.py --pattern bouncing_ball --fps 60 --resolution 3840x2160 --output 4k_test.mp4
  python generate.py --pattern bouncing_ball --codec prores --output test.mov
  python generate.py --list
        """,
    )

    parser.add_argument("--list", action="store_true", help="List available test patterns")
    parser.add_argument("--pattern", "-p", type=str, default="bouncing_ball",
                        help="Test pattern name (default: bouncing_ball)")
    parser.add_argument("--duration", "-d", type=float, default=10.0,
                        help="Video duration in seconds (default: 10)")
    parser.add_argument("--fps", type=int, default=30,
                        help="Frames per second (default: 30)")
    parser.add_argument("--resolution", "-r", type=parse_resolution, default="1920x1080",
                        help="Video resolution as WxH (default: 1920x1080)")
    parser.add_argument("--codec", "-c", type=str, default="h264",
                        choices=list(CODEC_PRESETS.keys()),
                        help="Video codec (default: h264)")
    parser.add_argument("--output", "-o", type=str, default="output.mp4",
                        help="Output file path (default: output.mp4)")
    parser.add_argument("--sample-rate", type=int, default=48000,
                        help="Audio sample rate (default: 48000)")
    parser.add_argument("--verbose", "-v", action="store_true",
                        help="Print progress info")
    parser.add_argument("--no-qr", action="store_true",
                        help="Disable QR code overlay on each frame")
    parser.add_argument("--no-timecode", action="store_true",
                        help="Disable SMPTE timecode track in container")
    parser.add_argument("--no-ltc", action="store_true",
                        help="Disable LTC (Linear Timecode) on right audio channel")
    parser.add_argument("--qr-position", type=str, default="bottom-right",
                        choices=["bottom-right", "bottom-left", "top-right", "top-left"],
                        help="QR code corner placement (default: bottom-right)")

    args = parser.parse_args()

    if args.list:
        patterns = list_patterns()
        if not patterns:
            print("No patterns registered.")
            return
        print("Available test patterns:")
        print()
        for key, cls in patterns.items():
            # Instantiate briefly to get metadata
            instance = cls(1, 1, 1, 1)
            meta = instance.metadata()
            print(f"  {key:20s}  {meta.description}")
        return

    # Create pattern instance
    width, height = args.resolution
    PatternClass = get_pattern(args.pattern)
    pattern = PatternClass(
        width=width,
        height=height,
        fps=args.fps,
        duration=args.duration,
    )

    enable_qr = not args.no_qr
    enable_timecode = not args.no_timecode
    enable_ltc = not args.no_ltc

    meta = pattern.metadata()
    print(f"Generating: {meta.name}")
    print(f"  Resolution: {width}x{height} @ {args.fps}fps")
    print(f"  Duration:   {args.duration}s")
    print(f"  Codec:      {args.codec}")
    print(f"  QR codes:   {'ON (' + args.qr_position + ')' if enable_qr else 'OFF'}")
    print(f"  Timecode:   {'ON' if enable_timecode else 'OFF'}")
    print(f"  LTC audio:  {'ON (right channel)' if enable_ltc else 'OFF'}")
    print(f"  Output:     {args.output}")
    print()

    render_video(
        pattern=pattern,
        output_path=args.output,
        codec=args.codec,
        sample_rate=args.sample_rate,
        verbose=args.verbose,
        enable_qr=enable_qr,
        enable_timecode=enable_timecode,
        enable_ltc=enable_ltc,
        qr_position=args.qr_position,
    )

    print(f"Done! Created {args.output}")


if __name__ == "__main__":
    main()
