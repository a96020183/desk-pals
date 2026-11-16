import json
from PIL import Image, ImageDraw
K=['stand','walk1','walk2','jump','sleep','happy','held','sit','grab','push','cry','blown','sig1','sig2','surprised','pout']
M=json.load(open(r'C:\tmp\dp\squad2\sprites\manifest.json',encoding='utf-8'))
rows=[]
for c in ['duoduo','meidian','cici']:
    CW,CH=M[c]['canvas_2x']; a=M[c]['anchor_2x']
    st=Image.open(rf'C:\tmp\dp\squad2\sprites\{c}\2x\stand.png')
    top=st.getchannel('A').point(lambda v:255 if v>24 else 0).getbbox()[1]
    sh=Image.new('RGBA',(8*CW,2*(CH+14)),(150,180,150,255)); d=ImageDraw.Draw(sh)
    for i,k in enumerate(K):
        x=(i%8)*CW; y=(i//8)*(CH+14)+14
        im=Image.open(rf'C:\tmp\dp\squad2\sprites\{c}\2x\{k}.png')
        d.rectangle([x,y,x+CW-1,y+CH-1],outline=(120,140,120))
        sh.alpha_composite(im,(x,y))
        d.line([x,y+a['baselineY'],x+CW,y+a['baselineY']],fill=(255,0,0))
        d.line([x,y+top,x+CW,y+top],fill=(0,0,255))
        d.line([x+a['footX'],y,x+a['footX'],y+CH],fill=(255,0,255))
        d.text((x+3,y-13),k,fill=(0,0,0))
    sh.save(f'verify_{c}.png')
