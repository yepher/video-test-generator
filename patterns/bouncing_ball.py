"""Bouncing ball audio/video sync test pattern.

A ball sweeps back and forth across a horizontal timeline ruler.
Each time the ball crosses the center beat mark, a tone burst plays.
A pie-chart clock shows elapsed time within the current second.
"""

import math

import numpy as np
from PIL import Image, ImageDraw, ImageFont

from patterns import TestPattern, PatternMetadata, register_pattern
from audio import place_tone_bursts


class BouncingBallPattern(TestPattern):

    def __init__(self, width, height, fps, duration, **kwargs):
        super().__init__(width, height, fps, duration)
        self.tone_freq = kwargs.get("tone_freq", 1000.0)
        self.burst_ms = kwargs.get("burst_ms", 30.0)
        self.ball_radius = kwargs.get("ball_radius", None)  # auto-size if None
        self.bg_color = (0, 0, 0)
        self.fg_color = (255, 255, 255)
        self.accent_color = (0, 180, 0)  # green for pie slice
        self.ruler_color = (200, 200, 0)  # yellow ruler ticks
        self.title_color = (220, 160, 0)  # orange/gold title

        # Beat period: ball sweeps left-to-right in 1 second, then back in 1 second
        # Beat at each end = every 1 second
        self.beat_period = 1.0

    def metadata(self) -> PatternMetadata:
        return PatternMetadata(
            name="Bouncing Ball A/V Sync",
            description="Ball sweeps across a timeline ruler; tone burst at each beat for A/V sync testing.",
            default_fps=30,
            default_resolution=(1920, 1080),
        )

    def _get_ball_radius(self) -> int:
        if self.ball_radius:
            return self.ball_radius
        return max(10, int(min(self.width, self.height) * 0.03))

    def _get_beat_times(self) -> list:
        """Return list of times (seconds) when the ball hits a beat mark."""
        times = []
        t = 0.0
        while t <= self.duration + 0.001:
            times.append(t)
            t += self.beat_period
        return times

    def generate_audio(self, duration: float, sample_rate: int = 48000) -> np.ndarray:
        beat_times = self._get_beat_times()
        return place_tone_bursts(
            beat_times=beat_times,
            duration=duration,
            sample_rate=sample_rate,
            frequency=self.tone_freq,
            burst_duration_ms=self.burst_ms,
        )

    def generate_frame(self, t: float, frame_num: int) -> Image.Image:
        W, H = self.width, self.height
        img = Image.new("RGB", (W, H), self.bg_color)
        draw = ImageDraw.Draw(img)

        # Layout constants
        margin_x = int(W * 0.05)
        ruler_y = int(H * 0.85)       # ruler vertical center
        ruler_h = int(H * 0.04)       # half-height of ruler area
        ball_y = int(H * 0.68)        # ball vertical center
        ball_r = self._get_ball_radius()

        # Ruler spans from margin_x to W - margin_x
        ruler_left = margin_x
        ruler_right = W - margin_x
        ruler_width = ruler_right - ruler_left
        ruler_center_x = (ruler_left + ruler_right) // 2

        # --- Draw ruler ---
        # Baseline
        draw.line([(ruler_left, ruler_y), (ruler_right, ruler_y)], fill=self.fg_color, width=2)

        # Tick marks: 20 divisions (-1.0 to +1.0, step 0.1)
        for i in range(21):
            frac = i / 20.0  # 0 to 1
            x = ruler_left + int(frac * ruler_width)
            val = -1.0 + i * 0.1

            # Major ticks at -1, 0, +1
            if abs(val) < 0.001 or abs(abs(val) - 1.0) < 0.001:
                tick_h = ruler_h
                tick_w = 3
                color = self.fg_color
            else:
                tick_h = int(ruler_h * 0.6)
                tick_w = 1
                color = self.ruler_color

            draw.line([(x, ruler_y - tick_h), (x, ruler_y + tick_h)], fill=color, width=tick_w)

        # Ruler labels
        try:
            font_size = max(14, int(H * 0.03))
            font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", font_size)
        except (OSError, IOError):
            font = ImageFont.load_default()

        label_y = ruler_y + ruler_h + 5
        # "-1" label
        draw.text((ruler_left, label_y), "-1", fill=self.ruler_color, font=font)
        # "0" label
        draw.text((ruler_center_x - 5, label_y), "0", fill=self.ruler_color, font=font)
        # "1" label
        draw.text((ruler_right - 15, label_y), "1", fill=self.ruler_color, font=font)

        # "10ths of a second" labels
        try:
            small_font_size = max(12, int(H * 0.025))
            small_font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", small_font_size)
        except (OSError, IOError):
            small_font = ImageFont.load_default()

        quarter_x = (ruler_left + ruler_center_x) // 2
        three_quarter_x = (ruler_center_x + ruler_right) // 2
        draw.text((quarter_x - 60, label_y), "10ths of a second", fill=self.ruler_color, font=small_font)
        draw.text((three_quarter_x - 60, label_y), "10ths of a second", fill=self.ruler_color, font=small_font)

        # --- Ball position ---
        # Ball oscillates: position within current beat cycle
        # Goes from center -> right -> center -> left -> center over 2 seconds
        cycle_t = t % 2.0  # 0 to 2 seconds
        if cycle_t < 1.0:
            # First half: center to right and back (really: sweep right)
            # Use sine for smooth motion: 0->1->0 over 1 second
            frac = math.sin(cycle_t * math.pi)
            ball_x = ruler_center_x + int(frac * (ruler_width // 2))
        else:
            # Second half: center to left and back
            frac = math.sin((cycle_t - 1.0) * math.pi)
            ball_x = ruler_center_x - int(frac * (ruler_width // 2))

        # Draw vertical reference line from ball down to ruler
        line_top = ball_y + ball_r
        line_bottom = ruler_y
        draw.line([(ball_x, line_top), (ball_x, line_bottom)], fill=self.fg_color, width=2)

        # Draw ball
        draw.ellipse(
            [(ball_x - ball_r, ball_y - ball_r), (ball_x + ball_r, ball_y + ball_r)],
            fill=self.fg_color,
        )

        # --- Pie chart clock (upper left) ---
        pie_cx = int(W * 0.2)
        pie_cy = int(H * 0.3)
        pie_r = int(min(W, H) * 0.18)

        # White circle background
        draw.ellipse(
            [(pie_cx - pie_r, pie_cy - pie_r), (pie_cx + pie_r, pie_cy + pie_r)],
            fill=self.fg_color,
            outline=self.bg_color,
            width=2,
        )

        # Green pie slice showing fraction of current second elapsed
        frac_second = t % 1.0
        if frac_second > 0.001:
            start_angle = -90  # 12 o'clock
            end_angle = start_angle + frac_second * 360
            draw.pieslice(
                [(pie_cx - pie_r, pie_cy - pie_r), (pie_cx + pie_r, pie_cy + pie_r)],
                start=start_angle,
                end=end_angle,
                fill=self.accent_color,
                outline=self.bg_color,
            )

        # --- Title text ---
        try:
            title_font_size = max(16, int(H * 0.04))
            title_font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", title_font_size)
        except (OSError, IOError):
            title_font = ImageFont.load_default()

        title_text = "Audio/Video Sync Test"
        bbox = draw.textbbox((0, 0), title_text, font=title_font)
        tw = bbox[2] - bbox[0]
        title_x = (W - tw) // 2
        title_y = int(H * 0.05)
        draw.text((title_x, title_y), title_text, fill=self.title_color, font=title_font)

        # Time counter
        time_text = f"Time: {t:.2f}s"
        time_y = title_y + title_font_size + 10
        bbox2 = draw.textbbox((0, 0), time_text, font=small_font)
        tw2 = bbox2[2] - bbox2[0]
        draw.text(((W - tw2) // 2, time_y), time_text, fill=self.title_color, font=small_font)

        # Frame counter (bottom-left corner)
        frame_text = f"Frame: {frame_num}  FPS: {self.fps}"
        draw.text((margin_x, int(H * 0.02)), frame_text, fill=(128, 128, 128), font=small_font)

        return img


register_pattern("bouncing_ball", BouncingBallPattern)
