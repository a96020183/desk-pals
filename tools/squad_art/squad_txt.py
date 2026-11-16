# 產生 pals/squad/squad.txt（程式讀這個，不解析 JSON）：每隻每個解析度一行
import json, os, numpy as np
from PIL import Image
SH=r"C:\tmp\dp\squad2\ship"
M=json.load(open(os.path.join(SH,'manifest.json'),encoding='utf-8'))
lines=["# 新續命小隊的圖（tools/squad_art 產生，別手改）",
       "# id 倍率 畫布寬 畫布高 腳底中心x 腳底y 身體頂y 身體高（stand 的不透明範圍；泡泡、櫃子高度用）"]
for c in ['duoduo','meidian','cici']:
    for r in (1,2):
        cw,ch=M[c][f'canvas_{r}x']; a=M[c][f'anchor_{r}x']
        al=np.array(Image.open(os.path.join(SH,c,f'{r}x','stand.png')).convert('RGBA'))[...,3]>24
        ys=np.where(al.any(1))[0]; top=int(ys.min()); h=int(a['baselineY'])-top+1
        lines.append(f"{c} {r} {cw} {ch} {a['footX']} {a['baselineY']} {top} {h}")
open(os.path.join(SH,'squad.txt'),'w',encoding='utf-8',newline='\n').write("\n".join(lines)+"\n")
# 側邊欄（VS Code）用的小圖：2x stand 裁掉透明邊（沒電用原圖的紅色電量）
for c in ['duoduo','meidian','cici']:
    im=Image.open(os.path.join(r"C:\tmp\dp\squad2\sprites",c,'2x','stand.png')).convert('RGBA')
    im=im.crop(im.getchannel('A').point(lambda v:255 if v>8 else 0).getbbox())
    im.quantize(256,method=Image.Quantize.FASTOCTREE,dither=Image.Dither.NONE).save(os.path.join(SH,c,'icon.png'),optimize=True)
print("\n".join(lines))
