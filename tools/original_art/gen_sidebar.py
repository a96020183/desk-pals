import json, final_art as A
art={}; pal={}; face={}; size={}
for pid,p in A.PALS.items():
    H=p["HEAD"]; fr=p["FACE_ROW"]
    def fc(name):
        rows=p["FACES"][name]; return rows[:max(0,len(H)-fr)]
    art[pid]={"HEAD":H,"BODY":p["BODY"],"ARMS_UP":p.get("BODY_UP",p["BODY"]),"LEGS_A":p["LEGS_A"],"LEGS_B":p["LEGS_B"],"SLEEPY":fc("SLEEPY"),"HAPPY":fc("HAPPY")}
    halo={"boba":"#FFC58F","coffee":"#A8D8F0","onigiri":"#C8D8B8","sticky":"#F0E0A0"}[pid]
    pal[pid]={"n":p["pal"],"d":p["night"],"halo":halo}
    face[pid]=fr
    rows=len(H)+len(p["BODY"])+len(p["LEGS_A"]); size[pid]=[p["W"]*3,rows*3]
print("// 續命小隊（原創角色，桌面版 DeskPals.Original.cs 同一套像素圖）：半糖、醒醒、糰糰、貼貼")
print("Object.assign(ART, "+json.dumps(art,ensure_ascii=False,separators=(",",":"))+");")
print("Object.assign(PAL, "+json.dumps(pal,ensure_ascii=False,separators=(",",":"))+");")
print("const ORIG = "+json.dumps(size)+";")
