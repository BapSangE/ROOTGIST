"""앱 아이콘·스플래시 원본 이미지를 만든다(PROPOSALS P2, 아이콘 시안 A).

    python3 tool/branding.py        # Pillow 필요
    dart run flutter_launcher_icons
    dart run flutter_native_splash:create

assets/branding/ 은 앱에 번들하지 않는 원본이다. 플랫폼별 크기는 위 두 도구가 만든다.
"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
FONTS = ROOT / 'assets/fonts'
OUT = ROOT / 'assets/branding'
BG = (0xF6, 0xF5, 0xF3)  # bgApp
INK = (0x11, 0x11, 0x11)  # textPrimary


def text_image(text, size, canvas, *, font='Pretendard-Bold.otf', tracking=0.0, bg=None):
    """글자 잉크 영역을 캔버스 정가운데에. tracking은 em 비율."""
    im = Image.new('RGBA', canvas, bg + (255,) if bg else (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    f = ImageFont.truetype(str(FONTS / font), size)
    boxes = [d.textbbox((0, 0), ch, font=f) for ch in text]
    gap = tracking * size
    width = sum(b[2] - b[0] for b in boxes) + gap * (len(text) - 1)
    top, bottom = min(b[1] for b in boxes), max(b[3] for b in boxes)
    x, y = (canvas[0] - width) / 2, (canvas[1] - (bottom - top)) / 2 - top
    for ch, b in zip(text, boxes):
        d.text((x - b[0], y), ch, font=f, fill=INK)
        x += b[2] - b[0] + gap
    return im


OUT.mkdir(exist_ok=True)
# iOS·Android 기본 아이콘: 불투명(iOS는 투명 금지), 모서리는 OS가 깎는다.
text_image('R', 620, (1024, 1024), bg=BG).convert('RGB').save(OUT / 'icon.png')
# Android 적응형 전경: 바깥 1/6씩 잘려 보이므로 같은 크기로 보이게 2/3로 줄인다. 배경은 BG 단색.
text_image('R', 413, (1024, 1024)).save(OUT / 'icon_foreground.png')
# 스플래시 워드마크(4배 기준 = 화면 24pt, 앱 안 워드마크와 같은 자간 +1.2/17).
text_image('ROOTGIST', 96, (960, 160), tracking=1.2 / 17).save(OUT / 'splash.png')
# Android 12+ 스플래시: 1152 캔버스 중 가운데 지름 768 원만 보인다.
text_image('R', 470, (1152, 1152)).save(OUT / 'splash_android12.png')
print('assets/branding 갱신')
