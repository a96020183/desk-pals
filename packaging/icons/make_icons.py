"""公仔櫃 Desk Pals：產生獨立版要用的所有圖示（從續命小隊的圖畫出來：packaging/icons/squad/<id>.png，tools/squad_art/icon_art.py 產生）。

用法：python -I packaging/icons/make_icons.py [輸出資料夾]   （預設 build/icons；需要 Pillow）
產出：
  DeskPals.ico                      Windows exe／安裝程式／捷徑（16～256，透明底）
  png/icon-<n>.png                  同一套的 PNG
  AppIcon.iconset/                  macOS（iconutil -c icns 轉成 AppIcon.icns；圓角磚＋小木架）
  msix/Assets/*.png                 Microsoft Store（MSIX）磚與 Logo（scale-100／200、targetsize、altform-unplated）
  inno/wizard-<pct>.bmp、inno/small-<pct>.bmp   安裝程式左邊的公仔櫃圖、右上角小圖（100%～200% DPI）
"""
import os
import struct
import sys
from io import BytesIO

from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
ART = os.path.join(HERE, "squad")


def art(pid):
    im = Image.open(os.path.join(ART, pid + ".png")).convert("RGBA")
    return im.crop(im.getbbox())


# 主角：躲躲從紙箱探頭（新安裝的預設一櫃「續命小隊」的大格）；小尺寸只畫上半（頭＋箱子口）
HERO = "duoduo"
HERO_HEAD_FRAC = 0.62


def hero_img(head_only):
    im = art(HERO)
    return im.crop((0, 0, im.width, int(im.height * HERO_HEAD_FRAC))) if head_only else im


def fit_img(im, box):
    """等比縮進 box×box（貼圖本身有白邊，不另外加）。"""
    k = min(box / im.width, box / im.height)
    w, h = max(1, round(im.width * k)), max(1, round(im.height * k))
    return im.convert("RGBa").resize((w, h), Image.LANCZOS).convert("RGBA")


def figure_icon(n, pad=0.0):
    """透明底、只有公仔（Windows 圖示的慣例）。小尺寸只畫頭。"""
    head_only = n < 48
    box = int(round(n * (1 - 2 * pad)))
    spr = fit_img(hero_img(head_only), box)
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    img.alpha_composite(spr, ((n - spr.width) // 2, (n - spr.height) // 2))
    return img


# ---------------- macOS：圓角磚＋小木架 ----------------
TOP, BOTTOM = (255, 236, 214), (255, 196, 170)       # 奶茶粉橘漸層
PLANK, PLANK_D, PLANK_L = (168, 116, 58), (122, 80, 38), (217, 165, 91)


def tile_bg(n, radius_frac=0.225, inset_frac=0.0977):
    """Big Sur 以後的 mac 圖示格線：1024 裡 824 的圓角方塊（四周留陰影空間）。4 倍取樣再縮小，邊緣平滑。"""
    s = 4
    N = n * s
    img = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ins = int(round(N * inset_frac))
    side = N - 2 * ins
    rad = int(round(side * radius_frac))
    # 陰影
    sh = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle([ins, ins + int(N * 0.012), ins + side, ins + side + int(N * 0.012)], rad, fill=(60, 30, 10, 70))
    img.alpha_composite(sh)
    grad = Image.new("RGBA", (N, N))
    gd = ImageDraw.Draw(grad)
    for y in range(N):
        t = min(1, max(0, (y - ins) / max(1, side)))
        gd.line([(0, y), (N, y)], fill=tuple(int(TOP[i] + (BOTTOM[i] - TOP[i]) * t) for i in range(3)) + (255,))
    mask = Image.new("L", (N, N), 0)
    ImageDraw.Draw(mask).rounded_rectangle([ins, ins, ins + side, ins + side], rad, fill=255)
    img.paste(grad, (0, 0), mask)
    return img.resize((n, n), Image.LANCZOS), ins // s, side // s


def mac_icon(n):
    bg, ins, side = tile_bg(n)
    img = bg.copy()
    head_only = n < 64
    plank = not head_only
    inner = int(side * (0.66 if plank else 0.80))
    spr = fit_img(hero_img(head_only), inner)
    cx = ins + side // 2
    if plank:
        # 小木架：一塊木板，公仔站在上面
        pw = int(side * 0.70)
        ph = max(2, side // 40)
        py = ins + int(side * 0.82)
        d = ImageDraw.Draw(img)
        x0 = cx - pw // 2
        lip = max(1, ph // 4)
        d.rectangle([x0, py, x0 + pw - 1, py + ph - 1], fill=PLANK + (255,))
        d.rectangle([x0, py, x0 + pw - 1, py + lip - 1], fill=PLANK_L + (255,))
        d.rectangle([x0, py + ph - lip, x0 + pw - 1, py + ph - 1], fill=PLANK_D + (255,))
        img.alpha_composite(spr, (cx - spr.width // 2, py - spr.height + max(1, ph // 3)))
    else:
        img.alpha_composite(spr, (cx - spr.width // 2, ins + (side - spr.height) // 2))
    return img


# ---------------- 一整櫃（續命小隊三隻站在木架上）----------------
SQUAD = ["duoduo", "meidian", "cici"]


def squad_sprites(h):
    """三隻一起縮放（保持彼此的大小比例），最高的那隻＝h。"""
    arts = [art(pid) for pid in SQUAD]
    top = max(a.height for a in arts)
    return [fit_img(a, max(1, round(max(a.width, a.height) * h / top))) for a in arts]


def shelf_image(w, h, ps, bg_top=TOP, bg_bottom=BOTTOM):
    """安裝程式左邊那張：直的公仔櫃，上層兩隻、下層一隻。"""
    img = Image.new("RGBA", (w, h))
    d = ImageDraw.Draw(img)
    for y in range(h):
        t = y / max(1, h - 1)
        d.line([(0, y), (w, y)], fill=tuple(int(bg_top[i] + (bg_bottom[i] - bg_top[i]) * t) for i in range(3)) + (255,))
    shelf_h = ps * 2
    sp = squad_sprites(int(min(w * 0.40, h * 0.30)))
    row_h = max(s.height for s in sp) + shelf_h + ps * 3
    top = (h - 2 * row_h) // 2 + ps * 2
    for r, pair in enumerate((sp[:2], sp[2:])):
        py = top + (r + 1) * row_h - shelf_h
        x0, x1 = ps * 2, w - ps * 2
        d.rectangle([x0, py, x1, py + shelf_h - 1], fill=PLANK + (255,))
        d.rectangle([x0, py, x1, py + max(1, ps // 2) - 1], fill=PLANK_L + (255,))
        d.rectangle([x0, py + shelf_h - max(1, ps // 2), x1, py + shelf_h - 1], fill=PLANK_D + (255,))
        gap = (w - sum(s.width for s in pair)) // (len(pair) + 1)
        x = gap
        for s in pair:
            img.alpha_composite(s, (x, py - s.height + ps // 2))
            x += s.width + gap
    return img


def squad_strip(w, h):
    """寬磚（310×150）：三隻排成一排，透明底。"""
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    sh = int(h * 0.8)
    while True:
        sp = squad_sprites(sh)
        if sum(s.width for s in sp) <= w * 0.86 or sh <= 8:
            break
        sh -= 2
    total = sum(s.width for s in sp)
    gap = (w - total) // (len(sp) + 1)
    base = (h + max(s.height for s in sp)) // 2
    x = gap
    for s in sp:
        img.alpha_composite(s, (x, base - s.height))
        x += s.width + gap
    return img


# ---------------- 檔案格式 ----------------
def write_ico(path, images):
    """ICO：≤64 用 32 位元 BMP（舊程式也認得），128／256 用 PNG。每個尺寸各自畫，不是縮放。"""
    entries, blobs = [], []
    for im in images:
        n = im.width
        if n >= 128:
            b = BytesIO()
            im.save(b, "PNG")
            data = b.getvalue()
        else:
            px = im.load()
            hdr = struct.pack("<IiiHHIIiiII", 40, n, n * 2, 1, 32, 0, 0, 0, 0, 0, 0)
            rows = bytearray()
            for y in range(n - 1, -1, -1):
                for x in range(n):
                    r, g, b_, a = px[x, y]
                    rows += bytes((b_, g, r, a))
            mask_stride = ((n + 31) // 32) * 4
            mask = bytearray()
            for y in range(n - 1, -1, -1):
                line = bytearray(mask_stride)
                for x in range(n):
                    if px[x, y][3] == 0:
                        line[x // 8] |= 0x80 >> (x % 8)
                mask += line
            data = hdr + bytes(rows) + bytes(mask)
        entries.append(n)
        blobs.append(data)
    off = 6 + 16 * len(images)
    out = bytearray(struct.pack("<HHH", 0, 1, len(images)))
    for n, data in zip(entries, blobs):
        out += struct.pack("<BBBBHHII", n % 256, n % 256, 0, 0, 1, 32, len(data), off)
        off += len(data)
    for data in blobs:
        out += data
    with open(path, "wb") as f:
        f.write(out)


def save(img, *parts):
    p = os.path.join(*parts)
    os.makedirs(os.path.dirname(p), exist_ok=True)
    img.save(p)
    return p


def bmp(img, path, bg=(255, 255, 255)):
    base = Image.new("RGB", img.size, bg)
    base.paste(img, (0, 0), img)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    base.save(path)


def main(out):
    os.makedirs(out, exist_ok=True)
    # Windows
    sizes = [16, 20, 24, 32, 40, 48, 64, 128, 256]
    icons = [figure_icon(n) for n in sizes]
    write_ico(os.path.join(out, "DeskPals.ico"), icons)
    for n, im in zip(sizes, icons):
        save(im, out, "png", f"icon-{n}.png")
    save(figure_icon(512), out, "png", "icon-512.png")

    # macOS iconset
    for n in (16, 32, 128, 256, 512):
        save(mac_icon(n), out, "AppIcon.iconset", f"icon_{n}x{n}.png")
        save(mac_icon(n * 2), out, "AppIcon.iconset", f"icon_{n}x{n}@2x.png")
    save(mac_icon(1024), out, "png", "mac-1024.png")

    # MSIX（Store）：透明底（磚的底色交給 Windows）
    a = os.path.join(out, "msix", "Assets")
    for sc in (100, 200):
        k = sc / 100
        save(figure_icon(int(50 * k), pad=0.04), a, f"StoreLogo.scale-{sc}.png")
        save(figure_icon(int(44 * k), pad=0.0), a, f"Square44x44Logo.scale-{sc}.png")
        save(figure_icon(int(71 * k), pad=0.12), a, f"SmallTile.scale-{sc}.png")
        save(figure_icon(int(150 * k), pad=0.16), a, f"Square150x150Logo.scale-{sc}.png")
        save(figure_icon(int(310 * k), pad=0.18), a, f"LargeTile.scale-{sc}.png")
        w, h = int(310 * k), int(150 * k)
        save(squad_strip(w, h), a, f"Wide310x150Logo.scale-{sc}.png")
    for n in (16, 24, 32, 48, 256):
        im = figure_icon(n)
        save(im, a, f"Square44x44Logo.targetsize-{n}.png")
        save(im, a, f"Square44x44Logo.targetsize-{n}_altform-unplated.png")
        save(im, a, f"Square44x44Logo.targetsize-{n}_altform-lightunplated.png")

    # Inno Setup 精靈圖（BMP、各 DPI）
    big = {100: (164, 314, 4), 125: (192, 386, 5), 150: (246, 459, 6), 175: (273, 556, 7), 200: (328, 604, 8)}
    small = {100: 55, 125: 64, 150: 83, 175: 92, 200: 110}
    for pct, (w, h, ps) in big.items():
        bmp(shelf_image(w, h, ps), os.path.join(out, "inno", f"wizard-{pct}.bmp"))
    for pct, n in small.items():
        bmp(figure_icon(n, pad=0.04), os.path.join(out, "inno", f"small-{pct}.bmp"))
    # README／PUBLISHING 用的預覽
    save(shelf_image(328, 604, 8), out, "png", "installer-art.png")
    print("icons ->", out)


if __name__ == "__main__":
    main(os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "icons")))
