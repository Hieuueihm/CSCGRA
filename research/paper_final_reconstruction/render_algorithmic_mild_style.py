import json, math, struct, zlib
from pathlib import Path
OUT=Path(r'D:/vivado_pj/analysis/paper_final_reconstruction')
DATA=json.loads((OUT/'k8_diagonal_algorithmic_vectors.json').read_text())
W=DATA['W']; H=DATA['H']
order=['Original','OMP','GOMP','CoSaMP','SP','IHT','HTP','GP','MP']
vecs=DATA['vectors']
WIDTH,HEIGHT=620,620
panel=150; gapx=52; gapy=52; mx0=28; sy=48
maxv=max(max(abs(v) for v in vecs[name]) for name in order) or 1.0
pixels=bytearray([255,255,255]*WIDTH*HEIGHT)
def setp(x,y,r,g=None,b=None):
    if g is None: g=b=r
    if 0<=x<WIDTH and 0<=y<HEIGHT:
        off=(y*WIDTH+x)*3; pixels[off:off+3]=bytes([max(0,min(255,int(r))),max(0,min(255,int(g))),max(0,min(255,int(b)))])
def rect(x,y,w,h,c):
    for yy in range(y,y+h):
        for xx in range(x,x+w): setp(xx,yy,c)
def value_at(vec,px,py,width=150,height=150):
    gx=px/(width-1)*(W-1); gy=py/(height-1)*(H-1); total=0.0; sigma2=0.58
    for yy in range(H):
        row=yy*W
        for xx in range(W):
            v=abs(vec[row+xx])/maxv
            if v>1e-9:
                d2=(gx-xx)**2+(gy-yy)**2
                total += v*math.exp(-d2/(2*sigma2))
    return max(0.0,min(1.0,total))
# tiny built-in 5x7 font sufficient for labels
font={
'A':['01110','10001','10001','11111','10001','10001','10001'],'C':['01111','10000','10000','10000','10000','10000','01111'],'G':['01110','10001','10000','10111','10001','10001','01110'],'H':['10001','10001','10001','11111','10001','10001','10001'],'I':['11111','00100','00100','00100','00100','00100','11111'],'M':['10001','11011','10101','10101','10001','10001','10001'],'O':['01110','10001','10001','10001','10001','10001','01110'],'P':['11110','10001','10001','11110','10000','10000','10000'],'S':['01111','10000','10000','01110','00001','00001','11110'],'T':['11111','00100','00100','00100','00100','00100','00100'],'a':['00000','00000','01110','00001','01111','10001','01111'],'g':['00000','00000','01111','10001','01111','00001','01110'],'i':['00100','00000','01100','00100','00100','00100','01110'],'l':['01100','00100','00100','00100','00100','00100','01110'],'m':['00000','00000','11010','10101','10101','10101','10101'],'n':['00000','00000','11110','10001','10001','10001','10001'],'o':['00000','00000','01110','10001','10001','10001','01110'],'p':['00000','00000','11110','10001','11110','10000','10000'],'r':['00000','00000','10110','11001','10000','10000','10000'],'s':['00000','00000','01111','10000','01110','00001','11110'],'t':['00100','00100','11111','00100','00100','00100','00011'],' ':'00000 00000 00000 00000 00000 00000 00000'.split()}
def draw_text(text,cx,y,scale=2,color=40):
    width=sum((len(font.get(ch,font[' '])[0])+1)*scale for ch in text)-scale
    x=cx-width//2
    for ch in text:
        patt=font.get(ch,font[' '])
        for yy,row in enumerate(patt):
            for xx,bit in enumerate(row):
                if bit=='1':
                    for dy in range(scale):
                        for dx in range(scale): setp(x+xx*scale+dx,y+yy*scale+dy,color)
        x += (len(patt[0])+1)*scale
def draw_panel(name,idx):
    x0=mx0+(idx%3)*(panel+gapx); y0=sy+(idx//3)*(panel+gapy)
    draw_text(name,x0+panel//2,y0-25,scale=2,color=35)
    vec=vecs[name]
    step=3
    for py in range(0,panel,step):
        for px in range(0,panel,step):
            val=value_at(vec,px+step/2,py+step/2)
            # mild contrast: lighter than algorithmic default, close to original mild figure
            shade=int(255-185*val)
            rect(x0+px,y0+py,step,step,shade)
    for x in range(x0,x0+panel): setp(x,y0,220); setp(x,y0+panel-1,220)
    for y in range(y0,y0+panel): setp(x0,y,220); setp(x0+panel-1,y,220)
for i,n in enumerate(order): draw_panel(n,i)
def chunk(tag,data): return struct.pack('>I',len(data))+tag+data+struct.pack('>I',zlib.crc32(tag+data)&0xffffffff)
raw=bytearray()
for y in range(HEIGHT): raw.append(0); raw.extend(pixels[y*WIDTH*3:(y+1)*WIDTH*3])
png=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',WIDTH,HEIGHT,8,2,0,0,0))+chunk(b'IDAT',zlib.compress(bytes(raw),9))+chunk(b'IEND',b'')
(OUT/'k8_diagonal_algorithmic_mild_style.png').write_bytes(png)
print(OUT/'k8_diagonal_algorithmic_mild_style.png')
