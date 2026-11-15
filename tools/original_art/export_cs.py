"""Generate the C# art block for DeskPals.Original.cs from final_art.py and splice it between the markers.
usage: python tools/original_art/export_cs.py extension/desktop/DeskPals.Original.cs   (no argument: print the block)"""
import sys
import final_art as A

BEGIN = "        // ==== 像素圖（由 tools/original_art/final_art.py 產生，別手改）===="
END = "        // ==== 像素圖結束 ===="
RESERVED = set("SWYPB12345678")   # Pal.Shared() 會蓋掉這些（配件、共用色），不能當身體顏色
CR, LF = "\r", "\n"


def cs_arr(rows):
    return "new string[] { " + ", ".join('"' + r + '"' for r in rows) + " }"


def hexint(h):
    return "0x" + h.lstrip("#").upper()


def gen():
    out = [BEGIN]
    for pid, p in A.PALS.items():
        fn = "Art" + pid[0].upper() + pid[1:]
        out.append(f"        static void {fn}(Pal p)")
        out.append("        {")
        day = dict(p["pal"]); day.update(A.EXTRA[pid])
        night = dict(p["night"]); night.update(A.EXTRA_NIGHT[pid])
        for c in sorted(day):
            if c in RESERVED:
                raise SystemExit(f"{pid}: palette char {c} is reserved")
            out.append(f"            p.Col('{c}', {hexint(day[c])}, {hexint(night.get(c, day[c]))});")
        for k, v in p.items():
            if isinstance(v, list):
                out.append(f'            p.Art["{k}"] = {cs_arr(v)};')
        for k, v in p["FACES"].items():
            out.append(f'            p.Art["F_{k}"] = {cs_arr(v)};')
        for nm, pr in A.PROPS.items():
            if pr["owner"] == pid:
                out.append(f'            p.Art["{nm}"] = {cs_arr(pr["rows"])};')
        out.append(f"            p.FaceRow = {p['FACE_ROW']};")
        out.append("        }")
    out.append(END)
    return LF.join(out)


def splice(path):
    raw = open(path, "rb").read().decode("utf-8-sig")
    crlf = (CR + LF) in raw
    src = raw.replace(CR + LF, LF)
    a = src.index(BEGIN); b = src.index(END) + len(END)
    src = src[:a] + gen() + src[b:]
    if crlf:
        src = src.replace(LF, CR + LF)
    open(path, "w", encoding="utf-8-sig", newline="").write(src)


if __name__ == "__main__":
    if len(sys.argv) > 1:
        splice(sys.argv[1])
    else:
        print(gen())
