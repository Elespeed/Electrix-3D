#!/usr/bin/env python3
"""Simple live PPM frame viewer for simulator frame_output directories."""

from __future__ import annotations

import argparse
import base64
import re
import sys
import tempfile
import time
from pathlib import Path
from tkinter import BOTH, BOTTOM, NW, TOP, Canvas, Label, Tk, PhotoImage


FRAME_RE = re.compile(r"_frame_(\d+)\.ppm$", re.IGNORECASE)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dir", required=True, help="Directory containing *.ppm frames")
    parser.add_argument("--fps", type=float, default=12.0, help="Playback refresh rate")
    parser.add_argument(
        "--mode",
        choices=["loop", "latest"],
        default="loop",
        help="loop plays all frames repeatedly; latest always shows newest frame",
    )
    parser.add_argument("--title", default="Virtual DVI Frame Viewer")
    parser.add_argument("--glob", default="*.ppm", help="Frame file glob")
    parser.add_argument("--scan-ms", type=int, default=250)
    parser.add_argument("--stable-ms", type=int, default=200)
    parser.add_argument("--max-scale", type=float, default=2.0)
    return parser.parse_args()


def frame_sort_key(path: Path) -> tuple[int, str]:
    match = FRAME_RE.search(path.name)
    if match:
        return int(match.group(1)), path.name
    return 1_000_000_000, path.name


def ppm_tokens(data: bytes):
    token = bytearray()
    in_comment = False
    for value in data:
        if in_comment:
            if value in (10, 13):
                in_comment = False
            continue
        if value == 35:
            in_comment = True
            continue
        if value <= 32:
            if token:
                yield bytes(token)
                token.clear()
            continue
        token.append(value)
    if token:
        yield bytes(token)


def p3_to_p6(src: Path, dst: Path) -> None:
    data = src.read_bytes()
    tokens = ppm_tokens(data)
    magic = next(tokens, b"")
    if magic != b"P3":
        raise ValueError(f"unsupported PPM magic: {magic!r}")
    width = int(next(tokens))
    height = int(next(tokens))
    maxval = int(next(tokens))
    if maxval <= 0 or maxval > 255:
        raise ValueError(f"unsupported PPM maxval: {maxval}")

    pixel_count = width * height * 3
    pixels = bytearray(pixel_count)
    for idx in range(pixel_count):
        pixels[idx] = int(next(tokens))

    dst.write_bytes(f"P6\n{width} {height}\n255\n".encode("ascii") + bytes(pixels))


class FrameViewer:
    def __init__(self, args: argparse.Namespace) -> None:
        self.args = args
        self.frame_dir = Path(args.dir).resolve()
        self.frames: list[Path] = []
        self.frame_index = 0
        self.current_photo: PhotoImage | None = None
        self.temp_dir = Path(tempfile.mkdtemp(prefix="frame_viewer_"))
        self.converted: dict[Path, tuple[float, int, Path]] = {}
        self.paused = False
        self.last_scan = 0.0
        self.last_error = ""

        self.root = Tk()
        self.root.title(args.title)
        self.root.configure(bg="#111111")
        self.canvas = Canvas(self.root, bg="#111111", highlightthickness=0)
        self.canvas.pack(side=TOP, fill=BOTH, expand=True)
        self.status = Label(
            self.root,
            text="waiting for frames...",
            anchor="w",
            bg="#202020",
            fg="#eeeeee",
            padx=8,
            pady=4,
        )
        self.status.pack(side=BOTTOM, fill="x")
        self.root.bind("<space>", self.toggle_pause)
        self.root.bind("r", self.reset_loop)
        self.root.protocol("WM_DELETE_WINDOW", self.close)

    def toggle_pause(self, _event=None) -> None:
        self.paused = not self.paused

    def reset_loop(self, _event=None) -> None:
        self.frame_index = 0

    def close(self) -> None:
        self.root.destroy()

    def stable_frames(self) -> list[Path]:
        now = time.time()
        if now - self.last_scan < self.args.scan_ms / 1000.0:
            return self.frames
        self.last_scan = now
        if not self.frame_dir.exists():
            return []

        stable: list[Path] = []
        min_age = self.args.stable_ms / 1000.0
        for path in self.frame_dir.glob(self.args.glob):
            try:
                stat = path.stat()
            except OSError:
                continue
            if stat.st_size <= 0:
                continue
            if now - stat.st_mtime < min_age:
                continue
            stable.append(path)

        stable.sort(key=frame_sort_key)
        self.frames = stable
        if self.frame_index >= len(self.frames):
            self.frame_index = 0
        return self.frames

    def image_path_for(self, path: Path) -> Path:
        stat = path.stat()
        cached = self.converted.get(path)
        if cached and cached[0] == stat.st_mtime and cached[1] == stat.st_size:
            return cached[2]

        header = path.read_bytes()[:2]
        if header == b"P6":
            self.converted[path] = (stat.st_mtime, stat.st_size, path)
            return path

        out = self.temp_dir / f"{path.stem}_{int(stat.st_mtime_ns)}.p6.ppm"
        p3_to_p6(path, out)
        self.converted[path] = (stat.st_mtime, stat.st_size, out)
        return out

    def load_photo(self, path: Path) -> PhotoImage:
        image_path = self.image_path_for(path)
        try:
            return PhotoImage(file=str(image_path))
        except Exception:
            data = base64.b64encode(image_path.read_bytes()).decode("ascii")
            return PhotoImage(data=data, format="PPM")

    def draw_frame(self, path: Path) -> None:
        photo = self.load_photo(path)
        self.current_photo = photo
        self.canvas.delete("all")
        self.canvas.config(width=photo.width(), height=photo.height())
        self.canvas.create_image(0, 0, anchor=NW, image=photo)
        self.status.config(
            text=(
                f"{self.args.mode} | {len(self.frames)} frame(s) | "
                f"{path.name} | {photo.width()}x{photo.height()}"
            )
        )

    def tick(self) -> None:
        frames = self.stable_frames()
        if frames and not self.paused:
            try:
                if self.args.mode == "latest":
                    self.frame_index = len(frames) - 1
                path = frames[self.frame_index]
                self.draw_frame(path)
                if self.args.mode == "loop":
                    self.frame_index = (self.frame_index + 1) % len(frames)
            except Exception as exc:
                self.last_error = str(exc)
                self.status.config(text=f"viewer error: {self.last_error}")
        elif not frames:
            self.status.config(text=f"waiting for frames in {self.frame_dir}")

        delay_ms = max(1, int(1000.0 / max(self.args.fps, 0.1)))
        self.root.after(delay_ms, self.tick)

    def run(self) -> None:
        self.tick()
        self.root.mainloop()


def main() -> int:
    args = parse_args()
    try:
        FrameViewer(args).run()
    except KeyboardInterrupt:
        return 130
    return 0


if __name__ == "__main__":
    sys.exit(main())
