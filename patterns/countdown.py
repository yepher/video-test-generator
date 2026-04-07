"""Countdown leader test pattern.

Classic film-style countdown from 10 to 0 with:
  - Large countdown number in center
  - Rotating sweep hand (clock-style) completing one revolution per second
  - Beep tone at each second mark
  - Flash frame at "2" (the traditional film leader pop)
  - Color changes per second for visual distinction

Audio: short beep at each whole second, longer "2-pop" beep at the 2-mark.
"""

import math

import numpy as np
from PIL import Image, ImageDraw, ImageFont

from patterns import TestPattern, PatternMetadata, register_pattern
from audio import place_tone_bursts


# Color cycle for each countdown number (background accent)
COUNTDOWN_COLORS = {
    10: (40, 40, 40),
    9: (0, 60, 0),
    8: (0, 0, 80),
    7: (60, 0, 60),
    6: (80, 40, 0),
    5: (0, 60, 60),
    4: (60, 60, 0),
    3: (80, 0, 0),
    2: (255, 255, 255),  # Flash frame
    1: (40, 40, 40),
    0: (0, 0, 0),
}


class CountdownPattern(TestPattern):

    def __init__(self, width, height, fps, duration, **kwargs):
        super().__init__(width, height, fps, duration)
        self.beep_freq = kwargs.get("beep_freq", 1000.0)
        self.pop_freq = kwargs.get("pop_freq", 1000.0)
        # Duration is forced to ~11 seconds (10 down to 0 + tail)
        # but we respect the user's duration setting

    def metadata(self) -> PatternMetadata:
        return PatternMetadata(
            name="Countdown Leader",
            description="Classic film-style countdown (10 to 0) with sweep hand and beeps for sync testing.",
            default_fps=30,
            default_resolution=(1920, 1080),
        )

    def generate_audio(self, duration: float, sample_rate: int = 48000) -> np.ndarray:
        # Beep at each whole second from 0 to duration
        # Longer beep at the "2" mark (classic 2-pop)
        from audio import tone_burst as make_burst

        total_samples = int(duration * sample_rate)
        audio = np.zeros(total_samples, dtype=np.float32)

        countdown_start = self._countdown_start()

        for sec in range(int(duration) + 1):
            t = float(sec)
            if t > duration:
                break

            # What countdown number is showing at this second?
            count = countdown_start - sec

            if count == 2:
                # 2-pop: longer, louder burst
                burst = make_burst(self.pop_freq, 80.0, sample_rate, 0.9)
            elif count >= 0:
                burst = make_burst(self.beep_freq, 30.0, sample_rate, 0.7)
            else:
                continue

            start = int(t * sample_rate)
            end = min(start + len(burst), total_samples)
            n = end - start
            if n > 0:
                audio[start:end] += burst[:n]

        np.clip(audio, -1.0, 1.0, out=audio)
        return audio

    def _countdown_start(self) -> int:
        """The number the countdown starts at."""
        return min(10, int(self.duration))

    def generate_frame(self, t: float, frame_num: int) -> Image.Image:
        W, H = self.width, self.height
        cx, cy = W // 2, H // 2

        countdown_start = self._countdown_start()
        current_second = int(t)
        count = countdown_start - current_second
        frac = t - current_second  # fraction within current second

        # Background color
        if count in COUNTDOWN_COLORS:
            bg = COUNTDOWN_COLORS[count]
        else:
            bg = (0, 0, 0)

        # Flash frame logic: at count=2, flash white for first 2 frames
        is_flash = (count == 2 and frac < 2.0 / self.fps)

        if is_flash:
            img = Image.new("RGB", (W, H), (255, 255, 255))
            draw = ImageDraw.Draw(img)
        else:
            img = Image.new("RGB", (W, H), (20, 20, 20))
            draw = ImageDraw.Draw(img)

        # Determine text/line colors based on background brightness
        if is_flash or count == 2:
            fg = (0, 0, 0)
            ring_color = (0, 0, 0)
            sweep_color = (80, 80, 80)
        else:
            fg = (255, 255, 255)
            ring_color = bg if bg != (0, 0, 0) and bg != (40, 40, 40) else (100, 100, 100)
            sweep_color = (200, 200, 200)

        # --- Outer ring ---
        ring_r = int(min(cx, cy) * 0.75)
        ring_w = max(4, int(H * 0.006))
        draw.ellipse(
            [(cx - ring_r, cy - ring_r), (cx + ring_r, cy + ring_r)],
            outline=ring_color, width=ring_w,
        )

        # --- Inner ring ---
        inner_r = int(ring_r * 0.85)
        draw.ellipse(
            [(cx - inner_r, cy - inner_r), (cx + inner_r, cy + inner_r)],
            outline=ring_color, width=max(2, ring_w // 2),
        )

        # --- Crosshairs ---
        draw.line([(cx - ring_r, cy), (cx + ring_r, cy)], fill=ring_color, width=max(1, ring_w // 3))
        draw.line([(cx, cy - ring_r), (cx, cy + ring_r)], fill=ring_color, width=max(1, ring_w // 3))

        # --- Sweep hand ---
        # Rotates 360 degrees per second, starting from 12 o'clock
        angle = -90 + frac * 360  # degrees, starting from top
        rad = math.radians(angle)
        hand_len = int(ring_r * 0.95)
        hx = cx + int(hand_len * math.cos(rad))
        hy = cy + int(hand_len * math.sin(rad))

        # Draw sweep as a filled pie wedge
        start_angle = -90
        end_angle = -90 + frac * 360
        if not is_flash:
            draw.pieslice(
                [(cx - inner_r, cy - inner_r), (cx + inner_r, cy + inner_r)],
                start=start_angle,
                end=end_angle,
                fill=(*ring_color[:3],) if ring_color != (100, 100, 100) else (60, 60, 60),
                outline=ring_color,
            )

        # Sweep hand line
        hand_w = max(2, int(H * 0.004))
        draw.line([(cx, cy), (hx, hy)], fill=sweep_color, width=hand_w)

        # --- Countdown number ---
        if count >= 0:
            num_text = str(count)
        else:
            num_text = ""

        if num_text:
            try:
                num_font_size = int(min(W, H) * 0.35)
                num_font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", num_font_size)
            except (OSError, IOError):
                num_font = ImageFont.load_default()

            bbox = draw.textbbox((0, 0), num_text, font=num_font)
            tw = bbox[2] - bbox[0]
            th = bbox[3] - bbox[1]
            draw.text((cx - tw // 2, cy - th // 2 - int(th * 0.1)), num_text, fill=fg, font=num_font)

        # --- Small labels ---
        try:
            small_size = max(12, int(H * 0.02))
            small_font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", small_size)
        except (OSError, IOError):
            small_font = ImageFont.load_default()

        # Frame info
        info = f"Frame {frame_num}  |  {W}x{H} @ {self.fps}fps"
        draw.text((10, H - small_size - 10), info, fill=(128, 128, 128), font=small_font)

        # Time
        time_text = f"{t:.2f}s"
        bbox2 = draw.textbbox((0, 0), time_text, font=small_font)
        draw.text((W - (bbox2[2] - bbox2[0]) - 10, H - small_size - 10), time_text, fill=(128, 128, 128), font=small_font)

        return img


register_pattern("countdown", CountdownPattern)
