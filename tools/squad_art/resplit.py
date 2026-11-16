# 續命小隊的圖怎麼做出來的（重做時照這個順序跑；路徑是當時的工作資料夾 C:\tmp\dp\…，換成自己的）：
#   resplit.py      從 GPT Image 生成的 2x2 動作表（gen/poses/<id>_s1..s4、修正版 *_fix）切出每個動作 → work/raw
#   normalize.py    同一隻統一比例尺（stand 為準）、腳底基準線、翻面軸；輸出 1x／2x 同尺寸畫布 → sprites/、manifest.json
#   battery.py      沒電的電量液體遮罩（手臂排除框在 arms.json）→ battery/<1x|2x>/<動作>.png（液體清成奶油色）＋ .liquid.png
#   battery_render.py  液面表 levels.json（test/desktop-squad.js 拿來對答案）＋示意圖
#   ship_preview.py 256 色壓縮 → ship/（＝extension/desktop/pals/squad）、實際大小預覽
#   squad_txt.py    squad.txt（程式讀的畫布／腳底／身體範圍）、側邊欄用的 icon.png
#   icon_art.py     App 圖示用的大圖 → packaging/icons/squad
# 從 2x2 原始動作表重新切：以「連通區塊」分給所在的象限（修正跨象限被切掉的部分）
import os, json, numpy as np
from PIL import Image
from scipy import ndimage as ndi
ROOT=r"C:\tmp\dp\gen"; OUT=r"C:\tmp\dp\squad2\work\raw"
SHEETS=[["stand","walk1","walk2","jump"],["sleep","happy","held","sit"],["grab","push","cry","blown"],["sig1","sig2","surprised","pout"]]
log={}
# 2026-11-16 重新生成：刺刺 走路兩張＋正面嘟嘴＋有小腳的站姿；沒電 懸空沒有人手的被抓
FIX={"cici":("cici_fix",["walk1","walk2","pout","stand"]),"meidian":("meidian_fix",["held",None,None,None])}
for cid in ["duoduo","meidian","cici"]:
    os.makedirs(os.path.join(OUT,cid),exist_ok=True)
    jobs=[(f"{cid}_s{si+1}",names) for si,names in enumerate(SHEETS)]
    if cid in FIX: jobs.append(FIX[cid])          # 重新生成的修正版，覆蓋同名動作
    for si,(sheet,names) in enumerate(jobs):
        im=np.array(Image.open(os.path.join(ROOT,"poses",sheet,"generated_image_url.png")).convert("RGBA"))
        H,W=im.shape[:2]; h=W//2
        a=im[...,3]>24
        lab,n=ndi.label(a,structure=np.ones((3,3)))
        ys,xs=np.indices(a.shape)
        qidx=(ys//h)*2+(xs//h)
        assign=np.zeros(n+1,int)-1
        notes=[]
        for i in range(1,n+1):
            m=lab==i; area=m.sum()
            cnt=np.bincount(qidx[m],minlength=4)
            q=int(cnt.argmax()); assign[i]=q
            if area>=150 and cnt.max()<area:
                notes.append(dict(comp=i,area=int(area),split=[int(c) for c in cnt],to=names[q]))
            if area<150: assign[i]=-2  # 小雜點
        for q,nm in enumerate(names):
            if nm is None: continue
            keep=np.isin(lab,np.where(assign==q)[0])
            # alpha 也保留低於 24 的反鋸齒邊：膨脹 2px 內的原 alpha
            keep2=ndi.binary_dilation(keep,iterations=3)&(im[...,3]>0)
            out=im.copy(); out[~keep2]=0
            bb=np.argwhere(out[...,3]>0); y1,x1=bb.min(0); y2,x2=bb.max(0)+1
            Image.fromarray(out[y1:y2,x1:x2]).save(os.path.join(OUT,cid,nm+".png"),optimize=False)
            log[f"{cid}/{nm}"]=dict(sheet=sheet,box=[int(x1),int(y1),int(x2),int(y2)],quarter=[(q%2)*h,(q//2)*h,(q%2)*h+h,(q//2)*h+h])
        for nt in notes: print(cid,sheet,nt)
json.dump(log,open(os.path.join(OUT,"resplit.json"),"w"),indent=1)
