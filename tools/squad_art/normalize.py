# 素材正規化：同一隻同比例尺（以 stand 為準）、腳底基準線對齊、身體中心對齊；輸出 1x／2x 同尺寸畫布＋manifest
import os, json, numpy as np
from PIL import Image
from scipy import ndimage as ndi
K=['stand','walk1','walk2','jump','sleep','happy','held','sit','grab','push','cry','blown','sig1','sig2','surprised','pout']
OUT=r"C:\tmp\dp\squad2\sprites"
# 桌面高度（1x＝100% 縮放的邏輯像素，站姿含白色貼紙邊）：依團體定稿的相對大小，躲躲 88
TARGET={'duoduo':88,'meidian':83,'cici':95}
def load(c,k): return np.array(Image.open(f'raw/{c}/{k}.png').convert('RGBA'))
def big(m):
    lab,n=ndi.label(m)
    if n==0: return 0,None
    s=ndi.sum(m,lab,range(1,n+1)); i=int(s.argmax())
    return float(s[i]), lab==i+1
def stroke(a):
    r,g,b,al=[a[...,i].astype(int) for i in range(4)]
    blk=(al>200)&(r<60)&(g<60)&(b<60)
    dt=ndi.distance_transform_edt(blk); mx=ndi.maximum_filter(dt,size=5)
    v=dt[blk&(dt==mx)&(dt>=2)]
    return float(np.median(v))*2
def feats(c,a):
    r,g,b,al=[a[...,i].astype(int) for i in range(4)]; op=al>200
    if c=='duoduo':
        P=op&(r>190)&(g<90)&(b<90); S1=op&(b>200)&(r>150)&(r<225)&(b-r>15); S2=op&(r>180)&(g>130)&(g<190)&(b<140)&(r-b>60)
        body=S2
    elif c=='cici':
        P=op&(r>180)&(g>80)&(g<150)&(b<100)&(r-g>60); S1=op&(r>200)&(g>110)&(g<190)&(b>120)&(r-g>40); S2=op&(g>150)&(r<190)&(g-r>25)&(g-b>40)
        body=P
    else:
        P=op&(abs(r-g)<12)&(abs(g-b)<12)&(r>110)&(r<200); S1=op&(r>200)&(g>200)&(b>150)&(r-b>8); S2=op&(r<140)&(r>70)&(b>70)&(g<110)&(b-g>8)
        body=S1
    return dict(P=big(P)[0],S1=(big(S1)[0] if c!='meidian' else float(S1.sum())),S2=(big(S2)[0] if c!='duoduo' else float(S2.sum())),stroke=stroke(a)),body
# 不可靠的估計（姿勢遮住／角度不同），人工排除
BAD={('meidian','sig2'):['P','S2'],('meidian','cry'):['S2'],('meidian','push'):['P'],('meidian','blown'):['P'],
     ('meidian','sleep'):['S1'],('cici','blown'):['P','S2'],('cici','held'):['S2'],('cici','push'):['S2'],('cici','sig1'):['S1'],
     ('cici','sleep'):['S1'],('cici','sit'):['S1'],('cici','happy'):['S1'],('duoduo','sig1'):['S1'],('duoduo','held'):['S1'],('duoduo','push'):['S1']}
def premul_resize(img,size):
    return img.convert('RGBa').resize(size,Image.LANCZOS,reducing_gap=3.0).convert('RGBA')
manifest={}
report=[]
for c in ['duoduo','meidian','cici']:
    raw={k:load(c,k) for k in K}
    F={}; bodies={}
    for k in K: F[k],bodies[k]=feats(c,raw[k])
    sc={}
    for k in K:
        est=[]
        for f in ['P','S1','S2']:
            if f in BAD.get((c,k),[]) or F['stand'][f]<=0 or F[k][f]<=0: continue
            v=np.sqrt(F[k][f]/F['stand'][f]); est+= [v,v] if f=='P' else [v]
        est.append(F[k]['stroke']/F['stand']['stroke'])
        s=float(np.median(est)); sc[k]=s
        spread=(max(est)-min(est))/s
        report.append(dict(c=c,k=k,scale=round(s,3),est=[round(e,3) for e in est],spread=round(spread,3)))
    # stand 高度（alpha>24）
    sa=raw['stand'][...,3]>24; ys=np.where(sa.any(1))[0]; Hs=ys.max()-ys.min()+1
    manifest[c]={'target_h_1x':TARGET[c],'frames':{}}
    for res in (1,2):
        T=TARGET[c]*res/Hs
        imgs={}; info={}
        for k in K:
            f=T/sc[k]
            im=Image.fromarray(raw[k]); w,h=im.size
            imgs[k]=premul_resize(im,(max(1,round(w*f)),max(1,round(h*f))))
            info[k]=f
        # 主體（最大連通塊）的腳底
        A={k:np.array(imgs[k])[...,3] for k in K}
        base={}; mains={}
        for k in K:
            _,mm=big(A[k]>128); mains[k]=mm
            base[k]=int(np.where(mm.any(1))[0].max())
        # 沒電被抓起來：電線和插頭垂在腳下面。程式從頭頂吊著晃，所以頭頂對齊 stand 的頭頂（電線落在腳底線以下）
        if c=='meidian':
          ts=int(np.where(mains['stand'].any(1))[0].min())
          th=int(np.where(mains['held'].any(1))[0].min())
          base['held']=th+(base['stand']-ts)
        # 錨點：stand 的身體色塊（箱子／電池本體／盆）橫向中心
        bs=np.array(imgs['stand'])
        _,bm=feats(c,bs)
        _,bm=big(bm)
        if c=='duoduo': bm=np.array(imgs['stand'])[...,3]>128   # 紙箱是 3/4 透視：用整個剪影的中心當翻面軸
        xs=np.where(bm.any(0))[0]; ax_stand=(xs.min()+xs.max())/2
        anchor={'stand':ax_stand}
        Ms=mains['stand']; hs_=Ms.shape[0]
        for k in K:
            if k=='stand': continue
            M=mains[k]
            # 腳底對齊後，找橫向位移讓剪影跟 stand 重疊最多
            best=(-1,0)
            # 把兩張放到同一座標：以腳底對齊
            hh=max(base['stand'],base[k])+1
            def place(m,b,W):
                out=np.zeros((hh,W),bool); top=hh-1-b
                src=m[max(0,-top):b+1]; out[max(0,top):max(0,top)+src.shape[0],:m.shape[1]]=src; return out
            Wd=Ms.shape[1]+M.shape[1]*2
            S=place(Ms,base['stand'],Ms.shape[1])
            Mk=place(M,base[k],M.shape[1])
            for dx in range(-M.shape[1]+1,Ms.shape[1]):
                # M 的 x=0 放在 S 的 x=dx
                x1=max(0,dx); x2=min(Ms.shape[1],dx+M.shape[1])
                if x2<=x1: continue
                ov=np.logical_and(S[:,x1:x2],Mk[:,x1-dx:x2-dx]).sum()
                if ov>best[0]: best=(ov,dx)
            anchor[k]=ax_stand-best[1]
        # 統一畫布：錨點在畫布正中、腳底在同一列
        up=max(base[k]+1 for k in K); 
        down=max(A[k].shape[0]-base[k]-1 for k in K)
        half=int(np.ceil(max(max(anchor[k],A[k].shape[1]-anchor[k]) for k in K)))+1
        CW=2*half; CH=up+down+2
        by=up  # 腳底那一列（0 起算）
        od=os.path.join(OUT,c,f'{res}x'); os.makedirs(od,exist_ok=True)
        for k in K:
            cv=Image.new('RGBA',(CW,CH),(0,0,0,0))
            ox=int(round(half-anchor[k])); oy=by-base[k]
            cv.alpha_composite(imgs[k],(ox,oy))
            cv.save(os.path.join(od,k+'.png'),optimize=True)
            manifest[c].setdefault('xf',{}).setdefault(f'{res}x',{})[k]=dict(f=info[k],ox=ox,oy=oy,size=list(imgs[k].size))
            if res==1:
                al=np.array(cv)[...,3]>24; yy=np.where(al.any(1))[0]; xx=np.where(al.any(0))[0]
                manifest[c]['frames'][k]=dict(scale_vs_stand=round(sc[k],3),bbox_1x=[int(xx.min()),int(yy.min()),int(xx.max())+1,int(yy.max())+1])
        manifest[c][f'canvas_{res}x']=[CW,CH]; manifest[c][f'anchor_{res}x']=dict(footX=half,baselineY=by)
json.dump(manifest,open(os.path.join(OUT,'manifest.json'),'w',encoding='utf-8'),ensure_ascii=False,indent=1)
json.dump(report,open('scale_report.json','w'),indent=1)
for r in report:
    flag=' <-- 估計不一致' if r['spread']>0.12 else ''
    print(f"{r['c']:8s}{r['k']:10s} scale={r['scale']:.3f} est={r['est']}{flag}")
for c in manifest: print(c,manifest[c]['canvas_1x'],manifest[c]['anchor_1x'],manifest[c]['canvas_2x'])
