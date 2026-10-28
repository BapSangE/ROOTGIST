# 통합 프리뷰: 14개 화면을 7열×2행으로, 화면마다 번호·이름. 글꼴은 앱의 Pretendard.
from PIL import Image, ImageDraw, ImageFont
F = "../assets/fonts/Pretendard-%s.otf"
items = [("01_home_top","홈"),("02_home_more","홈 · 아래"),("03_paper_detail","논문 상세"),("04_evidence_sheet","원문 근거 시트"),
 ("05_reader","초록 리더"),("06_term_sheet","용어 시트"),("07_explore_papers","탐색 · 논문"),("08_explore_news","탐색 · 공식 소식"),
 ("09_news_detail","공식 소식 상세"),("10_explore_models","탐색 · 모델"),("11_model_detail","모델 상세"),("12_library","보관함"),
 ("13_settings","설정"),("14_reading_settings","읽기 설정")]
W, H = 402, 874; s = 1.0; cols = 7; gap = 48; pad = 96; label = 64
bg = (232, 232, 228)
img = Image.new("RGB", (pad*2 + cols*W + (cols-1)*gap, pad + 150 + 2*(H+label) + gap + pad), bg)
d = ImageDraw.Draw(img)
d.text((pad, pad), "ROOTGIST — Ink & Paper", font=ImageFont.truetype(F % "Bold", 52), fill=(14,14,13))
d.text((pad, pad+70), "리디자인 시안 · 주요 화면 14개 · iPhone 402×874pt", font=ImageFont.truetype(F % "Regular", 28), fill=(107,107,101))
fl = ImageFont.truetype(F % "SemiBold", 24)
for k, (n, t) in enumerate(items):
    r, c = divmod(k, cols)
    x = pad + c*(W+gap); y = pad + 150 + r*(H+label+gap)
    sh = Image.open(f"screens/{n}.png").convert("RGB").resize((W, H), Image.LANCZOS)
    m = Image.new("L", (W, H), 0); ImageDraw.Draw(m).rounded_rectangle((0,0,W-1,H-1), 44, fill=255)
    d.rounded_rectangle((x-6, y-6, x+W+5, y+H+5), 50, fill=(20,20,19))
    img.paste(sh, (x, y), m)
    d.text((x, y+H+20), f"{k+1:02d}  {t}", font=fl, fill=(14,14,13))
img.save("overview.png")
print(img.size)
