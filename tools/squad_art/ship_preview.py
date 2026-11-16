import os, sys, json, io, math, numpy as np
sys.dont_write_bytecode=True
from PIL import Image, ImageDraw, ImageFont
import importlib.util
spec=importlib.util.spec_from_file_location('br','battery_render.py')
K=['stand','walk1','walk2','jump','sleep','happy','held','sit','grab','push','cry','blown','sig1','sig2','surprised','pout']
LAB=dict(stand="站",walk1="走1",walk2="走2",jump="跳",sleep="睡",happy="開心",held="被抓",sit="坐",grab="搶游標",push="推視窗",cry="抱錢包哭",blown="被震飛",surprised="嚇到",pout="嘟嘴")
SIG={"duoduo":("躲起來","箱子逃跑"),"meidian":("充電","沒電攤平"),"cici":("開花","炸毛")}
NAMES={"duoduo":"躲躲","meidian":"沒電","cici":"刺刺"}
SP=r"C:\tmp\dp\squad2\sprites"; BA=r"C:\tmp\dp\squad2\battery"; SH=r"C:\tmp\dp\squad2\ship"
M=json.load(open(os.path.join(SP,'manifest.json'),encoding='utf-8'))
LV=json.load(open(os.path.join(BA,'levels.json'),encoding='utf-8'))
# ---- 匯入 battery_render 的 render/ramp（不重跑它的主程式）
src=open('battery_render.py',encoding='utf-8').read().split('levels={}')[0]
ns={}; exec(src,ns); render=ns['render']; ramp=ns['ramp']; GREEN=ns['GREEN']
def quant_save(im,path):
    q=im.quantize(256,method=Image.Quantize.FASTOCTREE,dither=Image.Dither.NONE)
    q.save(path,optimize=True)
tot=0
for c in ['duoduo','meidian','cici']:
    for rs in ('1x','2x'):
        od=os.path.join(SH,c,rs); os.makedirs(od,exist_ok=True)
        for k in K:
            if c=='meidian':
                quant_save(Image.open(os.path.join(BA,rs,k+'.png')).convert('RGBA'),os.path.join(od,k+'.png'))
                Image.open(os.path.join(BA,rs,k+'.liquid.png')).save(os.path.join(od,k+'.liquid.png'),optimize=True)
            else:
                quant_save(Image.open(os.path.join(SP,c,rs,k+'.png')).convert('RGBA'),os.path.join(od,k+'.png'))
for root,_,fs in os.walk(SH):
    for f in fs: tot+=os.path.getsize(os.path.join(root,f))
man={}
for c in M:
    man[c]=dict(name=NAMES[c],target_h_1x=M[c]['target_h_1x'],canvas_1x=M[c]['canvas_1x'],canvas_2x=M[c]['canvas_2x'],
               anchor_1x=M[c]['anchor_1x'],anchor_2x=M[c]['anchor_2x'],R_1x=4,R_2x=8,
               frames={k:dict(label=(SIG[c][0] if k=='sig1' else SIG[c][1] if k=='sig2' else LAB[k]),bbox_1x=M[c]['frames'][k]['bbox_1x'],scale_vs_stand_raw=M[c]['frames'][k]['scale_vs_stand']) for k in K})
man['meidian']['battery']=dict(mask="<frame>.liquid.png（8-bit 灰階＝液體覆蓋率 w）；底圖已清成奶油色",cream=[251,240,223],levels_json="battery/levels.json")
json.dump(man,open(os.path.join(SH,'manifest.json'),'w',encoding='utf-8'),ensure_ascii=False,indent=1)
print('ship total bytes',tot)

def frame_img(c,rs,k,L=0.3):
    if c!='meidian': return Image.open(os.path.join(SH,c,rs,k+'.png')).convert('RGBA')
    base=np.array(Image.open(os.path.join(SH,c,rs,k+'.png')).convert('RGBA'))
    w=np.array(Image.open(os.path.join(SH,c,rs,k+'.liquid.png'))).astype(float)/255
    lv=LV['levels'][rs][k]
    if k=='sig1': L=0.6; col=GREEN
    elif k=='sig2': L=0.03; col=ramp(L)
    else: col=ramp(L)
    return Image.fromarray(render(base,w,lv['table'][int(round(L*100))],lv['band'],col,0))

# ---- 舊的像素版續命小隊（尺寸參考；那份程式已經從 repo 拿掉，有舊版的原始碼才畫）
OLD_ART = os.environ.get("OLD_ORIGINAL_ART", "")
def old_pal(pid, ps):
    sys.path.insert(0, OLD_ART)
    import final_art as A
    from rend import draw_grid
    spec2 = importlib.util.spec_from_file_location('poses', os.path.join(OLD_ART, 'poses.py'))
    P = importlib.util.module_from_spec(spec2); spec2.loader.exec_module(P)
    p = A.PALS[pid]; rows = P.frame(p); pal = P.pal_of(pid)
    w = max(len(r) for r in rows); h = len(rows)
    im = Image.new('RGBA', (w * ps + 2 * ps, h * ps + 2 * ps), (0, 0, 0, 0))
    draw_grid(im, rows, pal, ps, ps, ps)
    return im

FT=ImageFont.truetype("C:/Windows/Fonts/msjhbd.ttc",16); FS=ImageFont.truetype("C:/Windows/Fonts/msjh.ttc",12)
def sheet(rs,out,scale_note):
    sc=1 if rs=='1x' else 2
    cells={c:M[c][f'canvas_{rs}'] for c in M}
    cw=max(v[0] for v in cells.values()); ch=max(v[1] for v in cells.values())
    W=40+16*(cw+6)+20; rowh=ch+22
    H=60+2*(3*rowh+ (90*sc) +30)
    img=Image.new('RGB',(W,H),(0,0,0)); d=ImageDraw.Draw(img)
    for half,(bgc,fg,title) in enumerate([((233,238,243),(60,60,70),'淺色桌布'),((30,34,46),(220,220,230),'深色桌布')]):
        y0=half*(H//2)
        d.rectangle([0,y0,W,y0+H//2],fill=bgc)
        d.text((12,y0+8),f"{title}｜實際大小 {scale_note}（沒電：一般動作 30%、充電 60%、攤平 3%）",font=FT,fill=fg)
        y=y0+34
        # 舊的續命小隊做尺寸對照
        d.text((12,y),"現在的續命小隊（像素，16 格高）",font=FS,fill=fg)
        x=40
        for pid in (['boba','coffee','onigiri','sticky'] if OLD_ART else []):
            o=old_pal(pid,4*sc); img.paste(o,(x,y+16+90*sc-o.height-6),o); x+=o.width+10
        y+=90*sc+16
        for c in ['duoduo','meidian','cici']:
            d.text((12,y),NAMES[c],font=FS,fill=fg)
            cwc,chc=cells[c]
            for i,k in enumerate(K):
                im=frame_img(c,rs,k)
                x=40+i*(cw+6)+(cw-cwc)//2
                img.paste(im,(x,y+4+(ch-chc)),im)
                lab=(SIG[c][0] if k=='sig1' else SIG[c][1] if k=='sig2' else LAB[k])
                if c=='cici': d.text((40+i*(cw+6)+2,y+ch+6),lab,font=FS,fill=fg)
            y+=rowh
    img.save(out)
sheet('1x',r"C:\tmp\dp\squad2\preview.png","100% 縮放（1x）")
sheet('2x',r"C:\tmp\dp\squad2\preview_2x.png","200% 縮放／Retina（2x）")
