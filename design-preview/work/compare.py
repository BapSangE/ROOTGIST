# 바탕 온도 비교: 지금(따뜻한 종이) ↔ 중립 회색, 화면 3개를 쌍으로.
from PIL import Image, ImageDraw, ImageFont
F = "../assets/fonts/Pretendard-%s.otf"
W, H = 402, 874; gap, pair, pad = 24, 72, 80
names = [("01_home","홈"),("03_paper","논문 상세"),("05_reader","초록 리더")]
img = Image.new("RGB", (pad*2 + 6*W + 3*gap + 2*pair, pad + 230 + H + 100 + 200), (226,226,226))
d = ImageDraw.Draw(img)
d.text((pad, pad), "바탕 온도 비교", font=ImageFont.truetype(F % "Bold", 52), fill=(14,14,14))
d.text((pad, pad+72), "각 쌍의 왼쪽: 지금 시안(따뜻한 종이)   오른쪽: 중립 회색. 글자·강조색·구성은 같아요.", font=ImageFont.truetype(F % "Regular", 28), fill=(100,100,100))
fl = ImageFont.truetype(F % "SemiBold", 24); fs = ImageFont.truetype(F % "Regular", 22)
x = pad; y = pad + 170
for n, t in names:
    for v, lab in [("w_", "지금 · 따뜻한 종이"), ("n_", "중립 회색")]:
        sh = Image.open(f"work/compare/{v}{n}.png").convert("RGB").resize((W, H), Image.LANCZOS)
        m = Image.new("L", (W, H), 0); ImageDraw.Draw(m).rounded_rectangle((0,0,W-1,H-1), 44, fill=255)
        d.rounded_rectangle((x-6, y-6, x+W+5, y+H+5), 50, fill=(20,20,20))
        img.paste(sh, (x, y), m)
        d.text((x, y+H+22), f"{t}", font=fl, fill=(14,14,14))
        d.text((x, y+H+56), lab, font=fs, fill=(100,100,100))
        x += W + gap
    x += pair - gap
# 바탕 색 견본
sw = [("바탕", "#F4F4F1", "#F5F5F5"), ("리더 바탕", "#FAFAF7", "#FFFFFF"), ("칩·세그먼트", "#EBEBE6", "#EDEDED"), ("구분선", "#E4E4DF", "#E5E5E5"), ("보조 글자", "#6B6B65", "#6B6B6B")]
y2 = y + H + 110; x = pad
for name, a, b in sw:
    for k, c in enumerate([a, b]):
        d.rounded_rectangle((x + k*70, y2, x + k*70 + 60, y2+60), 12, fill=c, outline=(200,200,200))
    d.text((x+150, y2+4), name, font=fl, fill=(14,14,14)); d.text((x+150, y2+36), f"{a} → {b}", font=fs, fill=(100,100,100))
    x += 500
img.save("work/compare/background_compare.png"); print(img.size)
