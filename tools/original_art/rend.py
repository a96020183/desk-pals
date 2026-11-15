"""Design-sheet renderer for the original lineup: draws pixel grids the way DeskPals.cs does
(white halo around every pixel, then the colour), plus a 1x silhouette strip."""
from PIL import Image, ImageDraw, ImageFont

FONT = None
try:
    FONT = ImageFont.truetype("C:/Windows/Fonts/msjhbd.ttc", 18)
    FONT_S = ImageFont.truetype("C:/Windows/Fonts/msjhbd.ttc", 13)
except Exception:
    FONT = FONT_S = ImageFont.load_default()


def hexc(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


def stack(*parts):
    w = max(len(r) for p in parts for r in p)
    out = []
    for p in parts:
        for r in p:
            l = (w - len(r)) // 2
            out.append("." * l + r + "." * (w - len(r) - l))
    return out


def draw_grid(img, rows, pal, ox, oy, ps, halo=True, halo_col=(255, 255, 255), flip=False):
    d = ImageDraw.Draw(img)
    hw = max(1, ps // 3)
    for pas in ((0, 1) if halo else (1,)):
        for y, r in enumerate(rows):
            for x, c in enumerate(r):
                if c == ".":
                    continue
                xx = (len(r) - 1 - x) if flip else x
                px, py = ox + xx * ps, oy + y * ps
                if pas == 0:
                    d.rectangle([px - hw, py - hw, px + ps + hw - 1, py + ps + hw - 1], fill=halo_col)
                else:
                    col = hexc(pal[c]) if c in pal else (255, 0, 255)
                    d.rectangle([px, py, px + ps - 1, py + ps - 1], fill=col)


def sheet(items, out, ps=10, bg="#5B7DA8", cols=None, label_col=(255, 255, 255), small=4):
    """items: list of (label, rows, pal). Each drawn big (ps) and at real size (small) + silhouette."""
    cols = cols or len(items)
    cw = max(max(len(r) for r in rows) for _, rows, _ in items) * ps + 40
    chh = max(len(rows) for _, rows, _ in items) * ps
    rh = chh + 40 + 26 * small + 20
    nrow = (len(items) + cols - 1) // cols
    img = Image.new("RGB", (cw * cols + 20, rh * nrow + 10), hexc(bg))
    d = ImageDraw.Draw(img)
    for i, (label, rows, pal) in enumerate(items):
        cx, cy = 20 + (i % cols) * cw, 10 + (i // cols) * rh
        d.text((cx, cy), label, fill=label_col, font=FONT)
        h = len(rows) * ps
        draw_grid(img, rows, pal, cx, cy + 30 + chh - h, ps)
        # real size + silhouette
        sy = cy + 40 + chh
        draw_grid(img, rows, pal, cx, sy + (24 - len(rows)) * small, small)
        sil = {c: "#1A1A1A" for r in rows for c in r if c != "."}
        draw_grid(img, rows, sil, cx + 20 * small, sy + (24 - len(rows)) * small, small, halo=False)
    img.save(out)
    return img


def lineup(items, out, ps=4, bg="#5B7DA8", gap=8, night=False):
    """Four side by side at real app scale on a desktop-coloured strip (what a screenshot looks like)."""
    w = sum(max(len(r) for r in rows) * ps for _, rows, _ in items) + gap * ps * (len(items) + 1)
    h = max(len(rows) for _, rows, _ in items) * ps + 16 * ps
    img = Image.new("RGB", (w, h), hexc(bg))
    x = gap * ps
    for _, rows, pal in items:
        draw_grid(img, rows, pal, x, h - 4 * ps - len(rows) * ps, ps)
        x += max(len(r) for r in rows) * ps + gap * ps
    img.save(out)
    return img
