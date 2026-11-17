"""紙箱櫃（公仔櫃的外觀）：從 GPT Image 定稿量出格子、背板、地板、名牌的位置，輸出 1x／2x 圖＋ shelf.txt。

用法（可重跑）：
  PYTHONPATH=<numpy／scipy 的資料夾> python tools/shelf_art/shelf_art.py [定稿.png] [--out 資料夾] [--preview 資料夾]

- 定稿：透明背景、1024×1536；右邊一個高格（最愛）、左邊三個一樣大的小格，每格底下一塊空白名牌。
  原圖不進 repo（C:\\tmp\\dp\\gen\\shelf\\B_box_final）；輸出到 extension/desktop/pals/shelf。
- 偵測：奶油色的大塊＝背板（4 塊）、扁的＝名牌（4 塊）；從背板往左、往下找黑線：
  左邊最近的黑線是側板和背板的交界，再過去一條＝開口左緣；下面第 1 條＝地板後緣、第 2 條＝開口下緣（地板前緣）。
- 座標都存成 2x 圖的像素（1x 圖剛好是 2x 的一半；程式用 S/8 換算，S=4 是 100% 縮放）。
- --preview：畫一張對齊檢查圖 shelf_verify.png（綠＝開口、藍＝背板、紅十字＝公仔腳底、黃＝名牌、洋紅＝收合鈕和可以拖的蓋子下緣）。
- 晚上版不另外存圖：程式自己調暗、偏藍（DeskPals.cs 的 ShelfArt.Night）。
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy import ndimage as ndi

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
SRC = r"C:\tmp\dp\gen\shelf\B_box_final\generated_image_url.png"
OUT = os.path.join(ROOT, "extension", "desktop", "pals", "shelf")
SCALE_2X = 0.5        # 定稿 → 2x（1x＝0.25：100% 縮放時約 256×334，跟以前的木頭櫃（192×339）差不多高）
FOOT_DEPTH = 0.6      # 公仔站在地板深度的哪裡（0＝貼著背板、1＝地板前緣）
TAB_SRC = (764, 150, 852, 194)   # 收合鈕「－」：大箱子蓋子正面、膠帶右邊（目視選的位置，定稿座標）
CROWN_UP = 38         # 開口上緣再往上這麼多（定稿像素）＝箱子正面的上緣；再上面是蓋子，可以拖著搬家


def dark(px):
    return (px[..., :3].sum(-1) < 200) & (px[..., 3] > 200)


def runs(mask):
    out, s = [], None
    for i, v in enumerate(mask):
        if v and s is None:
            s = i
        if not v and s is not None:
            out.append((s, i - 1))
            s = None
    if s is not None:
        out.append((s, len(mask) - 1))
    return out


def quantize(img):
    """256 色調色盤＋透明（PIL 的 RGBA 量化會把白邊變奶油色）：不透明的用 RGB 中位切割＋k-means 224 色，
    半透明的邊（反鋸齒）另外 31 色（RGBA 一起分群），全透明＝第 0 色。"""
    A = np.array(img).astype(np.int32)
    h, w = A.shape[:2]
    a = A[..., 3]
    opaque, semi = a == 255, (a > 0) & (a < 255)
    rgb = Image.fromarray(A[..., :3].astype(np.uint8)).quantize(224, method=Image.Quantize.MAXCOVERAGE, kmeans=4, dither=Image.Dither.NONE)
    pal_o = np.array(rgb.getpalette()[:224 * 3], np.int32).reshape(-1, 3)
    # 半透明：簡單的 k-means（RGB＋alpha），從 alpha 分層開始
    S = A[semi].astype(np.float64)
    k = 31
    cent = S[np.linspace(0, len(S) - 1, k).astype(int)] if len(S) >= k else np.vstack([S, np.zeros((k - len(S), 4))])
    for _ in range(12):
        lab = ((S[:, None, :] - cent[None]) ** 2).sum(-1).argmin(1) if len(S) else np.zeros(0, int)
        for j in range(k):
            if (lab == j).any():
                cent[j] = S[lab == j].mean(0)
    cent = np.clip(np.round(cent), 0, 255).astype(np.int32)
    cent[:, 3] = np.clip(cent[:, 3], 1, 254)
    idx = np.zeros((h, w), np.uint8)
    O = A[opaque][:, :3]
    best = np.zeros(len(O), np.int64)
    for s in range(0, len(O), 20000):
        best[s:s + 20000] = ((O[s:s + 20000, None, :] - pal_o[None]) ** 2).sum(-1).argmin(1)
    idx[opaque] = 1 + best
    if len(S):
        idx[semi] = 1 + 224 + ((S[:, None, :] - cent[None].astype(np.float64)) ** 2).sum(-1).argmin(1)
    pal = [0, 0, 0] + pal_o.flatten().tolist() + cent[:, :3].flatten().tolist()
    alpha = [0] + [255] * 224 + cent[:, 3].tolist()
    out = Image.fromarray(idx, "P")
    out.putpalette(pal)
    out.info["transparency"] = bytes(alpha)
    return out


def measure(px):
    px = px.astype(int)
    a = px[..., 3]
    r, g, b = px[..., 0], px[..., 1], px[..., 2]
    cream = (a > 200) & (r > 235) & (g > 225) & (b > 200) & (r - b < 40)
    lab, _ = ndi.label(cream)
    backs, plates = [], []
    for i, sl in enumerate(ndi.find_objects(lab)):
        cnt = int((lab[sl] == i + 1).sum())
        y0, y1, x0, x1 = sl[0].start, sl[0].stop, sl[1].start, sl[1].stop
        if cnt < 3000 or cnt / ((x1 - x0) * (y1 - y0)) < 0.9:
            continue   # 白邊、膠帶、易碎貼紙
        (backs if (y1 - y0) > 120 else plates).append((x0, y0, x1, y1))
    assert len(backs) == 4 and len(plates) == 4, (backs, plates)
    tall = max(backs, key=lambda q: q[3] - q[1])
    smalls = sorted([q for q in backs if q is not tall], key=lambda q: q[1])
    cells = []
    for bk in [tall] + smalls:
        x0, y0, x1, y1 = bk
        my, mx = (y0 + y1) // 2, (x0 + x1) // 2
        left = runs(dark(px[my, :x0 + 2]))
        assert len(left) >= 2, ("left", bk, left)
        outl = left[-2]                                        # 開口左緣（left[-1] 是側板／背板交界）
        right = runs(dark(px[my, x1 - 2:]))
        rx = x1 - 2 + right[0][0]                              # 開口右緣（黑線的左邊）
        top = runs(dark(px[:y0 + 2, mx]))
        ty = top[-1][1] + 1                                    # 開口上緣（黑線的下面）
        down = runs(dark(px[y1 - 2:, mx]))
        fb = y1 - 2 + (down[0][0] + down[0][1]) / 2.0          # 地板後緣（黑線中間）
        ff = y1 - 2 + down[1][0]                               # 開口下緣＝地板前緣（黑線的上面）
        opening = (outl[1] + 1, ty, rx, ff)
        t = FOOT_DEPTH
        fy = fb + (ff - fb) * t
        fx0 = x0 + (opening[0] - x0) * t
        fx1 = x1 + (opening[2] - x1) * t
        ocx = (opening[0] + opening[2]) / 2
        plate = min(plates, key=lambda p: abs(p[1] - ff) + abs((p[0] + p[2]) / 2 - ocx))
        cells.append(dict(open=opening, back=bk, floor=(fb, ff), foot=((fx0 + fx1) / 2.0, fy), plate=plate))
    return cells


def main(argv):
    src, out, prev = SRC, OUT, None
    i = 0
    while i < len(argv):
        if argv[i] == "--out":
            out = argv[i + 1]
            i += 2
        elif argv[i] == "--preview":
            prev = argv[i + 1]
            i += 2
        else:
            src = argv[i]
            i += 1
    arr = np.array(Image.open(src).convert("RGBA"))
    al = arr[..., 3]
    arr[..., 3] = np.where(al < 8, 0, np.where(al >= 248, 255, al))   # 生圖的 alpha 最高 254、透明處有雜點
    arr[arr[..., 3] == 0] = 0
    ys, xs = np.where(arr[..., 3] > 0)
    # 裁掉透明邊，寬高湊成 4 的倍數（1x 剛好是 2x 的一半）
    bx0, by0, bx1, by1 = xs.min(), ys.min(), xs.max() + 1, ys.max() + 1
    W, H = -(-(bx1 - bx0) // 4) * 4, -(-(by1 - by0) // 4) * 4
    canvas = np.zeros((H, W, 4), np.uint8)
    canvas[:by1 - by0, :bx1 - bx0] = arr[by0:by1, bx0:bx1]
    cells = measure(canvas)
    crop = Image.fromarray(canvas)
    W2, H2 = int(round(W * SCALE_2X)), int(round(H * SCALE_2X))
    img2 = crop.resize((W2, H2), Image.LANCZOS)
    img1 = crop.resize((W2 // 2, H2 // 2), Image.LANCZOS)

    def c2(v):
        return int(round(v * SCALE_2X))

    def r2(q):
        return (c2(q[0]), c2(q[1]), c2(q[2]) - c2(q[0]), c2(q[3]) - c2(q[1]))

    tab = (TAB_SRC[0] - bx0, TAB_SRC[1] - by0, TAB_SRC[2] - bx0, TAB_SRC[3] - by0)
    crown = min(c["open"][1] for c in cells) - CROWN_UP
    lines = ["# 紙箱櫃（tools/shelf_art/shelf_art.py 產生，別手改）。座標＝2x 圖的像素（1x 圖剛好一半；程式用 S/8 換算）",
             "# size 寬 高",
             "# cell 格 開口x y 寬 高 背板x y 寬 高 地板後緣y 地板前緣y 腳底x 腳底y 名牌x y 寬 高（格 0＝右邊高格，1～3＝左邊由上到下）",
             "# tab 收合鈕x y 寬 高；crown 箱子正面上緣y（再上面是蓋子，可以拖著搬家）",
             f"size {W2} {H2}"]
    for k, c in enumerate(cells):
        lines.append("cell %d %s %s %d %d %d %d %s" % (k, " ".join(map(str, r2(c["open"]))), " ".join(map(str, r2(c["back"]))),
                                                       c2(c["floor"][0]), c2(c["floor"][1]), c2(c["foot"][0]), c2(c["foot"][1]),
                                                       " ".join(map(str, r2(c["plate"])))))
    lines.append("tab %s" % " ".join(map(str, r2(tab))))
    lines.append(f"crown {c2(crown)}")
    os.makedirs(os.path.join(out, "1x"), exist_ok=True)
    os.makedirs(os.path.join(out, "2x"), exist_ok=True)
    open(os.path.join(out, "shelf.txt"), "w", encoding="utf-8", newline="\n").write("\n".join(lines) + "\n")
    for r, img in (("1x", img1), ("2x", img2)):
        q = quantize(img)
        q.save(os.path.join(out, r, "box.png"), optimize=True, transparency=q.info["transparency"])
    print("\n".join(lines))
    for r, img in (("1x", img1), ("2x", img2)):
        f = os.path.join(out, r, "box.png")
        A, Q = np.array(img).astype(int), np.array(Image.open(f).convert("RGBA")).astype(int)
        vis = A[..., 3] > 128
        err = np.abs(Q - A)[vis][:, :3].max(1)
        print(f, os.path.getsize(f), Image.open(f).size, "誤差 p99=%d max=%d" % (np.percentile(err, 99), err.max()))
    if prev:
        os.makedirs(prev, exist_ok=True)
        v = Image.new("RGBA", img2.size, (91, 125, 168, 255))
        v.alpha_composite(Image.open(os.path.join(out, "2x", "box.png")).convert("RGBA"))
        d = ImageDraw.Draw(v)

        def box(q, col):
            d.rectangle((q[0], q[1], q[0] + q[2] - 1, q[1] + q[3] - 1), outline=col, width=1)
        for c in cells:
            box(r2(c["open"]), (0, 200, 0))
            box(r2(c["back"]), (0, 90, 255))
            box(r2(c["plate"]), (240, 200, 0))
            fx, fy = c2(c["foot"][0]), c2(c["foot"][1])
            d.line((fx - 20, fy, fx + 20, fy), fill=(255, 0, 0), width=1)
            d.line((fx, fy - 6, fx, fy + 6), fill=(255, 0, 0), width=1)
        box(r2(tab), (255, 0, 255))
        d.line((0, c2(crown), W2, c2(crown)), fill=(255, 0, 255), width=1)
        v.save(os.path.join(prev, "shelf_verify.png"))


if __name__ == "__main__":
    main(sys.argv[1:])
