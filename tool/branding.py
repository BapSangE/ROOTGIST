"""앱 아이콘·스플래시 원본 이미지를 만든다(로고 2026-10-27: 펼친 책·새싹 마크 + 가로 로고).

    python3 tool/branding.py        # Pillow, numpy, Google Chrome 필요
    dart run flutter_launcher_icons
    dart run flutter_native_splash:create

입력:
  assets/branding/rootgist_app_icon.svg      마크 벡터, 정사각 바탕 포함(1254 기준, 마크 긴 변 52%)
  assets/branding/rootgist_symbol.svg        마크 벡터, 투명 바탕·여백 거의 없음
  assets/branding/rootgist_symbol_padded.svg 마크 벡터, 앱 아이콘과 같은 자리·여백, 투명 바탕
  assets/branding/rootgist_logo_horizontal_source.png  마크 + 글자, 투명 바탕 2000×667(글자 부분만 쓴다)
SVG는 받은 벡터 재작도본(베지어 3개)이고 색만 앱 토큰으로 바꿨다: 검정 #22211F → textPrimary #0E0E0D,
바탕 #F6F5F3 → bgApp #F4F4F1, 주황 #E0533A(newDot) 그대로. 마크는 SVG를 Chrome으로 바로 그려 선명하게,
가로 로고의 글자는 래스터 원본을 토큰 색으로 다시 칠해 쓴다(벡터 글자가 아직 없다).

assets/branding/ 은 앱에 번들하지 않는 원본이다. 플랫폼별 크기는 위 두 도구가 만든다.
"""
import subprocess
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / 'assets/branding'
CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome'
BG = np.array([0xF4, 0xF4, 0xF1], float)  # bgApp
INK = np.array([0x0E, 0x0E, 0x0D], float)  # textPrimary
RED = np.array([0xE0, 0x53, 0x3A], float)  # newDot


def svg_layer(path: Path, px: int) -> Image.Image:
    """SVG를 px×px 투명 PNG로(헤드리스 Chrome). 바탕이 있는 SVG면 바탕까지 그린다."""
    with tempfile.TemporaryDirectory() as d:
        html = Path(d) / 'svg.html'
        png = Path(d) / 'svg.png'
        html.write_text(
            '<!doctype html><html><body style="margin:0;background:transparent">'
            f'<img src="{path.as_uri()}" style="display:block;width:{px}px;height:{px}px"></body></html>'
        )
        subprocess.run(
            [CHROME, '--headless=new', '--disable-gpu', '--hide-scrollbars', '--allow-file-access-from-files',
             '--default-background-color=00000000', '--force-device-scale-factor=1', f'--window-size={px},{px}',
             f'--screenshot={png}', html.as_uri()],
            check=True, capture_output=True,
        )
        return Image.open(png).convert('RGBA').copy()


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
    cover = np.where(cover < 0.06, 0, cover)  # 바탕의 미세한 얼룩은 바탕으로
    share = np.where(a + b > 0, b / np.maximum(a + b, 1e-6), 0)[:, None]
    return INK * (1 - share) + RED * share, cover


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


def trimmed(layer: Image.Image) -> Image.Image:
    return layer.crop(layer.getchannel('A').getbbox())


def placed(layer: Image.Image, canvas: int, size: int) -> Image.Image:
    """잉크 영역을 긴 변 size로 줄여 정사각 투명 캔버스 정가운데에."""
    ink = trimmed(layer)
    s = size / max(ink.size)
    ink = ink.resize((round(ink.width * s), round(ink.height * s)), Image.LANCZOS)
    im = Image.new('RGBA', (canvas, canvas), (0, 0, 0, 0))
    im.alpha_composite(ink, ((canvas - ink.width) // 2, (canvas - ink.height) // 2))
    return im


def horizontal_logo(mark: Image.Image, logo: Image.Image) -> Image.Image:
    """가로 로고의 마크 자리에 벡터 마크를 같은 높이로 넣는다. 글자는 래스터 그대로.
    마크와 글자 사이 비어 있는 세로 띠로 둘을 나눈다."""
    logo = trimmed(logo)
    cols = np.asarray(logo.getchannel('A')).max(0) > 8
    gap = int(np.argmax(~cols))  # 마크 오른쪽 첫 빈 열
    text_at = gap + int(np.argmax(cols[gap:]))  # 글자가 시작하는 열
    old_mark = trimmed(logo.crop((0, 0, gap, logo.height)))
    text = logo.crop((text_at, 0, logo.width, logo.height))
    m = trimmed(mark)
    m = m.resize((round(m.width * old_mark.height / m.height), old_mark.height), Image.LANCZOS)
    space = text_at - gap + (old_mark.width - m.width)  # 마크 폭이 달라도 글자 앞 간격은 원본과 같게
    out = Image.new('RGBA', (m.width + space + text.width, logo.height), (0, 0, 0, 0))
    mark_top = logo.getchannel('A').crop((0, 0, gap, logo.height)).getbbox()[1]
    out.alpha_composite(m, (0, mark_top))
    out.alpha_composite(text, (m.width + space, 0))
    return out


OUT.mkdir(exist_ok=True)
mark = svg_layer(OUT / 'rootgist_symbol.svg', 2048)

# iOS·Android 기본 아이콘: 불투명(iOS는 투명 금지), 모서리는 OS가 깎는다. 받은 앱 아이콘 SVG 그대로(마크 52%).
svg_layer(OUT / 'rootgist_app_icon.svg', 1024).convert('RGB').save(OUT / 'icon.png')
# Android 적응형 전경: 바깥 1/6씩 잘려 보이므로 같은 크기로 보이게 2/3로 줄인다. 배경은 BG 단색(pubspec).
placed(mark, 1024, 355).save(OUT / 'icon_foreground.png')
# 스플래시: 가로 로고(마크 + 글자). 4배 기준 폭 880 = 화면 220pt.
ink = horizontal_logo(mark, logo_layer(OUT / 'rootgist_logo_horizontal_source.png'))
s = 880 / ink.width
ink = ink.resize((880, round(ink.height * s)), Image.LANCZOS)
splash = Image.new('RGBA', (960, ink.height + 80), (0, 0, 0, 0))
splash.alpha_composite(ink, (40, 40))
splash.save(OUT / 'splash.png')
# Android 12+ 스플래시: 1152 캔버스 중 가운데 지름 768 원만 보인다. 글자는 넣지 않고 마크만.
placed(mark, 1152, 460).save(OUT / 'splash_android12.png')
print('assets/branding 갱신')
