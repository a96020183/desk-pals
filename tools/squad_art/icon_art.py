"""App 圖示用的大圖（packaging/icons/squad/<id>.png）：從重新切好的原圖（resplit.py 的 raw/）取 stand，裁掉透明邊、縮成 512 高、256 色。
用法：python icon_art.py <raw 資料夾> <輸出資料夾>
"""
import os, sys
from PIL import Image

raw, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
for pid in ("duoduo", "meidian", "cici"):
    im = Image.open(os.path.join(raw, pid, "stand.png")).convert("RGBA")
    im = im.crop(im.getchannel("A").point(lambda v: 255 if v > 24 else 0).getbbox())
    h = 512
    w = round(im.width * h / im.height)
    im = im.convert("RGBa").resize((w, h), Image.LANCZOS, reducing_gap=3.0).convert("RGBA")
    im.quantize(256, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE).save(os.path.join(out, pid + ".png"), optimize=True)
    print(pid, im.size)
