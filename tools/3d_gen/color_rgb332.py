"""RGB332 conversion and arithmetic shared by SketchBook 3D tools."""
from __future__ import annotations

from model import normalise_color


def hex_to_rgb332(color: str) -> int:
    color = normalise_color(color)
    red, green, blue = int(color[1:3], 16), int(color[3:5], 16), int(color[5:7], 16)
    return ((red >> 5) << 5) | ((green >> 5) << 2) | (blue >> 6)


def rgb332_to_hex(color: int) -> str:
    """Expand one RGB332 pixel to its exact RGB888 display representation."""
    color &= 0xFF
    red = (color >> 5) & 0x7
    green = (color >> 2) & 0x7
    blue = color & 0x3
    r8 = (red << 5) | (red << 2) | (red >> 1)
    g8 = (green << 5) | (green << 2) | (green >> 1)
    b8 = (blue << 6) | (blue << 4) | (blue << 2) | blue
    return f"#{r8:02X}{g8:02X}{b8:02X}"


def shade_hex_rgb332(
    color: str,
    intensity_q15: int,
    minimum_q15: int,
    maximum_q15: int = 32767,
) -> str:
    pixel = hex_to_rgb332(color)
    intensity = max(minimum_q15, min(maximum_q15, int(intensity_q15)))
    red = min(0x7, (((pixel >> 5) & 0x7) * intensity) >> 15)
    green = min(0x7, (((pixel >> 2) & 0x7) * intensity) >> 15)
    blue = min(0x3, ((pixel & 0x3) * intensity) >> 15)
    return rgb332_to_hex((red << 5) | (green << 2) | blue)
