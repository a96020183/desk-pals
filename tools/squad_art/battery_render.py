# 沒電：執行時重新上色的參考實作（C#／Swift 照這個寫）＋ 電量表 levels.json ＋ 示意圖
import os, json, math, numpy as np
from PIL import Image, ImageDraw, ImageFont
B=r"C:\tmp\dp\squad2\battery"
K=['stand','walk1','walk2','jump','sleep','happy','held','sit','grab','push','cry','blown','sig1','sig2','surprised','pout']
CREAM=np.array([251,240,223],float)
RED=np.array([232,58,50.]); AMBER=np.array([245,178,35.]); GREEN=np.array([76,192,56.])
STOPS=[(0,RED),(0.20,RED),(0.35,AMBER),(0.55,AMBER),(0.70,GREEN),(1.0,GREEN)]
def ramp(L):
    for (a,ca),(b,cb) in zip(STOPS,STOPS[1:]):
        if L<=b: t=0 if b==a else (L-a)/(b-a); return ca+(cb-ca)*t
    return STOPS[-1][1]
def level_table(w):
    """液面永遠水平：由下往上累積遮罩面積，L% 的液面 y＝下方面積剛好是 L% 的那條線（傾斜、躺平都適用）"""
    rows=w.sum(1)                     # 每列的液體面積（w 是 0..1）
    tot=rows.sum(); H=len(rows)
    cum=np.cumsum(rows[::-1])[::-1]   # cum[y]＝y 列以下（含）的面積
    ys=np.nonzero(rows>0)[0]; ytop,ybot=int(ys.min()),int(ys.max())+1
    tab=[]
    for i in range(101):
        target=tot*i/100
        # 找 yL：yL 以下面積＝target（列內線性內插）
        y=ybot
        acc=0.0
        while y>ytop and acc+rows[y-1]<target: acc+=rows[y-1]; y-=1
        frac=0 if rows[y-1]==0 or y<=ytop else (target-acc)/rows[y-1]
        tab.append(round(float(y-frac),2))
    return ytop,ybot,tab
def render(base,w,yL,band,color,pulse=0.0):
    """base: HxWx4（液體已清成奶油色）、w: HxW 0..1、yL: 液面 y（像素，小數）、band: 液面亮帶厚度"""
    H,W=w.shape
    y=np.arange(H)[:,None]+0.0
    cov=np.clip(y+1-yL,0,1)                 # 這一列有多少在液面以下（液面反鋸齒）
    inband=np.clip((yL+band)-y,0,1)*(cov>0)  # 液面下 band 像素內＝亮帶
    c=np.array(color)*(1+pulse)
    hi=c+(255-c)*0.45
    liquid=c[None,None,:]*(1-inband[...,None])+hi[None,None,:]*inband[...,None]
    tgt=CREAM[None,None,:]*(1-cov[...,None])+liquid*cov[...,None]
    out=base.astype(float).copy()
    out[...,:3]+= w[...,None]*(tgt-CREAM[None,None,:])
    out[...,:3]=np.clip(out[...,:3],0,255)
    return out.astype(np.uint8)
levels={}
for rs in ('1x','2x'):
    levels[rs]={}
    for k in K:
        w=np.array(Image.open(os.path.join(B,rs,f'{k}.liquid.png'))).astype(float)/255
        ytop,ybot,tab=level_table(w)
        band=max(1.0,(ybot-ytop)*0.06) if k not in ('sleep','sig2') else max(1.0,(ybot-ytop)*0.1)
        levels[rs][k]=dict(yTop=ytop,yBottom=ybot,band=round(band,2),table=tab)
json.dump(dict(note="table[i]＝電量 i% 時的液面 y（畫布像素，往下為正；y 以下為液體）。液面永遠水平（重力），所以躺平／被震飛也成立。",
               colors=dict(cream=CREAM.tolist(),red=RED.tolist(),amber=AMBER.tolist(),green=GREEN.tolist(),stops=[[a,c.tolist()] for a,c in STOPS],band_mix_white=0.45),
               levels=levels),open(os.path.join(B,'levels.json'),'w',encoding='utf-8'),ensure_ascii=False,indent=0)

# ---------- 示意圖 ----------
FT=ImageFont.truetype("C:/Windows/Fonts/msjhbd.ttc",26); FS=ImageFont.truetype("C:/Windows/Fonts/msjh.ttc",19)
def get(rs,k,L,charging=False,phase=0.0):
    base=np.array(Image.open(os.path.join(B,rs,f'{k}.png')).convert('RGBA'))
    w=np.array(Image.open(os.path.join(B,rs,f'{k}.liquid.png'))).astype(float)/255
    lv=levels[rs][k]; yL=lv['table'][int(round(L*100))]
    if charging: color=GREEN; pulse=0.10*math.sin(phase*2*math.pi)
    else: color=ramp(L); pulse=0
    return Image.fromarray(render(base,w,yL,lv['band'],color,pulse))
SC=1.5
cols=[("10%",0.10,False,0),("50%",0.50,False,0),("90%",0.90,False,0),("充電中 50%（亮）",0.5,True,0.25),("充電中 50%（暗）",0.5,True,0.75)]
rows=[('stand','站'),('blown','被震飛（斜）'),('sleep','睡（躺）'),('sig2','沒電攤平（躺）'),('push','推視窗（前傾）'),('sig1','充電動作')]
cw,ch=json.load(open(r'C:\tmp\dp\squad2\sprites\manifest.json',encoding='utf-8'))['meidian']['canvas_2x']
cellw,cellh=int(cw*SC)+20,int(ch*SC)+10
img=Image.new('RGB',(170+len(cols)*cellw,90+len(rows)*cellh),(246,244,238)); d=ImageDraw.Draw(img)
d.text((16,12),"沒電：電量液體執行時上色（2x 素材放大 1.5 倍看）— 液面永遠水平、依圖片 y 算；面積比例＝電量",font=FT,fill=(40,30,30))
for j,(t,_,_,_) in enumerate(cols): d.text((170+j*cellw+10,54),t,font=FS,fill=(90,60,40))
for i,(k,lab) in enumerate(rows):
    y0=90+i*cellh
    d.text((16,y0+cellh//2-12),lab,font=FS,fill=(90,60,40))
    for j,(t,L,chg,ph) in enumerate(cols):
        if k=='sig1' and not chg and j<3: pass
        im=get('2x',k,L,chg,ph)
        im=im.resize((int(im.width*SC),int(im.height*SC)),Image.LANCZOS)
        bg=Image.new('RGBA',im.size,(214,222,232,255) if (i+j)%2==0 else (206,214,226,255)); bg.alpha_composite(im)
        img.paste(bg.convert('RGB'),(170+j*cellw,y0))
img.save(r"C:\tmp\dp\squad2\battery_demo.png")
# 實際大小（1x）的一列
row=Image.new('RGB',(40+5*150,150),(236,238,242)); 
for j,(t,L,chg,ph) in enumerate(cols):
    im=get('1x','stand',L,chg,ph); bg=Image.new('RGBA',im.size,(236,238,242,255)); bg.alpha_composite(im); row.paste(bg.convert('RGB'),(20+j*150,15))
row.save(r"C:\tmp\dp\squad2\battery_demo_1x.png")
print(levels['1x']['stand']['yTop'],levels['1x']['stand']['yBottom'],levels['1x']['stand']['table'][::10])
