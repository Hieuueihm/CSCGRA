import csv, math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter
OUT = Path(r'D:/vivado_pj/analysis/paper_k8_8alg_rtl_exact')
CSV = OUT/'k8_8alg_rtl_exact_vectors.csv'
ORDER = ['Original','OMP','GOMP','CoSaMP','SP','IHT','HTP','GP','MP']
W=H=16
vectors={}
with CSV.open() as f:
    rows=list(csv.DictReader(f))
    for name in ORDER:
        vectors[name]=[abs(float(r[name])) for r in rows]
maxv=max(max(v) for v in vectors.values()) or 1.0
panel=150; gapx=60; gapy=55; marginx=35; marginy=35
img=Image.new('RGB',(660,650),'white')
d=ImageDraw.Draw(img)
try: font=ImageFont.truetype('arial.ttf',14)
except: font=ImageFont.load_default()
for idx,name in enumerate(ORDER):
    row=idx//3; col=idx%3
    x0=marginx+col*(panel+gapx); y0=55+row*(panel+gapy)
    tw=d.textlength(name,font=font)
    d.text((x0+(panel-tw)/2,y0-22),name,fill=(40,40,40),font=font)
    small=Image.new('L',(W,H),255)
    pix=small.load()
    vec=vectors[name]
    for y in range(H):
        for x in range(W):
            val=min(1.0, vec[y*W+x]/maxv)
            pix[x,y]=int(255-230*val)
    big=small.resize((panel,panel),Image.Resampling.BICUBIC).filter(ImageFilter.GaussianBlur(radius=2.2))
    rgb=Image.merge('RGB',(big,big,big))
    img.paste(rgb,(x0,y0))
    d.rounded_rectangle((x0,y0,x0+panel,y0+panel),radius=6,outline=(220,220,220),width=1)
img.save(OUT/'k8_8alg_rtl_exact_reconstruction.png')
print(OUT/'k8_8alg_rtl_exact_reconstruction.png')
