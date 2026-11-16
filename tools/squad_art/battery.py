# 沒電：電量液體遮罩。原圖解析度算 → 跟動作圖同一個變換縮到 1x/2x 畫布
import os, json, numpy as np
from PIL import Image
from scipy import ndimage as ndi
K=['stand','walk1','walk2','jump','sleep','happy','held','sit','grab','push','cry','blown','sig1','sig2','surprised','pout']
SP=r"C:\tmp\dp\squad2\sprites"; OUT=r"C:\tmp\dp\squad2\battery"
CREAM=np.array([251,240,223],float)
M=json.load(open(os.path.join(SP,'manifest.json'),encoding='utf-8'))
def lum(a): return a[...,0]*0.299+a[...,1]*0.587+a[...,2]*0.114
def disk(r):
    y,x=np.ogrid[-r:r+1,-r:r+1]; return x*x+y*y<=r*r
def classify(a):
    r,g,b,al=[a[...,i] for i in range(4)]
    op=al>200
    red=op&(r-g>40)&(abs(g-b)<40)&(r>170)                    # 紅液、粉紅液面、粉紅反光
    grn=op&(g-r>30)&(g-b>30)&(g>120)                         # 綠液（充電）
    cream=op&(r>=g-2)&(g>=b-2)&(r-b>=12)&(r-b<=60)&(lum(a)>200)   # 奶油色（空的）
    return red|grn, cream, op
def container(a, liq, cream, op, d, excl):
    light=op&(liq|cream|(lum(a)>215))
    seed,n=ndi.label(liq)
    if n==0: raise SystemExit('no liquid')
    sz=ndi.sum(liq,seed,range(1,n+1)); seed=seed==(int(sz.argmax())+1)
    lab,_=ndi.label(light)   # 4 連通：反鋸齒的斜縫不會漏
    ids=np.unique(lab[seed]); ids=ids[ids>0]
    B=np.isin(lab,ids)
    Bf=ndi.binary_fill_holes(B)
    E=ndi.binary_erosion(Bf,structure=disk(d))
    el,_=ndi.label(E)
    ids=set(np.unique(el[seed&E]).tolist())-{0}
    sz=ndi.sum(E,el,range(1,el.max()+1))
    ids|={i+1 for i,v in enumerate(sz) if v>0.015*Bf.sum()}
    C=np.isin(el,list(ids))|seed
    C=ndi.binary_fill_holes(C)
    # 手臂：從液體走過去要繞一大圈（手臂內線上端才通），測地距離遠大於直線距離 → 不算容器
    dark=lum(a)<110
    dark&=~liq
    C=(C&~excl)|seed
    C=ndi.binary_opening(C,structure=disk(3))
    el,_=ndi.label(C); ids=np.unique(el[seed&C]); ids=ids[ids>0]; C=np.isin(el,ids)
    return C,B,seed

import heapq
def geodesic(region,seed):
    H,W=region.shape; INF=1e18
    dist=np.full(H*W,INF); R=region.ravel()
    pq=[]
    for i in np.flatnonzero(seed.ravel()&R): dist[i]=0; pq.append((0.0,int(i)))
    heapq.heapify(pq)
    nb=[(-1,-1,1.4142),(-1,0,1),(-1,1,1.4142),(0,-1,1),(0,1,1),(1,-1,1.4142),(1,0,1),(1,1,1.4142)]
    while pq:
        dd,i=heapq.heappop(pq)
        if dd>dist[i]: continue
        y,x=divmod(i,W)
        for dy,dx,c in nb:
            yy,xx=y+dy,x+dx
            if 0<=yy<H and 0<=xx<W:
                j=yy*W+xx
                if R[j] and dd+c<dist[j]: dist[j]=dd+c; heapq.heappush(pq,(dd+c,j))
    return dist.reshape(H,W)
def arms(C,seed,W):
    s=3
    Cs=C[::s,::s]; Ss=seed[::s,::s]&Cs
    g=geodesic(Cs,Ss)
    e=ndi.distance_transform_edt(~Ss)
    bad=((g-e)*s>W*0.12)&(g<1e17)
    bad=np.repeat(np.repeat(bad,s,0),s,1)[:C.shape[0],:C.shape[1]]
    return bad
from PIL import ImageDraw
ARMS=json.load(open('arms.json',encoding='utf-8'))
def poly_mask(shape,polys):
    im=Image.new('L',(shape[1],shape[0]),0); d=ImageDraw.Draw(im)
    for p in polys: d.polygon([tuple(q) for q in p],fill=255)
    return np.array(im)>0
res_meta={}
os.makedirs(OUT,exist_ok=True)
dbg=[]
for k in K:
    a=np.array(Image.open(f'raw/meidian/{k}.png').convert('RGBA')).astype(float)
    liq,cream,op=classify(a)
    W=a.shape[1]
    d=max(6,int(round(W*0.0165)))
    excl=poly_mask(a.shape[:2],ARMS.get(k,[]))
    C,B,seed=container(a,liq,cream,op,d,excl)
    core=C&(liq|cream)
    # 邊緣的反鋸齒：容器內、離 core 2px 內、顏色＝core 顏色×亮度（跟黑線混）
    dist,(iy,ix)=ndi.distance_transform_edt(~core,return_indices=True)
    F=a[iy,ix,:3]
    w=np.zeros(a.shape[:2])
    w[core]=1
    edge=C&~core&(dist<=2.5)&op
    ratio=np.clip(lum(a)/np.maximum(1,lum(F)),0,1)
    err=np.abs(a[...,:3]-F*ratio[...,None]).max(-1)
    ok=edge&(err<40)
    w[ok]=ratio[ok]
    # 底圖：把液體換成奶油色（空的）
    base=a.copy()
    base[...,:3]=a[...,:3]+w[...,None]*(CREAM-F)
    left=liq&(w<0.5)&op          # 遮罩外殘留的液體色 → 一律改奶油色（空的）
    base[left,:3]=CREAM*np.clip(lum(a)[left]/lum(CREAM[None,None,:])[0,0],0,1)[:,None]
    base[...,:3]=np.clip(base[...,:3],0,255)
    res_meta[k]=dict(d=d)
    # debug：原圖上標容器（藍）、遮罩（洋紅）
    v=a[...,:3].copy(); v[C&~(w>0)]=v[C&~(w>0)]*0.5+np.array([0,0,255])*0.5
    v[w>0]=v[w>0]*0.4+np.array([255,0,255])*0.6*w[w>0][:,None]
    di=Image.fromarray(np.dstack([v,a[...,3]]).astype(np.uint8)); dd=ImageDraw.Draw(di)
    for p in ARMS.get(k,[]): dd.polygon([tuple(q) for q in p],outline=(0,200,0,255),width=4)
    os.makedirs('dbg',exist_ok=True); di.save(f'dbg/{k}.png')
    dbg.append(di)
    # 縮到 1x／2x 畫布
    for rs in ('1x','2x'):
        xf=M['meidian']['xf'][rs][k]; CW,CH=M['meidian'][f'canvas_{rs}']
        sz=tuple(xf['size'])
        bi=Image.fromarray(base.astype(np.uint8)).convert('RGBa').resize(sz,Image.LANCZOS,reducing_gap=3.0).convert('RGBA')
        wi=Image.fromarray((w*255).round().astype(np.uint8),'L').resize(sz,Image.LANCZOS,reducing_gap=3.0)
        cb=Image.new('RGBA',(CW,CH),(0,0,0,0)); cb.alpha_composite(bi,(xf['ox'],xf['oy']))
        cm=Image.new('L',(CW,CH),0); cm.paste(wi,(xf['ox'],xf['oy']))
        od=os.path.join(OUT,rs); os.makedirs(od,exist_ok=True)
        cb.save(os.path.join(od,f'{k}.png'),optimize=True)
        cm.save(os.path.join(od,f'{k}.liquid.png'),optimize=True)
# debug 拼圖
sh=Image.new('RGBA',(4*360,4*330),(120,160,120,255))
for i,im in enumerate(dbg):
    t=im.copy(); t.thumbnail((350,320)); sh.alpha_composite(t,((i%4)*360+5,(i//4)*330+5))
sh.save('battery_debug.png')
