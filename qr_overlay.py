"""QR code overlay for embedding machine-readable timing data in video frames.

Each frame gets a small QR code in the bottom-right corner encoding a JSON
payload with frame number, timestamp, FPS, resolution, and pattern name.
This data survives any pipeline — transcode, capture, re-encode, even
pointing a camera at a screen.
"""

import json
import qrcode
from PIL import Image


# Pre-configure QR generator for small, fast codes
_qr_factory = qrcode.QRCode(
    version=None,  # auto-size
    error_correction=qrcode.constants.ERROR_CORRECT_M,
    box_size=1,    # 1 pixel per module, we'll resize after
    border=1,
)


def make_qr_overlay(
    frame_num: int,
    t: float,
    fps: int,
    width: int,
    height: int,
    pattern_name: str = "",
    qr_size: int = None,
) -> Image.Image:
    """Generate a small QR code image encoding frame timing data.

    Args:
        frame_num: current frame number.
        t: current time in seconds.
        fps: frames per second.
        width: video width.
        height: video height.
        pattern_name: name of the test pattern.
        qr_size: target QR code size in pixels (default: ~8% of frame height).

    Returns:
        RGBA PIL Image of the QR code with white background.
    """
    if qr_size is None:
        qr_size = max(60, int(min(width, height) * 0.08))

    # Build compact payload
    payload = {
        "f": frame_num,
        "t": round(t, 4),
        "fps": fps,
        "res": f"{width}x{height}",
    }
    if pattern_name:
        payload["pat"] = pattern_name

    data = json.dumps(payload, separators=(",", ":"))

    # Generate QR code
    _qr_factory.clear()
    _qr_factory.add_data(data)
    _qr_factory.make(fit=True)
    qr_img = _qr_factory.make_image(fill_color="black", back_color="white")
    qr_img = qr_img.convert("RGB")

    # Resize to target size (nearest neighbor to keep sharp pixels)
    qr_img = qr_img.resize((qr_size, qr_size), Image.NEAREST)

    return qr_img


def composite_qr(
    frame: Image.Image,
    frame_num: int,
    t: float,
    fps: int,
    pattern_name: str = "",
    position: str = "bottom-right",
    margin: int = None,
    qr_size: int = None,
) -> Image.Image:
    """Composite a QR code onto a video frame.

    Args:
        frame: the video frame (RGB PIL Image).
        frame_num: current frame number.
        t: current time in seconds.
        fps: frames per second.
        pattern_name: name of the test pattern.
        position: corner placement — "bottom-right", "bottom-left",
                  "top-right", or "top-left".
        margin: pixel margin from edge (default: 1% of frame height).
        qr_size: QR code size in pixels (default: ~8% of frame height).

    Returns:
        The frame with QR code composited.
    """
    W, H = frame.size

    if margin is None:
        margin = max(4, int(H * 0.01))

    qr_img = make_qr_overlay(
        frame_num=frame_num,
        t=t,
        fps=fps,
        width=W,
        height=H,
        pattern_name=pattern_name,
        qr_size=qr_size,
    )

    qw, qh = qr_img.size

    if position == "bottom-right":
        x = W - qw - margin
        y = H - qh - margin
    elif position == "bottom-left":
        x = margin
        y = H - qh - margin
    elif position == "top-right":
        x = W - qw - margin
        y = margin
    elif position == "top-left":
        x = margin
        y = margin
    else:
        x = W - qw - margin
        y = H - qh - margin

    frame.paste(qr_img, (x, y))
    return frame
