"""Render a synthetic feature GIF; no screenshots or account data are read."""

from __future__ import annotations

import argparse
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

WIDTH, HEIGHT = 1280, 820
FPS, SECONDS = 10, 10
BACKGROUND = "#F4F7FC"
INK = "#18263E"
MUTED = "#607087"
BLUE = "#2865D9"
PURPLE = "#8054CF"
ROOT = Path(__file__).resolve().parents[1]


def find_font(requested: str | None) -> Path:
    candidates = [Path(requested)] if requested else [
        Path("/System/Library/Fonts/Supplemental/Arial Unicode.ttf"),
        Path("C:/Windows/Fonts/msyh.ttc"),
        Path("/usr/share/fonts/opentype/noto/NotoSansCJK-Regular.ttc"),
        Path("/usr/share/fonts/noto-cjk/NotoSansCJK-Regular.ttc"),
    ]
    for candidate in candidates:
        if candidate.is_file():
            return candidate
    raise SystemExit("Pass --font with a Chinese-capable TTF/OTF/TTC font.")


def smooth(value: float) -> float:
    value = max(0.0, min(1.0, value))
    return value * value * (3.0 - 2.0 * value)


def frame_at(t: float, fonts: dict[int, ImageFont.FreeTypeFont]) -> Image.Image:
    image = Image.new("RGB", (WIDTH, HEIGHT), BACKGROUND)
    draw = ImageDraw.Draw(image)

    def text(x: float, y: float, value: str, size: int = 22, color: str = INK) -> None:
        draw.text((round(x), round(y)), value, font=fonts[size], fill=color)

    def box(bounds: tuple[float, float, float, float], fill: str, radius: int = 16,
            outline: str | None = None, width: int = 1) -> None:
        draw.rounded_rectangle(tuple(round(v) for v in bounds), radius, fill,
                               outline=outline, width=width)

    windows_mode = 2.6 <= t < 6.8
    music_press = 1.8 <= t < 2.6
    mail_press = 6.0 <= t < 6.8
    switching = music_press or mail_press
    accent = BLUE if windows_mode or music_press else PURPLE

    text(64, 30, "一套键鼠，两种工作模式", 40)
    text(66, 92, "Deskflow + DDC/CI  ·  Windows ↔ Mac", 22, MUTED)
    box((1044, 44, 1216, 82), "#E7ECF5", 19)
    text(1067, 49, "功能示意动画", 18, MUTED)

    if music_press:
        status = "按下音乐键：启用右屏扩展 → 切 DP → 键鼠回到 Windows"
    elif mail_press:
        status = "按下邮件键：切 HDMI → Windows 仅左屏 → 键鼠交给 Mac"
    elif windows_mode:
        status = "Windows 双屏：窗口可拖到右屏，键鼠留在 Windows"
    else:
        status = "日常双主机：左侧 Windows，右侧 Mac，共用一套键鼠"
    box((64, 142, 1216, 188), "#FFFFFF", 14)
    draw.ellipse((82, 158, 94, 170), fill=accent)
    text(108, 150, status, 22)

    screens: list[tuple[int, int, int, int]] = []
    for index, x in enumerate((64, 668)):
        box((x + 2, 226, x + 550, 516), "#DCE3ED", 20)
        box((x, 218, x + 548, 508), INK, 18)
        bounds = (x + 10, 228, x + 538, 490)
        screens.append(bounds)
        is_mac = index == 1 and not windows_mode
        screen_color = "#EFE8FB" if is_mac else "#E6F0FF"
        box(bounds, screen_color, 10)
        if is_mac:
            draw.ellipse((x + 295, 228, x + 530, 459), fill="#DFD0F6")
            draw.ellipse((x + 325, 278, x + 495, 448), fill="#CEB6F0")
            text(x + 34, 246, "macOS", 22, PURPLE)
            text(x + 34, 278, "Mac 工作区", 18, MUTED)
            box((x + 130, 325, x + 432, 451), "#FFFFFF", 12)
            text(x + 151, 339, "Mac 应用", 18)
            for row, length in enumerate((222, 176, 198)):
                box((x + 151, 379 + row * 17, x + 151 + length, 384 + row * 17), "#DDD5EB", 2)
        else:
            text(x + 34, 246, "Windows", 22, BLUE)
            text(x + 34, 278, "主屏" if index == 0 else "扩展工作区", 18, MUTED)
            for dx, dy in ((0, 0), (27, 0), (0, 27), (27, 27)):
                draw.rectangle((x + 40 + dx, 340 + dy, x + 62 + dx, 362 + dy), fill="#BDD4FA")
        draw.rectangle((x + 10, 466, x + 538, 490), fill="#FFFFFF")
        for dot in range(4):
            box((x + 230 + dot * 26, 473, x + 242 + dot * 26, 484),
                "#D8C7EE" if is_mac else "#BED2F3", 3)
        draw.ellipse((x + 271, 497, x + 277, 503), fill="#B9C7DC")
        draw.polygon(((x + 254, 508), (x + 294, 508), (x + 304, 538), (x + 244, 538)), fill="#CAD3E1")
        box((x + 214, 535, x + 334, 544), "#AEBCCF", 4)

    # A fictional window moves across the extended Windows desktop.
    progress = smooth((t - 3.0) / 2.1) if windows_mode else 0.0
    app_x = round(238 + progress * 540)
    app = Image.new("RGBA", image.size, (0, 0, 0, 0))
    app_draw = ImageDraw.Draw(app)
    app_draw.rounded_rectangle((app_x + 3, 324, app_x + 283, 451), 12, fill="#C2D0E7")
    app_draw.rounded_rectangle((app_x, 320, app_x + 280, 446), 12, fill="white")
    app_draw.rounded_rectangle((app_x, 320, app_x + 280, 350), 10, fill="#D6E5FC")
    app_draw.text((app_x + 16, 324), "工作窗口", font=fonts[18], fill=INK)
    for row, length in enumerate((224, 194, 212)):
        app_draw.rounded_rectangle((app_x + 18, 370 + row * 19, app_x + 18 + length, 376 + row * 19), 3, fill="#E0E8F3")
    for bounds in screens if windows_mode else screens[:1]:
        region = app.crop(bounds)
        image.paste(region, bounds[:2], region)
    draw = ImageDraw.Draw(image)

    if switching:
        phase = (t - (1.8 if music_press else 6.0)) / 0.8
        opacity = round(150 * math.sin(math.pi * max(0, min(1, phase))))
        shade = Image.new("RGBA", (528, 262), (24, 38, 62, opacity))
        image.paste(shade, (678, 228), shade)
        draw = ImageDraw.Draw(image)

    pointer_x = app_x + 152 if windows_mode else 1040
    pointer_y = 345 if windows_mode else 405
    draw.polygon(((pointer_x, pointer_y), (pointer_x + 3, pointer_y + 30),
                  (pointer_x + 11, pointer_y + 22), (pointer_x + 17, pointer_y + 34),
                  (pointer_x + 23, pointer_y + 31), (pointer_x + 17, pointer_y + 19),
                  (pointer_x + 29, pointer_y + 18)), fill=INK, outline="white", width=2)

    text(64, 562, "左屏 · Windows 主屏", 24)
    text(668, 562, "右屏 · Windows 扩展屏" if windows_mode else "右屏 · Mac", 24)
    text(64, 596, "始终保留 Windows 画面", 18, MUTED)
    text(668, 596, "DP 输入 · 可跨屏拖动窗口" if windows_mode else "HDMI 输入 · Mac 独立画面", 18, MUTED)

    for index, x in enumerate((64, 668)):
        pressing = music_press if index == 0 else mail_press
        active = (windows_mode if index == 0 else not windows_mode)
        color = BLUE if index == 0 else PURPLE
        border = color if active or pressing else "#DCE3ED"
        box((x, 640, x + 548, 724), "#FFFFFF", 16, border, 3 if active or pressing else 1)
        box((x + 16, 655, x + 72, 709), "#E8F0FF" if index == 0 else "#F0E9FA", 12)
        if index == 0:
            draw.line((x + 43, 668, x + 43, 695), fill=color, width=3)
            draw.line((x + 43, 668, x + 57, 664), fill=color, width=3)
            draw.ellipse((x + 32, 688, x + 43, 699), fill=color)
        else:
            draw.rounded_rectangle((x + 29, 672, x + 60, 695), 3, outline=color, width=2)
            draw.line((x + 29, 673, x + 44, 684, x + 60, 673), fill=color, width=2)
        text(x + 90, 648, "音乐键" if index == 0 else "邮件键", 24, color)
        text(x + 90, 684, "Windows 双屏 + 键鼠锁定" if index == 0 else "左 Windows / 右 Mac + 键鼠切换", 18, MUTED)
        if pressing:
            text(x + 450, 662, "按下", 22, color)

    footer = "切换中，请稍候" if switching else (
        "输入源：DP     Windows：扩展双屏     键鼠：Windows" if windows_mode else
        "输入源：HDMI     Windows：仅左屏     键鼠：Mac")
    text(66, 754, footer, 22, MUTED)
    draw.rounded_rectangle((64, 803, 1216, 808), 2, fill="#E0E6EF")
    draw.rounded_rectangle((64, 803, 64 + round(1152 * t / SECONDS), 808), 2, fill=accent)
    return image


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--font", help="Path to a Chinese-capable font")
    parser.add_argument("--output", type=Path, default=ROOT / "assets/demo.gif")
    parser.add_argument("--preview-dir", type=Path, help="Optional inspection frames")
    args = parser.parse_args()
    font_path = find_font(args.font)
    fonts = {size: ImageFont.truetype(str(font_path), size) for size in (18, 22, 24, 40)}
    frames = [frame_at(index / FPS, fonts) for index in range(FPS * SECONDS)]
    # One global palette avoids color flicker between otherwise identical frames.
    samples = Image.new("RGB", (320, 205 * 10))
    for row, index in enumerate(range(0, len(frames), 10)):
        samples.paste(frames[index].resize((320, 205)), (0, row * 205))
    palette = samples.quantize(colors=256)
    encoded = [frame.quantize(palette=palette, dither=Image.Dither.NONE) for frame in frames]
    args.output.parent.mkdir(parents=True, exist_ok=True)
    encoded[0].save(args.output, save_all=True, append_images=encoded[1:], duration=1000 // FPS,
                    loop=0, optimize=True, disposal=1)
    if args.preview_dir:
        args.preview_dir.mkdir(parents=True, exist_ok=True)
        for label, index in (("mac", 0), ("music", 22), ("windows", 48), ("mail", 64), ("restored", 85)):
            frames[index].save(args.preview_dir / (label + ".png"))
    print(f"Saved {args.output.name}: {WIDTH}x{HEIGHT}, {SECONDS}s, {args.output.stat().st_size:,} bytes")


if __name__ == "__main__":
    main()
