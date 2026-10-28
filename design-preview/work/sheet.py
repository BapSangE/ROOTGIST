import sys
from PIL import Image
out, names = sys.argv[1], sys.argv[2:]
ims = [Image.open(f"screens/{n}.png").convert("RGB") for n in names]
w, h = ims[0].size; s = 0.4
sheet = Image.new("RGB", (int(w*s)*len(ims) + 20*(len(ims)-1), int(h*s)), "white")
for i, im in enumerate(ims): sheet.paste(im.resize((int(w*s), int(h*s))), (i*(int(w*s)+20), 0))
sheet.save(out)
