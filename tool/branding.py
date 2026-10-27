"""앱 아이콘·스플래시 원본 이미지를 만든다(로고 2026-10-27: 펼친 책·새싹 마크 + 가로 로고).

    python3 tool/branding.py        # Pillow, numpy 필요
    dart run flutter_launcher_icons
    dart run flutter_native_splash:create

입력(받은 로고 원본, 이름만 바꿨다):
  assets/branding/rootgist_mark_source.png            마크, 밝은 바탕 위 1254×1254
  assets/branding/rootgist_logo_horizontal_source.png 마크 + 글자, 투명 바탕 2000×667
원본의 검정·주황은 파일마다 조금씩 달라(#272523·#201E1A, #DD5C3E·#DF5836) 앱 토큰
textPrimary #111111·newDot #E0533A로 다시 칠한다. 가장자리의 부드러운 경계(안티에일리어싱)는 비율 그대로 살린다.

assets/branding/ 은 앱에 번들하지 않는 원본이다. 플랫폼별 크기는 위 두 도구가 만든다.
"""
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'assets/branding'
BG = np.array([0xF6, 0xF5, 0xF3], float)  # bgApp
INK = np.array([0x11, 0x11, 0x11], float)  # textPrimary
RED = np.array([0xE0, 0x53, 0x3A], float)  # newDot


def _median(px: np.ndarray, keep: np.ndarray) -> np.ndarray:
    return np.median(px[keep], axis=0)


def _recolor(flat: np.ndarray, bg: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    """픽셀마다 「바탕 + a·(검정−바탕) + b·(주황−바탕)」으로 보고 a·b를 최소제곱으로 푼다.
    돌려주는 것: 토큰 색(검정·주황을 b/(a+b) 비율로 섞은 색), 덮는 정도(a+b, 0~1)."""
    ink = _median(flat, flat.sum(1) < 150)
    red = _median(flat, (flat[:, 0] > 180) & (flat[:, 1] < 120) & (flat[:, 2] < 100))
    basis = np.stack([ink - bg, red - bg], 1)  # 3×2
    w, *_ = np.linalg.lstsq(basis, (flat - bg).T, rcond=None)  # 2×N
    a, b = np.clip(w, 0, 1)
    cover = np.clip(a + b, 0, 1)
    cover = np.where(cover < 0.06, 0, cover)  # 바탕의 미세한 얼룩(#F5F4F2 등)은 바탕으로
    share = np.where(a + b > 0, b / np.maximum(a + b, 1e-6), 0)[:, None]
    return INK * (1 - share) + RED * share, cover


def mark_layer(path: Path) -> Image.Image:
    """밝은 바탕 위 마크 → 토큰 색으로 칠한 투명 레이어."""
    px = np.asarray(Image.open(path).convert('RGB'), float)
    flat = px.reshape(-1, 3)
    rgb, cover = _recolor(flat, _median(flat, flat.sum(1) > 700))
    rgba = np.concatenate([rgb, cover[:, None] * 255], 1).reshape(px.shape[0], px.shape[1], 4)
    return Image.fromarray(rgba.round().astype(np.uint8), 'RGBA')


def logo_layer(path: Path) -> Image.Image:
    """투명 바탕 가로 로고 → 흰 바탕에 올려 같은 방법으로 풀고, 원래 투명도와 곱한다.
    잎 사이 흰 틈(불투명 흰색)이 검정·주황 사이 색으로 칠해지지 않게 흰색을 바탕으로 본다."""
    im = Image.open(path).convert('RGBA')
    px = np.asarray(im, float)
    rgb, alpha = px[..., :3].reshape(-1, 3), px[..., 3].reshape(-1) / 255
    white = np.array([255, 255, 255], float)
    on_white = rgb * alpha[:, None] + white * (1 - alpha[:, None])
    color, cover = _recolor(on_white, white)
    rgba = np.concatenate([color, cover[:, None] * 255], 1).reshape(px.shape)
    return Image.fromarray(rgba.round().astype(np.uint8), 'RGBA')


def placed(layer: Image.Image, canvas: int, size: int) -> Image.Image:
    """잉크 영역을 긴 변 size로 줄여 정사각 투명 캔버스 정가운데에."""
    ink = layer.crop(layer.getchannel('A').getbbox())
    s = size / max(ink.size)
    ink = ink.resize((round(ink.width * s), round(ink.height * s)), Image.LANCZOS)
    im = Image.new('RGBA', (canvas, canvas), (0, 0, 0, 0))
    im.alpha_composite(ink, ((canvas - ink.width) // 2, (canvas - ink.height) // 2))
    return im


def on_bg(layer: Image.Image) -> Image.Image:
    bg = Image.new('RGBA', layer.size, tuple(BG.astype(int)) + (255,))
    bg.alpha_composite(layer)
    return bg.convert('RGB')


OUT.mkdir(exist_ok=True)
mark = mark_layer(OUT / 'rootgist_mark_source.png')
logo = logo_layer(OUT / 'rootgist_logo_horizontal_source.png')

# iOS·Android 기본 아이콘: 불투명(iOS는 투명 금지), 모서리는 OS가 깎는다. 마크 긴 변 = 폭의 52%(받은 시안 비율 그대로).
on_bg(placed(mark, 1024, 532)).save(OUT / 'icon.png')
# Android 적응형 전경: 바깥 1/6씩 잘려 보이므로 같은 크기로 보이게 2/3로 줄인다. 배경은 BG 단색(pubspec).
placed(mark, 1024, 355).save(OUT / 'icon_foreground.png')
# 스플래시: 가로 로고(마크 + 글자). 4배 기준 폭 880 = 화면 220pt.
ink = logo.crop(logo.getchannel('A').getbbox())
s = 880 / ink.width
ink = ink.resize((880, round(ink.height * s)), Image.LANCZOS)
splash = Image.new('RGBA', (960, ink.height + 80), (0, 0, 0, 0))
splash.alpha_composite(ink, (40, 40))
splash.save(OUT / 'splash.png')
# Android 12+ 스플래시: 1152 캔버스 중 가운데 지름 768 원만 보인다. 글자는 넣지 않고 마크만.
placed(mark, 1152, 460).save(OUT / 'splash_android12.png')
print('assets/branding 갱신')
