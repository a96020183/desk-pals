"""窩伴小世界（翻翻・破破・綿綿）的圖：放進 extension/desktop/pals/woban。

用法（只需要 Pillow，可重跑）：
  python tools/woban_art/woban_art.py placeholder
      → 暫代圖：把續命小隊的圖換色（躲躲→翻翻、沒電→破破、刺刺→綿綿），書包小屋用程式畫一個簡單的版本。
        woban.txt 第一行寫 placeholder，程式啟動時 log 會記「woban art is placeholder」。
  python tools/woban_art/woban_art.py import <素材線的 ship 資料夾，例如 C:\\tmp\\dp\\woban\\ship>
      → 換成真的素材：<ship>/<id>/<1x|2x>/<動作>.png（16 張，同 squad2 的 manifest.json 格式）。
        書包小屋：<ship>/shelf/shelf.txt＋<ship>/shelf/<1x|2x>/<圖>.png（格式見下）；沒有就保留暫代的小屋並提醒。

書包小屋 shelf.txt（跟紙箱櫃 pals/shelf/shelf.txt 同一套，座標＝2x 圖的像素）：
  size 寬 高
  cell 格 開口x y 寬 高 背板x y 寬 高 地板後緣y 地板前緣y 腳底x 腳底y 名牌x y 寬 高
       （格 0＝翻翻（左）、1＝破破（中）、2＝綿綿（右）；三格一樣大、左右並排）
  tab 收合鈕x y 寬 高
  crown 正面上緣y（再上面可以拖著搬家）
  image 圖檔名（預設 box.png）
  pedestal 0（格 0 不畫展示台）、note 0（不釘便利貼）
"""
import json
import os
import shutil
import sys

from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
PALS = os.path.join(ROOT, "extension", "desktop", "pals")
OUT = os.path.join(PALS, "woban")
KEYS = ["stand", "walk1", "walk2", "jump", "sleep", "happy", "held", "sit", "grab", "push", "cry", "blown", "sig1", "sig2", "surprised", "pout"]
IDS = ["fanfan", "bobo", "mian"]
NL = chr(10)
NAMES = {"fanfan": "翻翻", "bobo": "破破", "mian": "綿綿"}
# 暫代：從續命小隊借哪一隻、色相轉多少（0～255）
BORROW = {"fanfan": ("duoduo", 120), "bobo": ("meidian", 230), "mian": ("cici", 110)}


def save_png(im, path):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    im = im.convert("RGBA")
    im.quantize(256, method=Image.Quantize.FASTOCTREE, dither=Image.Dither.NONE).save(path, optimize=True)


def hue_shift(im, dh):
    im = im.convert("RGBA")
    a = im.getchannel("A")
    h, s, v = im.convert("RGB").convert("HSV").split()
    h = h.point(lambda x: (x + dh) % 256)
    s = s.point(lambda x: min(255, int(x * 0.85)))
    out = Image.merge("HSV", (h, s, v)).convert("RGB")
    out.putalpha(a)
    return out


def body_box(path):
    im = Image.open(path).convert("RGBA")
    return im.getchannel("A").point(lambda v: 255 if v > 24 else 0).getbbox(), im.size


def meta_lines(src_dir, anchors, placeholder):
    """woban.txt：id 倍率 畫布寬 畫布高 腳底中心x 腳底y 身體頂y 身體高 身體左x 身體寬（stand 的不透明範圍）"""
    lines = []
    if placeholder:
        lines += ["placeholder 1", "# ↑ 暫代圖（續命小隊換色）：素材線的真圖好了用 tools/woban_art/woban_art.py import 換掉"]
    lines += ["# 窩伴小世界的圖（tools/woban_art/woban_art.py 產生，別手改）",
              "# id 倍率 畫布寬 畫布高 腳底中心x 腳底y 身體頂y 身體高 身體左x 身體寬（stand 的不透明範圍；泡泡、櫃子大小、走路間距用）"]
    for c in IDS:
        for r in (1, 2):
            (l, t, rr, b), (cw, ch) = body_box(os.path.join(src_dir, c, f"{r}x", "stand.png"))
            fx, by = anchors[c][r]
            lines.append(f"{c} {r} {cw} {ch} {fx} {by} {t} {by - t + 1} {l} {rr - l}")
    return lines


def icon(src_png, dst):
    im = Image.open(src_png).convert("RGBA")
    im = im.crop(im.getchannel("A").point(lambda v: 255 if v > 8 else 0).getbbox())
    save_png(im, dst)


# ---------------------------------------------------------------- 書包小屋（暫代）
HOUSE = {"size": (624, 410), "crown": 96, "tab": (520, 52, 44, 22), "open_w": 170, "open_h": 222, "open_y": 112, "xs": (30, 227, 424)}
WALL = [(0xE4, 0xF0, 0xFB), (0xFD, 0xE8, 0xDF), (0xEE, 0xE6, 0xF8)]   # 翻翻淡藍、破破蜜桃、綿綿淡紫


def house_cells():
    H = HOUSE
    cells = []
    for i, x in enumerate(H["xs"]):
        ow, oh, oy = H["open_w"], H["open_h"], H["open_y"]
        back = (x + 8, oy + 8, ow - 16, oh - 56)
        fb, ff = oy + oh - 48, oy + oh
        foot = (x + ow // 2, oy + oh - 20)
        pw, ph = 124, 26
        plate = (x + (ow - pw) // 2, oy + oh + 16, pw, ph)
        cells.append((i, (x, oy, ow, oh), back, fb, ff, foot, plate))
    return cells


def draw_house(path_2x, path_1x, txt):
    W, Hh = HOUSE["size"]
    ink, halo = (0x2A, 0x26, 0x33, 255), (255, 255, 255, 255)
    im = Image.new("RGBA", (W, Hh), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    body = (16, 52, W - 16, Hh - 14)
    # 提把、白邊、本體、上蓋
    d.rounded_rectangle((W // 2 - 70, 4, W // 2 + 70, 70), 34, outline=halo, width=22)
    d.rounded_rectangle((W // 2 - 70, 4, W // 2 + 70, 70), 34, outline=ink, width=10)
    d.rounded_rectangle((body[0] - 8, body[1] - 8, body[2] + 8, body[3] + 8), 68, fill=halo)
    d.rounded_rectangle(body, 60, fill=(0xA8, 0xD8, 0xC4, 255), outline=ink, width=8)
    d.rounded_rectangle((body[0], body[1], body[2], HOUSE["crown"] + 4), 60, fill=(0x86, 0xC4, 0xAC, 255), outline=ink, width=8)
    d.line((body[0] + 30, HOUSE["crown"] + 4, body[2] - 30, HOUSE["crown"] + 4), fill=ink, width=6)
    tx, ty, tw, th = HOUSE["tab"]
    d.rounded_rectangle((tx, ty, tx + tw, ty + th), 10, fill=(0xFF, 0xF4, 0xE2, 255), outline=ink, width=4)
    lines = ["# 書包小屋（暫代圖：tools/woban_art/woban_art.py placeholder 用程式畫的；素材線的真圖好了換掉）",
             "# 座標＝2x 圖的像素（1x 圖剛好一半）；格 0＝左（翻翻）、1＝中（破破）、2＝右（綿綿），三格一樣大",
             f"size {W} {Hh}"]
    for (i, o, b, fb, ff, foot, pl) in house_cells():
        x, y, w, h = o
        d.rounded_rectangle((x - 6, y - 6, x + w + 6, y + h + 6), 30, fill=ink)
        d.rounded_rectangle((x, y, x + w, y + h), 24, fill=WALL[i] + (255,))
        d.rectangle((x + 4, fb, x + w - 4, ff - 4), fill=(0xEA, 0xCC, 0xA4, 255))
        d.line((x + 4, fb, x + w - 4, fb), fill=(0xC8, 0xA4, 0x7A, 255), width=4)
        # 每間一點小擺設：書架／小窗／月亮
        if i == 0:
            for k in range(3):
                d.rectangle((x + 22 + k * 14, y + 40, x + 32 + k * 14, y + 78), fill=[(0xF2, 0x9E, 0x8E, 255), (0x8E, 0xB8, 0xE8, 255), (0xF6, 0xCF, 0x6A, 255)][k])
            d.line((x + 16, y + 80, x + 76, y + 80), fill=ink, width=4)
        elif i == 1:
            d.rounded_rectangle((x + w - 70, y + 30, x + w - 22, y + 78), 8, fill=(0xC8, 0xE8, 0xFA, 255), outline=ink, width=4)
            d.line((x + w - 46, y + 30, x + w - 46, y + 78), fill=ink, width=3)
        else:
            d.ellipse((x + w - 66, y + 30, x + w - 26, y + 70), fill=(0xFF, 0xE8, 0x9A, 255))
            d.ellipse((x + w - 56, y + 24, x + w - 18, y + 62), fill=WALL[i] + (255,))
        px, py, pw, ph = pl
        d.rounded_rectangle((px, py, px + pw, py + ph), 9, fill=(0xFF, 0xFB, 0xF2, 255), outline=ink, width=4)
        lines.append(f"cell {i} {x} {y} {w} {h} {b[0]} {b[1]} {b[2]} {b[3]} {fb} {ff} {foot[0]} {foot[1]} {px} {py} {pw} {ph}")
    try:
        f = ImageFont.truetype(r"C:\Windows\Fonts\msjhbd.ttc", 22)
        d.text((40, 60), "暫代圖", font=f, fill=(0x2A, 0x26, 0x33, 160))
    except OSError:
        pass
    lines += [f"tab {tx} {ty} {tw} {th}", f"crown {HOUSE['crown']}", "image house.png", "pedestal 0", "note 0"]
    save_png(im, path_2x)
    save_png(im.resize((W // 2, Hh // 2), Image.LANCZOS), path_1x)
    with open(txt, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(lines) + "\n")


# ---------------------------------------------------------------- 主程式
def placeholder():
    squad = os.path.join(PALS, "squad")
    anchors = {}
    for line in open(os.path.join(squad, "squad.txt"), encoding="utf-8"):
        a = line.split()
        if len(a) >= 8 and not a[0].startswith("#"):
            anchors.setdefault(a[0], {})[int(a[1])] = (int(a[4]), int(a[5]))
    for c in IDS:
        src, dh = BORROW[c]
        for r in (1, 2):
            for k in KEYS:
                save_png(hue_shift(Image.open(os.path.join(squad, src, f"{r}x", f"{k}.png")), dh), os.path.join(OUT, c, f"{r}x", f"{k}.png"))
        icon(os.path.join(OUT, c, "2x", "stand.png"), os.path.join(OUT, c, "icon.png"))
    an = {c: anchors[BORROW[c][0]] for c in IDS}
    with open(os.path.join(OUT, "woban.txt"), "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(meta_lines(OUT, an, True)) + "\n")
    with open(os.path.join(OUT, "PLACEHOLDER.txt"), "w", encoding="utf-8", newline="\n") as fh:
        fh.write("這個資料夾的圖是暫代圖（續命小隊換色＋程式畫的書包小屋），不是窩伴小世界的正式素材。\n"
                 "素材線（C:\\tmp\\dp\\woban\\ship）好了以後：python tools/woban_art/woban_art.py import C:\\tmp\\dp\\woban\\ship\n")
    house = os.path.join(OUT, "shelf")
    draw_house(os.path.join(house, "2x", "house.png"), os.path.join(house, "1x", "house.png"), os.path.join(house, "shelf.txt"))
    print("placeholder art →", OUT)


def import_ship(ship):
    """素材線的產出（C:/tmp/dp/woban）：ship/<id>/<1x|2x>/*.png、icon.png、manifest.json、squad.txt；書包小屋在 ship 旁邊的 shelf/。
    圖原封不動複製（素材線用每張自己的 224＋31 色調色盤，再量化一次會有色帶）。"""
    for c in IDS:
        for r in (1, 2):
            for k in KEYS:
                if not os.path.isfile(os.path.join(ship, c, f"{r}x", f"{k}.png")):
                    sys.exit(f"少了 {c}/{r}x/{k}.png")
    if os.path.isdir(OUT):
        shutil.rmtree(OUT)
    for c in IDS:
        for r in (1, 2):
            os.makedirs(os.path.join(OUT, c, f"{r}x"))
            for k in KEYS:
                shutil.copyfile(os.path.join(ship, c, f"{r}x", f"{k}.png"), os.path.join(OUT, c, f"{r}x", f"{k}.png"))
        shutil.copyfile(os.path.join(ship, c, "icon.png"), os.path.join(OUT, c, "icon.png"))
    shutil.copyfile(os.path.join(ship, "manifest.json"), os.path.join(OUT, "manifest.json"))
    meta = open(os.path.join(ship, "squad.txt"), encoding="utf-8").read().splitlines()
    # shadow 1：圖沒有白邊，淺色桌布上輪廓偏弱 → 程式在腳下畫一層很淡的落地陰影（只有這一櫃）
    meta += ["shadow 1"]
    with open(os.path.join(OUT, "woban.txt"), "w", encoding="utf-8", newline=NL) as fh:
        fh.write(NL.join(meta) + NL)
    sh = os.path.join(os.path.dirname(os.path.abspath(ship)), "shelf")
    dst = os.path.join(OUT, "shelf")
    os.makedirs(os.path.join(dst, "1x")); os.makedirs(os.path.join(dst, "2x"))
    for r in (1, 2):
        shutil.copyfile(os.path.join(sh, f"{r}x", "box.png"), os.path.join(dst, f"{r}x", "box.png"))
    lines = open(os.path.join(sh, "shelf.txt"), encoding="utf-8").read().splitlines()
    lines += ["# 程式用：格 0 不畫展示台、不釘便利貼（三格一樣大）", "pedestal 0", "note 0"]
    txt = NL.join(lines) + NL
    with open(os.path.join(dst, "shelf.txt"), "w", encoding="utf-8", newline=NL) as fh:
        fh.write(txt)
    print("imported", ship, "→", OUT)


if __name__ == "__main__":
    if len(sys.argv) >= 2 and sys.argv[1] == "placeholder":
        placeholder()
    elif len(sys.argv) >= 3 and sys.argv[1] == "import":
        import_ship(sys.argv[2])
    else:
        print(__doc__)
        sys.exit(2)
