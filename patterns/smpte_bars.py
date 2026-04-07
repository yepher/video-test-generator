"""SMPTE color bars test pattern.

Generates the standard SMPTE RP 219 color bar pattern used for
color calibration and monitor alignment. The pattern has three
horizontal sections:

  Top 67%:    Seven vertical bars (gray, yellow, cyan, green, magenta, red, blue)
  Middle 8%:  Reverse bars (blue, black, magenta, black, cyan, black, gray)
  Bottom 25%: PLUGE region (-I, white, +Q, black, sub-black, black, super-white, black)

Audio: 1 kHz reference tone at -20 dBFS (continuous).
"""

import numpy as np
from PIL import Image, ImageDraw, ImageFont

from patterns import TestPattern, PatternMetadata, register_pattern


# SMPTE bar colors (top section, left to right)
TOP_BARS = [
    (192, 192, 192),  # 75% Gray
    (192, 192, 0),    # Yellow
    (0, 192, 192),    # Cyan
    (0, 192, 0),      # Green
    (192, 0, 192),    # Magenta
    (192, 0, 0),      # Red
    (0, 0, 192),      # Blue
]

# Middle castellations (reverse order subset)
MID_BARS = [
    (0, 0, 192),      # Blue
    (19, 19, 19),     # Black
    (192, 0, 192),    # Magenta
    (19, 19, 19),     # Black
    (0, 192, 192),    # Cyan
    (19, 19, 19),     # Black
    (192, 192, 192),  # Gray
]

# Bottom PLUGE region colors
PLUGE_COLORS = {
    "neg_i": (0, 33, 76),        # -I
    "white": (192, 192, 192),    # 75% White
    "pos_q": (50, 0, 106),       # +Q
    "black": (19, 19, 19),       # Black (7.5 IRE)
    "sub_black": (0, 0, 0),      # Sub-black (0 IRE)
    "mid_black": (19, 19, 19),   # Black
    "super_white": (29, 29, 29), # Slightly above black (for PLUGE)
    "black2": (19, 19, 19),      # Black
}


class SMPTEBarsPattern(TestPattern):

    def __init__(self, width, height, fps, duration, **kwargs):
        super().__init__(width, height, fps, duration)
        self.tone_freq = kwargs.get("tone_freq", 1000.0)
        # Cache the static frame since it doesn't change
        self._cached_frame = None

    def metadata(self) -> PatternMetadata:
        return PatternMetadata(
            name="SMPTE Color Bars",
            description="Standard SMPTE RP 219 color bars for color calibration and monitor setup.",
            default_fps=30,
            default_resolution=(1920, 1080),
        )

    def generate_audio(self, duration: float, sample_rate: int = 48000) -> np.ndarray:
        """Continuous 1 kHz tone at -20 dBFS."""
        n_samples = int(duration * sample_rate)
        t = np.arange(n_samples, dtype=np.float32) / sample_rate
        amplitude = 10 ** (-20 / 20.0)  # -20 dBFS
        return (amplitude * np.sin(2.0 * np.pi * self.tone_freq * t)).astype(np.float32)

    def generate_frame(self, t: float, frame_num: int) -> Image.Image:
        if self._cached_frame is not None:
            return self._cached_frame.copy()

        W, H = self.width, self.height
        img = Image.new("RGB", (W, H), (0, 0, 0))
        draw = ImageDraw.Draw(img)

        top_h = int(H * 0.67)
        mid_h = int(H * 0.08)
        bot_h = H - top_h - mid_h

        bar_w = W / 7.0

        # --- Top section: 7 color bars ---
        for i, color in enumerate(TOP_BARS):
            x0 = int(i * bar_w)
            x1 = int((i + 1) * bar_w)
            draw.rectangle([(x0, 0), (x1, top_h)], fill=color)

        # --- Middle section: castellations ---
        for i, color in enumerate(MID_BARS):
            x0 = int(i * bar_w)
            x1 = int((i + 1) * bar_w)
            draw.rectangle([(x0, top_h), (x1, top_h + mid_h)], fill=color)

        # --- Bottom section: PLUGE ---
        # Layout: -I (1 bar width), White (1 bar), +Q (1 bar),
        #         Black (4 bars with sub-black/super-white inserts)
        pluge_y0 = top_h + mid_h
        pluge_y1 = H

        # First 3 bars: -I, White, +Q
        pluge_left = [
            PLUGE_COLORS["neg_i"],
            PLUGE_COLORS["white"],
            PLUGE_COLORS["pos_q"],
        ]
        for i, color in enumerate(pluge_left):
            x0 = int(i * bar_w)
            x1 = int((i + 1) * bar_w)
            draw.rectangle([(x0, pluge_y0), (x1, pluge_y1)], fill=color)

        # Remaining 4 bars: black with PLUGE inserts
        black_x0 = int(3 * bar_w)
        black_x1 = W
        draw.rectangle([(black_x0, pluge_y0), (black_x1, pluge_y1)], fill=PLUGE_COLORS["black"])

        # PLUGE inserts within the black region
        black_region_w = black_x1 - black_x0
        # Sub-black, black, super-white pattern in center
        insert_w = black_region_w / 7.0
        inserts = [
            (PLUGE_COLORS["sub_black"], 1),
            (PLUGE_COLORS["mid_black"], 2),
            (PLUGE_COLORS["super_white"], 3),
            (PLUGE_COLORS["black2"], 4),
        ]
        for color, idx in inserts:
            ix0 = black_x0 + int(idx * insert_w)
            ix1 = black_x0 + int((idx + 1) * insert_w)
            draw.rectangle([(ix0, pluge_y0), (ix1, pluge_y1)], fill=color)

        # Label
        try:
            font_size = max(14, int(H * 0.02))
            font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", font_size)
        except (OSError, IOError):
            font = ImageFont.load_default()

        label = "SMPTE Color Bars"
        bbox = draw.textbbox((0, 0), label, font=font)
        lw = bbox[2] - bbox[0]
        draw.text(((W - lw) // 2, 5), label, fill=(255, 255, 255), font=font)

        self._cached_frame = img
        return img.copy()


register_pattern("smpte_bars", SMPTEBarsPattern)
