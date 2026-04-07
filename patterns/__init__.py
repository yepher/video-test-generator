"""Test pattern registry and base class."""

from abc import ABC, abstractmethod
from dataclasses import dataclass
from typing import Dict, Type

import numpy as np
from PIL import Image


@dataclass
class PatternMetadata:
    name: str
    description: str
    default_fps: int = 30
    default_resolution: tuple = (1920, 1080)


class TestPattern(ABC):
    """Base class for all test patterns.

    Subclasses must implement:
      - generate_frame(t, frame_num) -> PIL.Image
      - generate_audio(duration, sample_rate) -> np.ndarray
      - metadata() -> PatternMetadata
    """

    def __init__(self, width: int, height: int, fps: int, duration: float):
        self.width = width
        self.height = height
        self.fps = fps
        self.duration = duration

    @abstractmethod
    def metadata(self) -> PatternMetadata:
        """Return pattern name and description."""

    @abstractmethod
    def generate_frame(self, t: float, frame_num: int) -> Image.Image:
        """Render a single frame at time t (seconds)."""

    @abstractmethod
    def generate_audio(self, duration: float, sample_rate: int = 48000) -> np.ndarray:
        """Generate the full audio track as a mono float32 array in [-1, 1]."""


# Pattern registry
_registry: Dict[str, Type[TestPattern]] = {}


def register_pattern(key: str, cls: Type[TestPattern]):
    _registry[key] = cls


def get_pattern(key: str) -> Type[TestPattern]:
    if key not in _registry:
        raise KeyError(f"Unknown pattern '{key}'. Available: {list(_registry.keys())}")
    return _registry[key]


def list_patterns() -> Dict[str, Type[TestPattern]]:
    return dict(_registry)


# Auto-import patterns so they self-register
from patterns import bouncing_ball  # noqa: E402, F401
from patterns import smpte_bars     # noqa: E402, F401
from patterns import grid_chart     # noqa: E402, F401
from patterns import countdown      # noqa: E402, F401
