"""公仔櫃 Desk Pals：公開版（public）與個人版（personal）。

個人版＝repo 裡的原始碼本身（全部角色）。公開版（上架 Microsoft Store／Steam／公開下載用）只有原創的
續命小隊＋使用者自己做的公仔，由這支從原始碼「減掉」同人角色產生，不另外維護一份：

  1. 整個檔案拿掉：FAN_FILES（同人角色的資料、動作、串場都放在這幾個檔）。
  2. 其他檔案裡的標記（標記本身是註解，個人版編譯起來完全不受影響）：
       // <fan>  …  // </fan>     整段拿掉（# <fan> / <!-- <fan> --> 也可以）
       某一行程式 … //@fan          這一行拿掉（行尾的註解以 @fan 結尾）
       // <public> 程式碼            公開版才有的那一行（個人版裡只是註解）
  3. 留下來的註解裡如果提到同人角色，那段註解拿掉（只動註解，程式碼一律靠上面的標記）。
  4. 最後用 guard() 掃一遍：任何同人角色的名字、id、口頭禪出現在公開版的原始碼、二進位檔、vsix／msix 裡 → 失敗。

用法：
  python -I tools/variant.py public [輸出資料夾]      → 產生公開版的 extension/（預設 build/public/extension），順便 guard
  python -I tools/variant.py guard 路徑…              → 掃檔案／資料夾／.vsix／.msix／.zip／.exe（找到就 exit 1）
"""
import io
import json
import os
import re
import shutil
import sys
import zipfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# 同人角色整個檔案（公開版不帶）
FAN_FILES = {
    "extension/desktop/DeskPals.Fan.cs",      # 經典一櫃、天線寶寶一櫃
    "extension/desktop/DeskPals.Pikmin.cs",   # 皮克敏一櫃
    "mac/src/50_pikmin.swift",
    "mac/src/58_fan.swift",
}
FAN_IDS = {"spidey", "po", "stitch", "hangyodon", "tinky", "dipsy", "laalaa", "pkred", "pkyellow", "pkblue"}
FAN_LINEUPS = {"classic", "teletubbies", "pikmin"}
SKIP_NAMES = {"SpideyDesktop", "DeskPals", ".DS_Store"}   # 編譯產物、雜檔（同 build_vsix.py）

# ---------------------------------------------------------------- guard
# 同人角色的名字、id、口頭禪、版權方。大小寫不分。
FAN_TERMS = [
    r"spidey", r"spider", r"stitch", r"hangyodon", r"tinky", r"dipsy", r"laa-?laa", r"teletubb", r"tubby", r"tubbies",
    r"pikmin", r"pkred", r"pkyellow", r"pkblue", r"thwip", r"eh-oh", r"ohana", r"aloha", r"ih-ih",
    r"marvel", r"disney", r"sanrio", r"nintendo",
    r"小波", r"史迪", r"漢頓", r"人魚", r"丁丁", r"迪西", r"拉拉(?!你)", r"天線寶寶", r"太陽寶寶", r"皮克敏", r"蜘蛛", r"噗咿",
    r"嘟嘟糊", r"三麗鷗", r"任天堂", r"漫威", r"迪士尼", r"休息花", r"魔法袋",
]
# 小波的 id「po」太短不能整個字串掃，只抓當成 id／名字／工廠用的寫法（區分大小寫）
FAN_TERMS_CS = [r"[\"']po[\"']", r"\bPo\(", r"\bPo\b(?!['’]?s\b)"]
# 不是角色內容、而是跨元件的基礎設施名稱（舊版「Spidey 小夥伴」留下的資料夾／socket／pipe／LaunchAgent／環境變數）：
# Mac 的 VS Code 擴充套件、獨立版 .app、claude-hook.js 都靠這幾個名字找到彼此，改名會斷線，所以放行（只放行這幾個完整的寫法）
INFRA_ALLOW = [r"SpideyDesktop", r"spidey\.sock", r"spidey-pet", r"SPIDEY_[A-Z_]+", r"spidey-desktop\.(?:log|sh)"]

_fan_re = re.compile("|".join(FAN_TERMS), re.I)
_fan_cs_re = re.compile("|".join(FAN_TERMS_CS))
_allow_re = re.compile("|".join(INFRA_ALLOW))


def fan_hits(text):
    """回傳文字裡的同人字眼（已扣掉放行的基礎設施名稱）"""
    t = _allow_re.sub(" ", text)
    return [m.group(0) for m in _fan_re.finditer(t)] + [m.group(0) for m in _fan_cs_re.finditer(t)]


# 二進位檔：.NET 字串常數是 UTF-16LE、識別字是 UTF-8；Swift／一般檔是 UTF-8。只掃夠長、不會誤判的字。
BIN_TERMS = ["Spidey", "spidey", "Stitch", "stitch", "Hangyodon", "hangyodon", "Tinky", "tinky", "Dipsy", "dipsy", "LaaLaa", "laalaa",
             "Teletubb", "Tubby", "tubby", "Pikmin", "pikmin", "pkred", "pkyellow", "pkblue", "Thwip", "Eh-oh", "Ohana", "Aloha",
             "FramePo", "PoBall", "小波", "史迪", "漢頓", "丁丁", "迪西", "天線寶寶", "太陽寶寶", "皮克敏", "蜘蛛", "噗咿", "休息花"]
BIN_ALLOW = ["SpideyDesktop", "spidey.sock", "spidey-pet", "SPIDEY_FORCE_DARK", "spidey-desktop.log", "spidey-desktop.sh"]


def bin_hits(data):
    hits = []
    for enc in ("utf-8", "utf-16-le"):
        d = data
        for a in BIN_ALLOW:
            d = d.replace(a.encode(enc), b" " * len(a.encode(enc)))
        for t in BIN_TERMS:
            if t.encode(enc) in d:
                hits.append(f"{t} ({enc})")
    return hits


TEXT_EXT = {".cs", ".swift", ".js", ".html", ".json", ".md", ".ps1", ".sh", ".py", ".txt", ".xml", ".plist", ".iss", ".isl", ".svg",
            ".vsixmanifest", ".manifest", ".ini", ".yml"}
ZIP_EXT = {".vsix", ".msix", ".zip", ".appx"}


def _scan_bytes(name, data, problems):
    ext = os.path.splitext(name)[1].lower()
    if ext in ZIP_EXT:
        with zipfile.ZipFile(io.BytesIO(data)) as z:
            for n in z.namelist():
                if n.endswith("/"):
                    continue
                _scan_bytes(name + "!/" + n, z.read(n), problems)
        return
    hits = fan_hits(name)
    if hits:
        problems.append((name, 0, "file name: " + ", ".join(sorted(set(hits)))))
    if ext in TEXT_EXT or ext == "" and b"\0" not in data[:4096]:
        try:
            text = data.decode("utf-8-sig")
        except UnicodeDecodeError:
            text = None
        if text is not None:
            for i, ln in enumerate(text.split("\n"), 1):
                h = fan_hits(ln)
                if h:
                    problems.append((name, i, ", ".join(sorted(set(h))) + "  | " + ln.strip()[:160]))
            return
    h = bin_hits(data)
    if h:
        problems.append((name, 0, "binary: " + ", ".join(h)))


def guard(paths, quiet=False):
    problems, n = [], 0
    for p in paths:
        if os.path.isdir(p):
            for base, dirs, files in os.walk(p):
                dirs.sort()
                for f in sorted(files):
                    full = os.path.join(base, f)
                    n += 1
                    _scan_bytes(os.path.relpath(full, os.path.dirname(os.path.abspath(p))).replace(os.sep, "/"), open(full, "rb").read(), problems)
        elif os.path.isfile(p):
            n += 1
            _scan_bytes(p.replace(os.sep, "/"), open(p, "rb").read(), problems)
        else:
            problems.append((p, 0, "missing"))
    for name, line, what in problems:
        print(f"FAN CONTENT {name}:{line}: {what}")
    if not quiet:
        print(f"guard: {n} file(s) checked, {len(problems)} problem(s)")
    return not problems


# ---------------------------------------------------------------- 標記、註解
_region_open = re.compile(r"^\s*(?://|#|<!--)\s*<fan>\s*(?:-->)?\s*$")
_region_close = re.compile(r"^\s*(?://|#|<!--)\s*</fan>\s*(?:-->)?\s*$")
_public_line = re.compile(r"^(\s*)(?://|#)\s*<public>\s?(.*)$")
_fan_line = re.compile(r"(?://|#).*@fan\s*$")


def comment_start(line, lang, state):
    """回傳 (註解開始的 index 或 -1, 下一行開始時的字串狀態)。state：None／'tpl'（JS 樣板字串）／'ml'（Swift 三引號）"""
    i, n = 0, len(line)
    while i < n:
        c = line[i]
        if state == "tpl":
            if c == "\\":
                i += 2
                continue
            if c == "`":
                state = None
            i += 1
            continue
        if state == "ml":
            if line.startswith('"""', i):
                state = None
                i += 3
                continue
            i += 1
            continue
        if lang == "hash":
            if c == "#":
                return i, state
            if c in "\"'":
                j = line.find(c, i + 1)
                i = n if j < 0 else j + 1
                continue
            i += 1
            continue
        if line.startswith("//", i):
            return i, state
        if lang == "swift" and line.startswith('"""', i):
            state = "ml"
            i += 3
            continue
        if lang == "js" and c == "`":
            state = "tpl"
            i += 1
            continue
        if c == '"' or (c == "'" and lang in ("js", "cs")):
            j = i + 1
            while j < n:
                if line[j] == "\\":
                    j += 2
                    continue
                if line[j] == c:
                    break
                j += 1
            i = j + 1
            continue
        i += 1
    return -1, state


def lang_of(path):
    ext = os.path.splitext(path)[1].lower()
    return {".cs": "cs", ".swift": "swift", ".js": "js", ".html": "js", ".ps1": "hash", ".sh": "hash", ".py": "hash"}.get(ext)


def to_public(text, path, linemap=None):
    """把一份原始碼轉成公開版（linemap：給一個 list，會依序填入每一行公開版對應的原始行號）"""
    lang = lang_of(path)
    out, in_fan, state, start = [], False, None, 0
    lines = text.split("\n")
    for no, ln in enumerate(lines, 1):
        if _region_open.match(ln):
            if in_fan:
                raise SystemExit(f"{path}:{no}: nested <fan>")
            in_fan, start = True, no
            continue
        if _region_close.match(ln):
            if not in_fan:
                raise SystemExit(f"{path}:{no}: </fan> without <fan>")
            in_fan = False
            continue
        if in_fan:
            continue
        m = _public_line.match(ln)
        if m:
            ln = m.group(1) + m.group(2)
        elif lang and state is None and _fan_line.search(ln):
            ci, _ = comment_start(ln, lang, None)
            if ci >= 0 and _fan_line.search(ln[ci:]):
                continue
        if lang:
            ci, state2 = comment_start(ln, lang, state)
            if ci >= 0 and fan_hits(ln[ci:]):
                code = ln[:ci].rstrip()
                state = state2
                if not code.strip():
                    continue          # 整行都是提到同人角色的註解
                ln = code
            else:
                state = state2
        out.append(ln)
        if linemap is not None:
            linemap.append(no)
    if in_fan:
        raise SystemExit(f"{path}:{start}: <fan> without </fan>")
    return "\n".join(out)


# ---------------------------------------------------------------- package.json
PUBLIC_PKG_TEXT = {
    "description": "右下角一個公仔櫃（或一顆蛋），住著原創的「續命小隊」：半糖、醒醒、糰糰、貼貼；也可以把你家的貓狗（或任何照片）變成桌面公仔。"
                   "選一隻出來，他就在整個螢幕陪你：散步、爬視窗、催你休息、提醒開會和死線。",
    "deskPals.lineup": "公仔櫃：換一櫃（續命小隊／我的櫃）",
}


def public_package_json(text):
    pkg = json.loads(text)
    pkg["description"] = PUBLIC_PKG_TEXT["description"]
    for c in pkg["contributes"]["commands"]:
        if c["command"] in PUBLIC_PKG_TEXT:
            c["title"] = PUBLIC_PKG_TEXT[c["command"]]
    props = pkg["contributes"]["configuration"]["properties"]
    for key, drop in (("deskPals.character", FAN_IDS), ("deskPals.lineup", FAN_LINEUPS)):
        p = props[key]
        keep = [i for i, v in enumerate(p["enum"]) if v not in drop]
        p["enum"] = [p["enum"][i] for i in keep]
        p["enumDescriptions"] = [p["enumDescriptions"][i] for i in keep]
        if p["default"] in drop:
            raise SystemExit(f"package.json: {key} default {p['default']} is a fan value")
    props["deskPals.lineup"]["description"] = props["deskPals.lineup"]["description"]
    return json.dumps(pkg, ensure_ascii=False, indent="\t") + "\n"


# ---------------------------------------------------------------- 產生公開版
def rel(p):
    return os.path.relpath(p, ROOT).replace(os.sep, "/")


def public_swift():
    sys.path.insert(0, os.path.join(ROOT, "mac"))
    import assemble  # noqa: E402
    files = [f for f in assemble.source_files() if rel(f) not in FAN_FILES]
    return assemble.assemble(files, lambda text, f: to_public(text, f))


def build_public(out_ext):
    src_ext = os.path.join(ROOT, "extension")
    if os.path.isdir(out_ext):
        shutil.rmtree(out_ext)
    for base, dirs, files in os.walk(src_ext):
        dirs.sort()
        for f in sorted(files):
            full = os.path.join(base, f)
            r = rel(full)
            if f in SKIP_NAMES or r in FAN_FILES or r == "extension/desktop/DeskPals.swift":
                continue
            dst = os.path.join(out_ext, os.path.relpath(full, src_ext))
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            if r == "extension/package.json":
                text = public_package_json(open(full, encoding="utf-8").read())
            elif lang_of(f):
                raw = open(full, "rb").read()
                bom = raw.startswith(b"\xef\xbb\xbf")
                text = to_public(raw.decode("utf-8-sig"), r)
                if bom:
                    text = "﻿" + text
            else:
                shutil.copyfile(full, dst)
                continue
            with open(dst, "w", encoding="utf-8", newline="") as fh:
                fh.write(text)
    swift = os.path.join(out_ext, "desktop", "DeskPals.swift")
    with open(swift, "w", encoding="utf-8", newline="\n") as fh:
        fh.write(public_swift())
    return out_ext


def main(argv):
    for st in (sys.stdout, sys.stderr):
        if hasattr(st, "reconfigure"):
            st.reconfigure(encoding="utf-8", errors="replace")
    if len(argv) >= 1 and argv[0] == "public":
        out = argv[1] if len(argv) > 1 else os.path.join(ROOT, "build", "public", "extension")
        build_public(out)
        print(f"public variant → {out}")
        ok = guard([out])
        return 0 if ok else 1
    if len(argv) >= 2 and argv[0] == "guard":
        return 0 if guard(argv[1:]) else 1
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
