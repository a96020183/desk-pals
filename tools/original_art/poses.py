"""Pose sheet for 續命小隊: every pal × every pose, day and night, plus props — the design sheet the user judges."""
import sys
from PIL import Image, ImageDraw
from rend import draw_grid, FONT, FONT_S, hexc
import importlib
import final_art as A
importlib.reload(A)


def frame(p, head="HEAD", body="BODY", legs="LEGS_A", face=None):
    rows = list(p.get(head, p["HEAD"])) + list(p.get(body, p["BODY"])) + list(p.get(legs, p["LEGS_A"]))
    if face:
        fr = p["FACES"][face]
        for i, r in enumerate(fr):
            if p["FACE_ROW"] + i < len(rows) and len(r) == len(rows[p["FACE_ROW"] + i]):
                rows[p["FACE_ROW"] + i] = r
    return rows


def pal_of(pid, night=False):
    p = A.PALS[pid]
    d = dict(p["night"] if night else p["pal"])
    d.update((A.EXTRA_NIGHT if night else A.EXTRA)[pid])
    d.update(S="#E23B3B", W="#FFFFFF", Y="#F5C842", P="#FF8FB0", B="#B8D6FF")
    d.update({"1": "#D9A55B", "2": "#A8743A"})
    return d


POSES = [
    ("站著", dict()),
    ("走路", dict(legs="LEGS_B")),
    ("舉手", dict(head="HEAD_UP", body="BODY_UP")),
    ("抱抱", dict(body="BODY_HUG", face="HAPPY")),
    ("開心", dict(head="HEAD_UP", body="BODY_UP", face="HAPPY")),
    ("睡覺", dict(legs="LEGS_SIT", face="SLEEPY")),
    ("頭暈", dict(face="DIZZY")),
    ("貼玻璃", dict(head="HEAD_UP", body="BODY_UP", face="SQUISH")),
]
SPECIAL = {
    "boba": [("噗珍珠", dict(face="BLOW")), ("擔心", dict(face="WORRY"))],
    "coffee": [("續杯醒了", dict(head="HEAD_UP", body="BODY_UP", face="WIDE")), ("熬夜（晚上）", dict(face="PANDA"))],
    "onigiri": [("嚼嚼", dict(face="CHEW")), ("衝浪", dict(head="HEAD_UP", body="BODY_UP", face="HAPPY"))],
    "sticky": [("慌張", dict(head="HEAD_UP", body="BODY_UP", face="PANIC")), ("寫便條", dict())],
}


def main(out="poses.png", ps=7):
    ids = ["boba", "coffee", "onigiri", "sticky"]
    ncol = len(POSES) + 2 + 1
    cw, ch = 22 * ps, 26 * ps
    img = Image.new("RGB", (ncol * cw + 140, len(ids) * 2 * ch + 60), hexc("#5B7DA8"))
    d = ImageDraw.Draw(img)
    for c, (nm, _) in enumerate(POSES + [("特別 1", 0), ("特別 2", 0), ("午餐", 0)]):
        d.text((140 + c * cw + 8, 8), nm, fill=(255, 255, 255), font=FONT_S)
    for r, pid in enumerate(ids):
        p = A.PALS[pid]
        for night in (False, True):
            y0 = 40 + (r * 2 + (1 if night else 0)) * ch
            if night:
                d.rectangle([0, y0 - 4, img.width, y0 + ch - 6], fill=hexc("#2E3550"))
            d.text((10, y0 + ch // 2 - 20), p["name"] + ("（晚上）" if night else ""), fill=(255, 255, 255), font=FONT)
            pal = pal_of(pid, night)
            poses = POSES + SPECIAL[pid] + [("午餐", dict())]
            for c, (nm, kw) in enumerate(poses):
                rows = frame(p, **kw)
                ox = 140 + c * cw + (cw - len(rows[0]) * ps) // 2
                oy = y0 + ch - 10 - len(rows) * ps
                draw_grid(img, rows, pal, ox, oy, ps)
                # props on the special columns
                def prop(name, col, row, flip=False):
                    pr = A.PROPS[name]["rows"]
                    draw_grid(img, pr, pal, ox + int(col * ps), oy + int(row * ps), ps, flip=flip)
                if pid == "boba" and nm == "噗珍珠":
                    prop("PEARL", 12, -2); prop("PEARL", 16, -6)
                if pid == "coffee" and nm == "續杯醒了":
                    prop("POT", 3, -5)
                if pid == "onigiri" and nm == "衝浪":
                    prop("NORI", 1, len(rows) - 2)
                if pid == "sticky" and nm == "寫便條":
                    prop("MARKER", 11, 12); prop("MINI_NOTE", -6, 8)
                if nm == "午餐":
                    food = {"boba": ("CHICKEN", 11, 11), "coffee": ("CROISSANT", -6, 12), "onigiri": ("BENTO", 9, 12), "sticky": ("RICEBOWL", 10, 12)}[pid]
                    prop(food[0], food[1], food[2])
    img.save(out)
    # props strip
    pimg = Image.new("RGB", (len(A.PROPS) * 16 * ps, 16 * ps), hexc("#5B7DA8"))
    for i, (nm, pr) in enumerate(A.PROPS.items()):
        draw_grid(pimg, pr["rows"], pal_of(pr["owner"]), i * 16 * ps + 10, 10, ps)
    pimg.save("props.png")


if __name__ == "__main__":
    main(*(sys.argv[1:2] or []))
