"""公仔櫃收起來的樣子（以前是像素蛋）：紙箱櫃 → 封好的小紙箱、書包小屋 → 小書包。輸出 1x／2x 的 mini.png ＋ mini.txt。

用法（可重跑）：
  PYTHONPATH=<numpy／scipy 的資料夾> python tools/shelf_art/mini_art.py [--preview 資料夾]

- 原圖不進 repo：Tripo GPT Image（chat_image_2.5_sunburst）生的 2×2 表，每張四個版本，挑一格：
    紙箱：C:\\tmp\\dp\\egg\\gen\\mini_box（參考紙箱櫃定稿，粗黑麥克筆線＋白色貼紙邊）
    書包：C:\\tmp\\dp\\egg\\gen\\mini_bag（參考書包小屋，柔和黏土、沒有黑線）
- 輸出：pals/shelf/{1x,2x}/mini.png、pals/woban/shelf/{1x,2x}/mini.png（量化方法跟 shelf_art.py 一樣：224＋31 色＋透明），
  以及同一個資料夾的 mini.txt：
    lid <y>    蓋子／提把跟下面的分界（2x 圖的像素）：吞公仔、收合動畫時上面那塊往上掀
    name <字>  選單、泡泡裡的叫法（小紙箱／小書包）
    btn <畫風> 櫃子上收合鈕的畫風：ink＝白色貼紙邊＋粗黑線（紙箱櫃）、clay＝紫色黏土（書包小屋）
- 程式把 2x 圖的大小 × S/8 當成收起來的大小（S=4 是 100% 縮放，剛好是 1x 圖）。
- 經典、天線寶寶、皮克敏、自己做的公仔這幾櫃用紙箱櫃，收起來也是小紙箱。
"""
import os
import sys

import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
sys.path.insert(0, HERE)
from shelf_art import quantize  # noqa: E402

PALS = os.path.join(ROOT, "extension", "desktop", "pals")
# 名字, 原圖, 挑哪一格（0 左上、1 右上、2 左下、3 右下）, 2x 圖的高, 蓋子分界（裁好後高度的比例）, 輸出資料夾, 叫法, 收合鈕畫風
JOBS = [
    ("box", r"C:\tmp\dp\egg\gen\mini_box\generated_image_url.png", 0, 140, 0.30, os.path.join(PALS, "shelf"), "小紙箱", "ink"),
    ("bag", r"C:\tmp\dp\egg\gen\mini_bag\generated_image_url.png", 0, 160, 0.36, os.path.join(PALS, "woban", "shelf"), "小書包", "clay"),
]


def cut(src, q):
    arr = np.array(Image.open(src).convert("RGBA"))
    h, w = arr.shape[:2]
    x0, y0 = (q % 2) * w // 2, (q // 2) * h // 2
    a = arr[y0:y0 + h // 2, x0:x0 + w // 2].copy()
    al = a[..., 3].astype(np.int32)
    a[..., 3] = np.where(al < 8, 0, np.where(al >= 248, 255, al)).astype(np.uint8)   # 生圖的 alpha 最高 254、透明處有雜點
    a[a[..., 3] == 0] = 0
    # 只留最大的一塊（去掉角落的雜點）
    from scipy import ndimage as ndi
    lab, n = ndi.label(a[..., 3] > 40)
    if n > 1:
        sizes = ndi.sum(np.ones_like(lab), lab, range(1, n + 1))
        keep = ndi.binary_dilation(lab == 1 + int(np.argmax(sizes)), iterations=3)
        a[~keep] = 0
    ys, xs = np.where(a[..., 3] > 0)
    return Image.fromarray(a[ys.min():ys.max() + 1, xs.min():xs.max() + 1])


def main(argv):
    prev = argv[argv.index("--preview") + 1] if "--preview" in argv else None
    for name, src, q, h2, lid, out, word, btn in JOBS:
        img = cut(src, q)
        w2 = int(round(img.width * h2 / img.height / 2)) * 2   # 偶數：1x 剛好一半
        im2 = img.resize((w2, h2), Image.LANCZOS)
        im1 = img.resize((w2 // 2, h2 // 2), Image.LANCZOS)
        for r, im in (("1x", im1), ("2x", im2)):
            qq = quantize(im)
            f = os.path.join(out, r, "mini.png")
            qq.save(f, optimize=True, transparency=qq.info["transparency"])
            print(f, os.path.getsize(f), qq.size)
        lines = ["# 公仔櫃收起來的樣子（tools/shelf_art/mini_art.py 產生，別手改）。座標＝2x mini.png 的像素",
                 "# lid 蓋子／提把跟下面的分界y（吞公仔時上面那塊往上掀）；name 選單、泡泡裡的叫法；btn 收合鈕畫風（ink 白邊黑線貼紙／clay 黏土）",
                 f"lid {int(round(h2 * lid))}", f"name {word}", f"btn {btn}"]
        open(os.path.join(out, "mini.txt"), "w", encoding="utf-8", newline="\n").write("\n".join(lines) + "\n")
        print("\n".join(lines))
        if prev:
            os.makedirs(prev, exist_ok=True)
            v = Image.new("RGBA", (w2 * 3 + 40, h2 + 20), (91, 125, 168, 255))
            v.alpha_composite(Image.open(os.path.join(out, "2x", "mini.png")).convert("RGBA"), (10, 10))
            v.alpha_composite(Image.open(os.path.join(out, "1x", "mini.png")).convert("RGBA"), (w2 + 20, 10))
            v.save(os.path.join(prev, f"mini_{name}.png"))


if __name__ == "__main__":
    main(sys.argv[1:])
