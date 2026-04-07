"""Grid/resolution test chart pattern.

Generates a resolution and geometry test chart with:
  - Fine grid lines at regular intervals
  - Center crosshair with concentric circles
  - Corner and edge resolution wedges (diagonal lines)
  - Resolution text labels
  - Grayscale ramp along the bottom

Audio: silence (no audio needed for a static resolution chart).
"""

import math

import numpy as np
from PIL import Image, ImageDraw, ImageFont

from patterns import TestPattern, PatternMetadata, register_pattern


class GridChartPattern(TestPattern):

    def __init__(self, width, height, fps, duration, **kwargs):
        super().__init__(width, height, fps, duration)
        self._cached_frame = None

    def metadata(self) -> PatternMetadata:
        return PatternMetadata(
            name="Grid/Resolution Chart",
            description="Fine grid, circles, and wedges for checking resolution, geometry, and sharpness.",
            default_fps=30,
            default_resolution=(1920, 1080),
        )

    def generate_audio(self, duration: float, sample_rate: int = 48000) -> np.ndarray:
        return np.zeros(int(duration * sample_rate), dtype=np.float32)

    def generate_frame(self, t: float, frame_num: int) -> Image.Image:
        if self._cached_frame is not None:
            return self._cached_frame.copy()

        W, H = self.width, self.height
        img = Image.new("RGB", (W, H), (0, 0, 0))
        draw = ImageDraw.Draw(img)

        cx, cy = W // 2, H // 2
        grid_color = (80, 80, 80)
        fine_grid_color = (40, 40, 40)
        circle_color = (0, 180, 0)
        crosshair_color = (255, 255, 255)
        text_color = (200, 200, 200)
        wedge_color = (180, 180, 180)

        # --- Fine grid ---
        # Major grid every 10% of height
        major_step = max(1, H // 10)
        # Minor grid at half that
        minor_step = major_step // 2

        # Minor grid lines
        for x in range(0, W, minor_step):
            draw.line([(x, 0), (x, H)], fill=fine_grid_color, width=1)
        for y in range(0, H, minor_step):
            draw.line([(0, y), (W, y)], fill=fine_grid_color, width=1)

        # Major grid lines
        for x in range(0, W, major_step):
            draw.line([(x, 0), (x, H)], fill=grid_color, width=1)
        for y in range(0, H, major_step):
            draw.line([(0, y), (W, y)], fill=grid_color, width=1)

        # --- Concentric circles ---
        max_r = min(cx, cy)
        for frac in [0.2, 0.4, 0.6, 0.8, 1.0]:
            r = int(max_r * frac)
            draw.ellipse([(cx - r, cy - r), (cx + r, cy + r)], outline=circle_color, width=1)

        # --- Center crosshair ---
        cross_len = int(max_r * 0.15)
        draw.line([(cx - cross_len, cy), (cx + cross_len, cy)], fill=crosshair_color, width=2)
        draw.line([(cx, cy - cross_len), (cx, cy + cross_len)], fill=crosshair_color, width=2)

        # Small center circle
        cr = max(3, int(H * 0.005))
        draw.ellipse([(cx - cr, cy - cr), (cx + cr, cy + cr)], outline=crosshair_color, width=2)

        # --- Corner resolution wedges ---
        # Diagonal converging lines in each corner to test sharpness
        wedge_len = int(min(W, H) * 0.12)
        corners = [
            (0, 0, 1, 1),           # top-left
            (W, 0, -1, 1),          # top-right
            (0, H, 1, -1),          # bottom-left
            (W, H, -1, -1),         # bottom-right
        ]
        for ox, oy, dx, dy in corners:
            for angle_offset in range(-30, 31, 5):
                rad = math.radians(45 * (1 if dx == dy else -1) + angle_offset)
                ex = ox + int(dx * abs(math.cos(rad)) * wedge_len)
                ey = oy + int(dy * abs(math.sin(rad)) * wedge_len)
                draw.line([(ox, oy), (ex, ey)], fill=wedge_color, width=1)

        # --- Edge marks (safe area indicators) ---
        # 90% and 80% safe area outlines
        for pct, color in [(0.9, (60, 60, 60)), (0.8, (50, 50, 50))]:
            margin_x = int(W * (1 - pct) / 2)
            margin_y = int(H * (1 - pct) / 2)
            draw.rectangle(
                [(margin_x, margin_y), (W - margin_x, H - margin_y)],
                outline=color, width=1,
            )

        # --- Grayscale ramp along the bottom ---
        ramp_h = max(20, int(H * 0.03))
        ramp_y = H - ramp_h
        n_steps = 32
        step_w = W / n_steps
        for i in range(n_steps):
            val = int(255 * i / (n_steps - 1))
            x0 = int(i * step_w)
            x1 = int((i + 1) * step_w)
            draw.rectangle([(x0, ramp_y), (x1, H)], fill=(val, val, val))

        # --- Labels ---
        try:
            font_size = max(14, int(H * 0.025))
            font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", font_size)
        except (OSError, IOError):
            font = ImageFont.load_default()

        try:
            small_font_size = max(12, int(H * 0.018))
            small_font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", small_font_size)
        except (OSError, IOError):
            small_font = ImageFont.load_default()

        # Title
        title = "Resolution & Geometry Chart"
        bbox = draw.textbbox((0, 0), title, font=font)
        tw = bbox[2] - bbox[0]
        draw.text(((W - tw) // 2, 8), title, fill=text_color, font=font)

        # Resolution label
        res_text = f"{W} x {H}"
        bbox2 = draw.textbbox((0, 0), res_text, font=small_font)
        rw = bbox2[2] - bbox2[0]
        draw.text(((W - rw) // 2, 8 + font_size + 4), res_text, fill=text_color, font=small_font)

        # Grid spacing labels at edges
        draw.text((5, cy - small_font_size // 2), f"{major_step}px", fill=text_color, font=small_font)
        draw.text((cx + 5, 5 + font_size + small_font_size + 8), f"grid: {major_step}px", fill=text_color, font=small_font)

        self._cached_frame = img
        return img.copy()


register_pattern("grid_chart", GridChartPattern)
