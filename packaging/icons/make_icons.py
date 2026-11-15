"""公仔櫃 Desk Pals：產生獨立版要用的所有圖示（全部從 tools/original_art/final_art.py 的像素圖畫出來，不放二進位檔進 repo）。

用法：python -I packaging/icons/make_icons.py [輸出資料夾]   （預設 build/icons；需要 Pillow）
產出：
  DeskPals.ico                      Windows exe／安裝程式／捷徑（16～256，透明底，像素清楚）
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

sys.dont_write_bytecode = True   # 不在 tools/original_art 留 __pycache__

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, os.path.join(ROOT, "tools", "original_art"))
import final_art as A  # noqa: E402

SHARED = dict(S="#E23B3B", W="#FFFFFF", Y="#F5C842", P="#FF8FB0", B="#B8D6FF", **{"1": "#D9A55B", "2": "#A8743A"})


def hexc(h, a=255):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) + (a,)


def pal_of(pid):
    d = dict(A.PALS[pid]["pal"])
    d.update(A.EXTRA[pid])
    d.update(SHARED)
    return d


def frame(pid, head="HEAD", body="BODY", legs="LEGS_A", face=None):
    p = A.PALS[pid]
    rows = list(p.get(head, p["HEAD"])) + list(p.get(body, p["BODY"])) + list(p.get(legs, p["LEGS_A"]))
    if face:
        for i, r in enumerate(p["FACES"][face]):
            j = p["FACE_ROW"] + i
            if j < len(rows) and len(r) == len(rows[j]):
                rows[j] = r
    return rows


def trim(rows):
    """去掉上下左右全空的行列（煙、吸管上面的空白）。"""
    rows = [r for r in rows]
    while rows and set(rows[0]) <= {"."}:
        rows.pop(0)
    while rows and set(rows[-1]) <= {"."}:
        rows.pop()
    w = max(len(r) for r in rows)
    rows = [r.ljust(w, ".") for r in rows]
    l = min((len(r) - len(r.lstrip(".")) for r in rows if r.strip(".")), default=0)
    rr = min((len(r) - len(r.rstrip(".")) for r in rows if r.strip(".")), default=0)
    return [r[l:w - rr] for r in rows]


# 主角：半糖舉手開心（新安裝的預設一櫃「續命小隊」的大格）
HERO = ("boba", dict(head="HEAD_UP", body="BODY_UP", face="HAPPY"))
HERO_HEAD_ROWS = 12          # 小尺寸只畫頭（吸管＋杯蓋＋臉）


def sprite(rows, pal, ps, halo):
    """像素圖 → RGBA。halo＝每顆像素外面一圈白邊的寬度（跟桌面版一樣的畫法）。"""
    w, h = max(len(r) for r in rows), len(rows)
    img = Image.new("RGBA", (w * ps + 2 * halo, h * ps + 2 * halo), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    if halo:
        for y, r in enumerate(rows):
            for x, c in enumerate(r):
                if c != ".":
                    d.rectangle([x * ps, y * ps, x * ps + ps + 2 * halo - 1, y * ps + ps + 2 * halo - 1], fill=(255, 255, 255, 255))
    for y, r in enumerate(rows):
        for x, c in enumerate(r):
            if c != ".":
                d.rectangle([halo + x * ps, halo + y * ps, halo + x * ps + ps - 1, halo + y * ps + ps - 1], fill=hexc(pal.get(c, "#FF00FF")))
    return img


def hero_rows(head_only):
    pid, pose = HERO
    rows = frame(pid, **pose)
    return trim(rows[:HERO_HEAD_ROWS] if head_only else rows)


def fit(rows, box, halo_frac=3, max_ps=None):
    """在 box×box 裡放得下的最大整數像素倍率（含白邊）。回傳 (ps, halo)。"""
    w, h = max(len(r) for r in rows), len(rows)
    best = (0, 0)
    for ps in range(1, 64):
        halo = max(1, ps // halo_frac) if ps >= 2 or box >= 20 else 0
        if w * ps + 2 * halo <= box and h * ps + 2 * halo <= box:
            best = (ps, halo)
    if max_ps:
        best = (min(best[0], max_ps), max(1, min(best[0], max_ps) // halo_frac))
    return best


def figure_icon(n, pad=0.0):
    """透明底、只有公仔（Windows 圖示的慣例）。小尺寸只畫頭。"""
    head_only = n < 48
    rows = hero_rows(head_only)
    box = int(round(n * (1 - 2 * pad)))
    ps, halo = fit(rows, box)
    if ps == 0:
        ps, halo = 1, 0
    spr = sprite(rows, pal_of(HERO[0]), ps, halo)
    img = Image.new("RGBA", (n, n), (0, 0, 0, 0))
    img.alpha_composite(spr, ((n - spr.width) // 2, (n - spr.height + (1 if head_only else 0)) // 2))
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
    rows = hero_rows(head_only)
    plank = not head_only
    inner = int(side * (0.62 if plank else 0.78))
    ps, halo = fit(rows, inner)
    if ps == 0:
        ps, halo = 1, 0
    spr = sprite(rows, pal_of(HERO[0]), ps, halo)
    cx = ins + side // 2
    if plank:
        # 小木架：一塊像素木板，公仔站在上面
        pw = int(side * 0.70)
        ph = max(2, ps * 2)
        py = ins + int(side * 0.80)
        d = ImageDraw.Draw(img)
        x0 = cx - pw // 2
        d.rectangle([x0, py, x0 + pw - 1, py + ph - 1], fill=PLANK + (255,))
        d.rectangle([x0, py, x0 + pw - 1, py + max(1, ps // 2) - 1], fill=PLANK_L + (255,))
        d.rectangle([x0, py + ph - max(1, ps // 2), x0 + pw - 1, py + ph - 1], fill=PLANK_D + (255,))
        img.alpha_composite(spr, (cx - spr.width // 2, py - spr.height + halo))
    else:
        img.alpha_composite(spr, (cx - spr.width // 2, ins + (side - spr.height) // 2))
    return img


# ---------------- 一整櫃（續命小隊四隻站在兩層木架上）----------------
SQUAD = ["boba", "coffee", "onigiri", "sticky"]


def squad_sprites(ps, halo):
    out = []
    for pid in SQUAD:
        rows = trim(frame(pid, face="HAPPY"))
        out.append(sprite(rows, pal_of(pid), ps, halo))
    return out


def shelf_image(w, h, ps, bg_top=TOP, bg_bottom=BOTTOM):
    """安裝程式左邊那張：直的公仔櫃，兩層、每層兩隻。"""
    img = Image.new("RGBA", (w, h))
    d = ImageDraw.Draw(img)
    for y in range(h):
        t = y / max(1, h - 1)
        d.line([(0, y), (w, y)], fill=tuple(int(bg_top[i] + (bg_bottom[i] - bg_top[i]) * t) for i in range(3)) + (255,))
    halo = max(1, ps // 3)
    sp = squad_sprites(ps, halo)
    shelf_h = ps * 2
    row_h = max(s.height for s in sp) + shelf_h + ps * 3
    top = (h - 2 * row_h) // 2 + ps * 2
    for r in range(2):
        pair = sp[r * 2:r * 2 + 2]
        py = top + (r + 1) * row_h - shelf_h
        x0, x1 = ps * 2, w - ps * 2
        d.rectangle([x0, py, x1, py + shelf_h - 1], fill=PLANK + (255,))
        d.rectangle([x0, py, x1, py + max(1, ps // 2) - 1], fill=PLANK_L + (255,))
        d.rectangle([x0, py + shelf_h - max(1, ps // 2), x1, py + shelf_h - 1], fill=PLANK_D + (255,))
        gap = (w - sum(s.width for s in pair)) // 3
        x = gap
        for s in pair:
            img.alpha_composite(s, (x, py - s.height + halo))
            x += s.width + gap
    return img


def squad_strip(w, h, ps):
    """寬磚（310×150）：四隻排成一排，透明底。"""
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    halo = max(1, ps // 3)
    sp = squad_sprites(ps, halo)
    total = sum(s.width for s in sp)
    gap = (w - total) // (len(sp) + 1)
    base = (h + max(s.height for s in sp)) // 2
    x = gap
    for s in sp:
        img.alpha_composite(s, (x, base - s.height))
        x += s.width + gap
    return img


def fit_strip(w, h):
    for ps in range(32, 0, -1):
        halo = max(1, ps // 3)
        sp = squad_sprites(ps, halo)
        if sum(s.width for s in sp) + 5 * ps * 2 <= w and max(s.height for s in sp) <= h * 0.8:
            return ps
    return 1


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
        save(squad_strip(w, h, fit_strip(w, h)), a, f"Wide310x150Logo.scale-{sc}.png")
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
    print("icons →", out)


if __name__ == "__main__":
    main(os.path.abspath(sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, "build", "icons")))
