"""續命小隊 — final pixel art (source of truth; exported to C# by export_cs.py).
Each pal: palette (day), parts, faces (rows replacing HEAD from FACE_ROW), props.
Coordinates: every part of one pal has the same width, so frames stack straight."""

PALS = {}

# ======================= 半糖（珍奶）=======================
# 15 wide. Straw (4 rows) sits above the 16-row frame.
BOBA = dict(
    id="boba", name="半糖", W=15, FACE_ROW=8,
    pal=dict(k="#4A2C1C", m="#E8B57C", M="#C98E55", h="#FBEBD4", H="#F3D2A8", j="#2E1C16", Q="#A58472", f="#FFFFFF", F="#FF8FB5",
             s="#FF7AAE", z="#D2508A", e="#2A1810", w="#FFFFFF", b="#F79A9A", o="#7A3A2A", x="#FF6F9C"),
    night=dict(k="#2E1A14", m="#B98A62", M="#946A44", h="#D8C2AE", H="#C2A488", j="#1E120E", Q="#7A6458", f="#E6DDF0", F="#C77AA0",
               s="#D86A9A", z="#A84878", e="#1E120E", w="#F0E8F4", b="#C07A86", o="#5A2A20", x="#C85A80"),
    HEAD=[
        "...........sz..",
        "..........sz...",
        ".........sz....",
        "........sz.....",
        "kkkkkkkkszkkkkk",
        "kfFfFfFszFfFfFk",
        "kkkkkkkkkkkkkkk",
        ".khmmmmmmmmmMk.",
        ".khmwemmmwemMk.",
        ".khmeemmmeemMk.",
        ".khbmmooommbMk.",
        ".khmmmmxmmmmMk.",
    ],
    # 手舉起來：兩隻小手在臉旁邊
    HEAD_UP=[
        "...........sz..",
        "..........sz...",
        ".........sz....",
        "........sz.....",
        "kkkkkkkkszkkkkk",
        "kfFfFfFszFfFfFk",
        "kkkkkkkkkkkkkkk",
        ".khmmmmmmmmmMk.",
        "kkhmwemmmwemMkk",
        "kkhmeemmmeemMkk",
        ".khbmmooommbMk.",
        ".khmmmmxmmmmMk.",
    ],
    BODY=[
        "kkhmmmmmmmmmMkk",
        ".khmmmmmmmmmMk.",
        ".khjQmjQmjQmMk.",
        ".khjjmjjmjjmMk.",
        ".kHHHHHHHHHHHk.",
        "..kkkkkkkkkkk..",
    ],
    BODY_J=[
        "kkhmmmmmmmmmMkk",
        ".khjQmjQmjQmMk.",
        ".khjjmjjmjjmMk.",
        ".khmmmmmmmmmMk.",
        ".kHHHHHHHHHHHk.",
        "..kkkkkkkkkkk..",
    ],
    BODY_UP=[
        ".khmmmmmmmmmMk.",
        ".khmmmmmmmmmMk.",
        ".khjQmjQmjQmMk.",
        ".khjjmjjmjjmMk.",
        ".kHHHHHHHHHHHk.",
        "..kkkkkkkkkkk..",
    ],
    BODY_HUG=[
        "kkhmmmmmmmmmMkk",
        "kkhmmmmmmmmmMkk",
        ".khjQmjQmjQmMk.",
        ".khjjmjjmjjmMk.",
        ".kHHHHHHHHHHHk.",
        "..kkkkkkkkkkk..",
    ],
    LEGS_A=["...kk.....kk...", "...kk.....kk..."],
    LEGS_B=["..kk.......kk..", "..kk.......kk.."],
    LEGS_SIT=["..kkk.....kkk..", "..............."],
    FACES=dict(
        SLEEPY=[".khmmmmmmmmmMk.", ".khmkkmmmkkmMk.", ".khbmmmmmmmbMk.", ".khmmmmommmmMk."],
        HAPPY=[".khmemmmmmemMk.", ".khememmmemeMk.", ".khbmmooommbMk.", ".khmmmmxmmmmMk."],
        DIZZY=[".khmemmmmmemMk.", ".khmmemmmemmMk.", ".khbemmmmmebMk.", ".khmmmooommmMk."],
        SQUISH=[".khmkkmmmkkmMk.", ".khmmkmmmkmmMk.", ".khbmmooommbMk.", ".khmmmooommmMk."],
        BLOW=[".khmwemmmwemMk.", ".khmeemmmeemMk.", ".khbmmmommmbMk.", ".khmmmmommmmMk."],
        WORRY=[".khmwemmmwemMk.", ".khmeemmmeemMk.", ".khbmmmommmbMk.", ".khmmmomommmMk."],
    ),
)
PALS["boba"] = BOBA

# ======================= 醒醒（咖啡馬克杯）=======================
# 16 wide; handle on the right; steam (4 rows) above the frame.
COFFEE = dict(
    id="coffee", name="醒醒", W=17, FACE_ROW=10,
    pal=dict(k="#1E2A3A", t="#4FB6C8", T="#2F8AA0", l="#A8E6EE", w="#FFFFFF", c="#8A5432", C="#5A3018", v="#F2F6FA", V="#C8D4E2",
             e="#1E2A3A", b="#F2A0A0", p="#FFE2C8", d="#2A5A6E", z="#6A4ADA"),
    night=dict(k="#101824", t="#3A8A9E", T="#245E70", l="#7CB4C4", w="#E8F0F8", c="#6A4026", C="#402212", v="#C8D0E8", V="#8E98B8",
               e="#0E1420", b="#B87A8A", p="#D8C0A8", d="#14303E", z="#5A3ABA"),
    HEAD=[
        ".....v.....v.....",
        "....v.....v......",
        ".....V.....V.....",
        "......V.....V....",
        "..kkkkkkkkkkkk...",
        ".kwcccccccccCwk..",
        ".kwccpppcccCCwk..",
        ".kwwCCpcccCCwwk..",
        ".kltttttttttttkkk",
        ".klttttttttttTkTk",
        ".klttwwttttwwtkTk",
        ".klttetttttettkTk",
    ],
    HEAD_UP=[
        ".....v.....v.....",
        "....v.....v......",
        ".....V.....V.....",
        "......V.....V....",
        "..kkkkkkkkkkkk...",
        ".kwcccccccccCwk..",
        ".kwccpppcccCCwk..",
        ".kwwCCpcccCCwwk..",
        "kkltttttttttttkkk",
        "ktltttttttttTTkTk",
        "kklttwwttttwwtkTk",
        ".klttetttttettkTk",
    ],
    STEAM_B=[
        "....v.....v......",
        ".....v.....v.....",
        "....V.....V......",
        ".....V.....V.....",
    ],
    BODY=[
        ".kltbtttttttbtkkk",
        ".kltttttkktttTk..",
        ".klttttttttttTk..",
        "..kTTTTTTTTTTk...",
        "...kkkkkkkkkk....",
    ],
    BODY_UP=[
        ".kltbtttttttbtkkk",
        ".kltttttkktttTk..",
        ".klttttttttttTk..",
        "..kTTTTTTTTTTk...",
        "...kkkkkkkkkk....",
    ],
    BODY_HUG=[
        ".kktbtttttttbkkkk",
        ".ktkkttttttkkTk..",
        ".klttttttttttTk..",
        "..kTTTTTTTTTTk...",
        "...kkkkkkkkkk....",
    ],
    ARMS_UP_L=["k.", "tk", "kt"],          # 左手（舉起來），畫在身體外
    LEGS_A=["....kk....kk.....", "....kk....kk....."],
    LEGS_B=["...kk......kk....", "...kk......kk...."],
    LEGS_SIT=["...kkk....kkk....", "................."],
    FACES=dict(
        WIDE=[".klttwettttwetkTk", ".kltteetttteetkTk", ".kltbtttttttbtkkk"],
        PANDA=[".klttwettttwetkTk", ".kltteetttteetkTk", ".kltbddttttddtkkk"],
        SLEEPY=[".kltttttttttttkTk", ".klttkkttttkktkTk", ".kltbtttttttbtkkk"],
        HAPPY=[".kltteetttteetkTk", ".kltettettettekTk", ".kltbtttttttbtkkk"],
        DIZZY=[".kltteetttttetkTk", ".kltttetttteetkTk", ".kltbtttttttbtkkk"],
        SQUISH=[".klttettttttetkTk", ".kltttettttettkTk", ".kltbtttttttbtkkk"],
    ),
)
PALS["coffee"] = COFFEE

# ======================= 糰糰（三角飯糰）=======================
ONIGIRI = dict(
    id="onigiri", name="糰糰", W=16, FACE_ROW=6,
    pal=dict(k="#2B2B33", r="#FCF9F0", g="#E3DCC8", n="#22302A", N="#45604F", e="#2B2B33", b="#F4A0A0", w="#FFFFFF", u="#E8607E", m="#C04050"),
    night=dict(k="#16161C", r="#D6D4E2", g="#B4B0C4", n="#141C18", N="#2E4036", e="#16161C", b="#B87A90", w="#ECEAF6", u="#B04A68", m="#903040"),
    HEAD=[
        ".......kk.......",
        "......krrk......",
        ".....krrrrk.....",
        "....krrgrrrk....",
        "...krrrrrrrrk...",
        "...krrrrrrgrk...",
        "..krreerreerrk..",
        "..krreerreerrk..",
        ".krrbrrrrrrbrrk.",
        ".krrrrrmmrrrrrk.",
    ],
    HEAD_UP=[
        ".......kk.......",
        "......krrk......",
        ".....krrrrk.....",
        ".kk.krrgrrrk.kk.",
        "krrkrrrrrrrrkrrk",
        ".kkkrrrrrrgrkkk.",
        "..krreerreerrk..",
        "..krreerreerrk..",
        ".krrbrrrrrrbrrk.",
        ".krrrrrmmrrrrrk.",
    ],
    BODY=[
        "krrrrrrrrrrrrrrk",
        "knnnnnnnnnnnnnnk",
        "knNnnnnnnnnnNnnk",
        ".kkkkkkkkkkkkkk.",
    ],
    BODY_BARE=[
        "krrrrrrrrrrrrrrk",
        "krrrrgrrrrrrrgrk",
        "krrgrrrrrgrrrrrk",
        ".kkkkkkkkkkkkkk.",
    ],
    BODY_HUG=[
        "kkkrrrrrrrrrrkkk",
        "krrkknnnnnnkkrrk",
        "knNnnnnnnnnnNnnk",
        ".kkkkkkkkkkkkkk.",
    ],
    LEGS_A=["....kk....kk....", "....kk....kk...."],
    LEGS_B=["...kk......kk...", "...kk......kk..."],
    LEGS_SIT=["...kkk....kkk...", "................"],
    FACES=dict(
        SLEEPY=["..krrrrrrrrrrk..", "..krkkrrrrkkrk..", ".krrbrrrrrrbrrk.", ".krrrrrrrrrrrrk."],
        HAPPY=["..krrerrrrerrk..", "..krerrrrrrerk..", ".krrbrrrrrrbrrk.", ".krrrrrmmrrrrrk."],
        DIZZY=["..krekrrrekrrk..", "..krrerrrrerrk..", ".krrbrrrrrrbrrk.", ".krrrrrmmrrrrrk."],
        SQUISH=["..krkkrrrrkkrk..", "..krrkrrrrkrrk..", ".krrbrrmmrrbrrk.", ".krrrrrmmrrrrrk."],
        CHEW=["..krrewrrewrrk..", "..krreerreerrk..", ".krrbrrrrrrbrrk.", ".krrrrmmmmrrrrk."],
    ),
)
PALS["onigiri"] = ONIGIRI

# ======================= 貼貼（便利貼）=======================
# 16 wide (2 empty cols on the left keep the 12-wide note centred); top-right corner flicks up.
STICKY = dict(
    id="sticky", name="貼貼", W=16, FACE_ROW=6,
    pal=dict(k="#6A5418", y="#FFE45C", g="#F2CC3A", l="#FFF6C8", L="#E8D890", d="#3A3020", p="#FF9AA8", w="#FFFFFF", u="#3F6FD8", b="#2A4FA8"),
    night=dict(k="#3A2E10", y="#D8BC5A", g="#BCA040", l="#E6DCB0", L="#C4B680", d="#221C10", p="#C87A88", w="#E8E4F0", u="#3458A8", b="#203E80"),
    HEAD=[
        "..............kk",
        "............kklk",
        "..kkkkkkkkkkllk.",
        "..kggggggggklk..",
        "..kyyyyyyyyykk..",
        "..kyyyyyyyyyyk..",
        "..kyydyyyydyyk..",
        "..kyydyyyydyyk..",
        "..kypyyyyyypyk..",
        "..kyyyyddyyyyk..",
    ],
    HEAD_UP=[
        "..............kk",
        "............kklk",
        "..kkkkkkkkkkllk.",
        "..kggggggggklk..",
        "..kyyyyyyyyykk..",
        "kkkyyyyyyyyyykkk",
        "kykyydyyyydyykyk",
        ".kkyydyyyydyykk.",
        "..kypyyyyyypyk..",
        "..kyyyyddyyyyk..",
    ],
    FLAP=[
        "................",
        "................",
        "..kkkkkkkkkkkk..",
        "..kggggggggggk..",
        "..kyyyyyyyyyyk..",
    ],
    BODY=[
        "..kyyyyyyyyyyk..",
        ".kkyyyyyyyyyykk.",
        "..kyyyyyyyyyyk..",
        "..kkkkkkkkkkkk..",
    ],
    BODY_HUG=[
        "..kyyyyyyyyyyk..",
        "kkkkyyyyyyyykkkk",
        "..kyyyyyyyyyyk..",
        "..kkkkkkkkkkkk..",
    ],
    LEGS_A=["....kk...kk.....", "....kk...kk....."],
    LEGS_B=["...kk.....kk....", "...kk.....kk...."],
    LEGS_SIT=["...kkk...kkk....", "................"],
    FACES=dict(
        SLEEPY=["..kyyyyyyyyyyk..", "..kyddyyyddyyk..", "..kypyyyyyypyk..", "..kyyyyddyyyyk.."],
        HAPPY=["..kyydyyyydyyk..", "..kydydyydydyk..", "..kypyyyyyypyk..", "..kyyyddddyyyk.."],
        DIZZY=["..kydydyydydyk..", "..kyydyyyydyyk..", "..kydydyydydyk..", "..kyyyyddyyyyk.."],
        SQUISH=["..kyddyyyddyyk..", "..kyydyyyydyyk..", "..kypyyddyypyk..", "..kyyyyddyyyyk.."],
        PANIC=["..kyydyyyydyyk..", "..kyydyyyydyyk..", "..kypyyddyypyk..", "..kyyyddddyyyk.."],
    ),
)
PALS["sticky"] = STICKY

# ======================= 道具（顏色要在主人的調色盤裡；S W Y P B 1-8 是共用色，不能拿來當身體色）=======================
EXTRA = dict(
    boba=dict(G="#F0B248", O="#B8742A", n="#E2C8A0", N="#BFA27A"),
    coffee=dict(g="#DCEBF2", G="#9FB8C8", o="#F2B25E", O="#BC7A30"),
    onigiri=dict(o="#D88A3C", O="#9A5420", G="#6AB04C", x="#B85A3A", X="#8A3E26", y="#FFD84A"),
    sticky=dict(c="#A0623A", C="#6E3E22", r="#FCF9F0", o="#E89A4A"),
)
EXTRA_NIGHT = dict(
    boba=dict(G="#C08A40", O="#8A5420", n="#B49E80", N="#8E785C"),
    coffee=dict(g="#A8B8D0", G="#7088A0", o="#C08A50", O="#8A5428"),
    onigiri=dict(o="#A86A34", O="#6E3C18", G="#4A8040", x="#8A4430", X="#62301E", y="#D8B040"),
    sticky=dict(c="#7A4A2E", C="#4E2C18", r="#D6D4E2", o="#B87A3A"),
)
PROPS = dict(
    PEARL=dict(rows=[".jj.", "jQjj", "jjjj", ".jj."], owner="boba"),
    CHICKEN=dict(rows=[".GOGGG..", "GGGOGGG.", "GOGGGOGk", ".GGOGGGk", "knnnnnnk", "knNnnNnk", "knnnnnnk", ".kkkkkk."], owner="boba"),   # 雞排（紙袋）
    DRINK=dict(rows=["....s.", "...s..", "kkkskk", "kfFfFk", "kmmmMk", "kjmjMk", ".kkkk."], owner="boba"),
    TAG=dict(rows=[".kkkkkkkkkkkk", "kSSSSSSSSSSSk", "kSSSWSWSWWWSk", "kSSSWSWSWSWSk", "kwSSWWWSWWWSk", "kSSSSSWSSSWSk", "kSSSSSWSWWWSk", "kSSSSSSSSSSSk", ".kkkkkkkkkkkk"], owner="boba"),  # 價格牌「49」
    POT=dict(rows=["..kkkk...", ".kkddkk..", "kggggggkk", "kgCCCCgk.k", "kgCCCCgk.k", "kgggggkk..", ".kkkkkk..."], owner="coffee"),  # 咖啡壺
    CROISSANT=dict(rows=["..kkkk..", ".kooOok.", "koOooOok", "kOooOooO", ".kkkkkk."], owner="coffee"),
    PADDLE=dict(rows=[".kkk.", "k111k", "k111k", "k112k", ".k2k.", "..2..", "..2..", "..k.."], owner="onigiri"),   # 飯匙
    BENTO=dict(rows=[".kkkkkkkk.", "kxrrroOrxk", "kxrrroooxk", "kxGGyyrrxk", "kXXXXXXXXk", ".kkkkkkkk."], owner="onigiri"),   # 雞腿便當
    MINI_ONIGIRI=dict(rows=["..k..", ".krk.", "krrrk", "knnnk", ".kkk."], owner="onigiri"),
    NORI=dict(rows=["kkkkkkkkkkkkkk", "knnnnnnnnnnnNk", "kkkkkkkkkkkkkk"], owner="onigiri"),  # 海苔衝浪板
    MARKER=dict(rows=["kuuuubk", "kwwwwbk", ".kkkkk."], owner="sticky"),
    MINI_NOTE=dict(rows=["kkkkkkkkk", "kgggggggk", "kyppyppyk", "kpppppppk", "kpppppppk", "kyppppyyk", "kyyppyyyk", "kkkkkkkkk"], owner="sticky"),
    NOTE_BANG=dict(rows=["kkkkkkkkk", "kgggggggk", "kyyyuyyyk", "kyyyuyyyk", "kyyyuyyyk", "kyyyyyyyk", "kyyyuyyyk", "kkkkkkkkk"], owner="sticky"),
    NOTE_HOME=dict(rows=["kkkkkkkkk", "kgggggggk", "kyyyuyyyk", "kyyuyuyyk", "kyuyyyuyk", "kyuyuyuyk", "kyuuuuuyk", "kkkkkkkkk"], owner="sticky"),
    NOTE_ZZ=dict(rows=["kkkkkkkkk", "kgggggggk", "kuuuuyyyk", "kyyuyyyyk", "kyuyyuuuk", "kuuuuyuyk", "kyyyyuuuk", "kkkkkkkkk"], owner="sticky"),
    NOTE_CHECK=dict(rows=["kkkkkkkkk", "kgggggggk", "kyyyyyyuk", "kyyyyyuyk", "kuyyyuyyk", "kyuyuyyyk", "kyyuyyyyk", "kkkkkkkkk"], owner="sticky"),
    NOTE_DRINK=dict(rows=["kkkkkkkkk", "kgggggggk", "kyuuuuuyk", "kyyyyyyyk", "kyuuuuyyk", "kyyyyyyyk", "kyuuuyyyk", "kkkkkkkkk"], owner="sticky"),
    RICEBOWL=dict(rows=["..cCcC..", ".rcCcCr.", "kwwwwwwk", ".kwuuwk.", "..kkkk.."], owner="sticky"),   # 滷肉飯
)
