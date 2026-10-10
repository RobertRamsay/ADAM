import numpy as np, math, wave, struct, os
from PIL import Image, ImageDraw, ImageFont, ImageFilter

W,H=1920,1080; FPS=60; LEN=4.6; N=int(FPS*LEN)
FB=''+os.path.join(os.path.dirname(os.path.abspath(__file__)),'..','..','datafiles','fonts')+'/Poppins-Bold.ttf'; FM=''+os.path.join(os.path.dirname(os.path.abspath(__file__)),'..','..','datafiles','fonts')+'/Poppins-Medium.ttf'

# ---------------- background ----------------
yy=np.linspace(0,1,H)[:,None]
bg=np.zeros((H,W,3),np.float32)
top=np.array([18,24,44],np.float32); bot=np.array([6,8,16],np.float32)
bg[:]=top*(1-yy[...,None])+bot*yy[...,None]
cx,cy=W*0.5,H*0.46
X,Y=np.meshgrid(np.arange(W),np.arange(H))
glowmask=np.clip(1-np.hypot(X-cx,Y-cy)/(H*0.55),0,1)**1.6
glowcol=np.array([255,150,40],np.float32)

def ball(size, spin, roll=0.0):
    ss=2; S=int(size*ss)
    r=S/2-0.5
    yv,xv=np.mgrid[0:S,0:S]
    nx=(xv-r)/r; ny=(yv-r)/r; d=nx*nx+ny*ny
    inside=d<=1
    nz=np.sqrt(np.clip(1-d,0,1))
    a=math.radians(20)
    rx=nx*math.cos(roll)-ny*math.sin(roll); ry=nx*math.sin(roll)+ny*math.cos(roll)   # roll with the travel
    tx=rx*math.cos(a)-ry*math.sin(a); ty=rx*math.sin(a)+ry*math.cos(a)
    lon=np.arctan2(tx,nz)+spin; lat=np.arcsin(np.clip(ty,-1,1))
    cu=np.floor((lon+math.pi)/(math.pi/4)); cv=np.floor((lat+math.pi/2)/(math.pi/8))
    red=((cu+cv)%2==0)
    shade=0.5+0.5*nz
    spec=np.clip((nx*-0.45+ny*-0.55+nz*0.7),0,1)**18*0.6
    col=np.where(red[...,None],np.array([230,30,40]),np.array([255,255,255])).astype(np.float32)
    col=col*shade[...,None]+255*spec[...,None]
    img=np.zeros((S,S,4),np.float32)
    img[...,:3]=np.clip(col,0,255); 
    # soft edge
    edge=np.clip((1-np.sqrt(d))*r/1.5,0,1)
    img[...,3]=np.where(inside,edge*255,0)
    im=Image.fromarray(img.astype(np.uint8),'RGBA')
    return im.resize((int(size),int(size)),Image.LANCZOS)

fbig=ImageFont.truetype(FB,290); ftag=ImageFont.truetype(FM,58)
fsub=ImageFont.truetype(FM,46); fsubB=ImageFont.truetype(FB,58)
tw=fbig.getbbox("ADAM"); TW=tw[2]-tw[0]; TH=tw[3]-tw[1]
def text_layer():
    pad=40
    im=Image.new('RGBA',(TW+pad*2,TH+pad*2),(0,0,0,0)); d=ImageDraw.Draw(im)
    d.text((pad-tw[0],pad-tw[1]),"ADAM",font=fbig,fill=(255,255,255,255))
    # vertical gradient white -> pale blue
    a=np.array(im).astype(np.float32)
    g=np.linspace(0,1,a.shape[0])[:,None]
    a[...,0]=a[...,0]*(1-g*0.22); a[...,1]=a[...,1]*(1-g*0.18); a[...,2]=a[...,2]*(1-g*0.08)
    return Image.fromarray(a.astype(np.uint8)),pad
TEXT,TPAD=text_layer()
SHADOW=TEXT.copy(); sa=np.array(SHADOW); sa[...,:3]=0; sa[...,3]=(sa[...,3]*0.55).astype(np.uint8)
SHADOW=Image.fromarray(sa).filter(ImageFilter.GaussianBlur(10))

def ease_back(t,s=1.9):
    u=t-1; return 1+u*u*((s+1)*u+s)
SLOW=2.2          # slow, floaty bounce-in
REST=0.84*SLOW    # the ball comes to rest here; everything else follows it
SH=REST-0.84+0.06
TXT_IN=0.6        # logo scale-in time (was 0.28)
TXT_T=REST+0.06   # logo starts
def drop(t):
    t=t/SLOW
    if t<0.36: p=t/0.36; return 1-p*p
    if t<0.66: p=(t-0.36)/0.30; return 4*p*(1-p)*0.42
    if t<0.84: p=(t-0.66)/0.18; return 4*p*(1-p)*0.15
    return 0
clamp=lambda v,a,b: max(a,min(b,v))

STR=[(230,60,50),(250,160,40),(90,190,90),(60,130,230)]
os.makedirs('frames',exist_ok=True)
size=H*0.28
TOTAL=size+size*0.14+TW+size*0.18+size*0.80
START=(W-TOTAL)/2
BX_END=START+size/2
TX=START+size+size*0.14
for f in range(N):
    t=f/FPS
    g=clamp((t-TXT_T-0.45)/0.7,0,1)
    frame=bg+glowmask[...,None]*glowcol*0.22*g
    im=Image.fromarray(np.clip(frame,0,255).astype(np.uint8)).convert('RGBA')
    floor=cy+size*0.55
    p=clamp(t/REST,0,1)
    START_X=W+size*0.8
    bx=BX_END+(START_X-BX_END)*(1-p)**2          # comes in from the right, slowing to a stop
    by=floor-size*0.5-drop(t)*H*0.62
    sq=1.0
    for k,hh in enumerate([0.36*SLOW,0.66*SLOW,0.84*SLOW]):
        dd=abs(t-hh)
        if dd<0.07: sq=min(sq,1-(0.07-dd)*3.2*(1-k*0.3))
    # shadow
    sh=1-drop(t)*0.7
    shl=Image.new('RGBA',(W,H),(0,0,0,0)); sd=ImageDraw.Draw(shl)
    sd.ellipse([bx-size*0.45*sh,floor-10,bx+size*0.45*sh,floor+14],fill=(0,0,0,int(110*sh)))
    im=Image.alpha_composite(im,shl.filter(ImageFilter.GaussianBlur(8)))
    dist=(bx-BX_END)/(size*0.5)            # radians rolled so far (moving left = anticlockwise)
    b=ball(size,-dist*0.35,dist)
    bw=int(size*(2-sq)); bh=int(size*sq)
    b=b.resize((max(1,bw),max(1,bh)),Image.LANCZOS)
    im.alpha_composite(b,(int(bx-bw/2),int(by+size*0.5-bh)))
    tx=TX
    lt=clamp((t-TXT_T)/TXT_IN,0,1)
    if lt>0:
        sc=ease_back(lt,1.3); al=min(1,lt*2)
        tl=TEXT.resize((max(1,int(TEXT.width*sc)),max(1,int(TEXT.height*sc))),Image.LANCZOS)
        shd=SHADOW.resize(tl.size,Image.LANCZOS)
        if al<1:
            for L in (tl,shd):
                a=np.array(L); a[...,3]=(a[...,3]*al).astype(np.uint8); L.paste(Image.fromarray(a))
        ox=int(tx-TPAD*sc); oy=int(cy-tl.height/2)
        im.alpha_composite(shd,(ox+10,oy+14)); im.alpha_composite(tl,(ox,oy))
        # shine sweep
        st=clamp((t-TXT_T-1.3)/0.6,0,1)
        if 0<st<1:
            shine=Image.new('RGBA',(W,H),(0,0,0,0)); s2=ImageDraw.Draw(shine)
            sx=tx+TW*st
            s2.polygon([(sx-30,cy-TH*0.7),(sx+20,cy-TH*0.7),(sx-20,cy+TH*0.7),(sx-70,cy+TH*0.7)],fill=(255,255,255,int(110*math.sin(st*math.pi))))
            mask=Image.new('L',(W,H),0); mask.paste(tl.split()[3],(ox,oy))
            shine.putalpha(Image.fromarray(np.minimum(np.array(shine.split()[3]),np.array(mask))))
            im=Image.alpha_composite(im,shine)
        # stripes
        layer=Image.new('RGBA',(W,H),(0,0,0,0)); d=ImageDraw.Draw(layer)
        x0=tx+TW+size*0.18; hgt=size*0.78
        for s_,c in enumerate(STR):
            sp=clamp((t-TXT_T-0.6-s_*0.1)/0.3,0,1)
            if sp<=0: continue
            w=size*0.075; o=x0+s_*w*1.55; topy=cy+hgt*0.5-hgt*sp
            d.polygon([(o,cy+hgt*0.5),(o+w,cy+hgt*0.5),(o+w+hgt*0.32*sp,topy),(o+hgt*0.32*sp,topy)],fill=c+(255,))
        im=Image.alpha_composite(im,layer)
        tg=clamp((t-TXT_T-0.95)/0.5,0,1)
        if tg>0:
            layer=Image.new('RGBA',(W,H),(0,0,0,0)); d=ImageDraw.Draw(layer)
            sub="AMIGA DEVELOPMENTAL MACHINE"; hi={0,6,17,20}       # A, D, A, M -> ADAM
            xx=tx+6; yy=cy+TH*0.62+(1-tg)*18
            base=fsub.getbbox("A")[3]
            for i,ch in enumerate(sub):
                if ch==" ": xx+=26; continue
                hl=i in hi
                fnt=fsubB if hl else fsub
                col=(255,150,40,int(255*tg)) if hl else (205,212,232,int(215*tg))
                d.text((xx,yy+base-fnt.getbbox("A")[3]),ch,font=fnt,fill=col)
                xx+=d.textlength(ch,font=fnt)+5
            im=Image.alpha_composite(im,layer)
    if t>LEN-0.4:
        fa=clamp((t-(LEN-0.4))/0.4,0,1)
        im=Image.blend(im,Image.new('RGBA',(W,H),(0,0,0,255)),fa)
    im.convert('RGB').save('frames/f%03d.png'%f)
print('frames done')

# ---------------- audio ----------------
R=48000; total=np.zeros(int(R*LEN))
rng=np.random.default_rng(7)
def place(sig,t,gain=1.0):
    i=int(t*R); n=min(len(sig),len(total)-i); total[i:i+n]+=sig[:n]*gain
def lowpass(x,cut):
    y=np.zeros_like(x); lp=0.0
    for i in range(len(x)): lp+=(x[i]-lp)*cut; y[i]=lp
    return y
def reverb(x,secs=0.9,mix=0.28):
    n=int(R*secs); ir=lowpass(rng.uniform(-1,1,n)*np.exp(-np.arange(n)/R*6.0),0.25)
    ir/=np.sqrt((ir*ir).sum())
    wet=np.fft.irfft(np.fft.rfft(x,len(x)+n)*np.fft.rfft(ir,len(x)+n))[:len(x)]
    wet*=np.abs(x).max()/max(1e-9,np.abs(wet).max())
    return x*(1-mix)+wet*mix
_PU=None
def boing(strength=1.0, pitch=1.0):
    # Bob's Pickup.wav: a rising square-wave 'bwoop'. Smaller bounces play it a little higher.
    global _PU
    if _PU is None:
        w=wave.open(''+os.path.join(os.path.dirname(os.path.abspath(__file__)),'Pickup.wav')+'')
        raw=np.frombuffer(w.readframes(w.getnframes()),np.int16).astype(float)/32768
        raw=raw.reshape(-1,w.getnchannels()).mean(1)
        src_r=w.getframerate()
        _PU=(raw-raw.mean(),src_r)
    raw,src_r=_PU
    n=int(len(raw)*R/src_r/pitch)
    pos=np.arange(n)*src_r*pitch/R
    sig=np.interp(pos,np.arange(len(raw)),raw)
    t=np.arange(n)/R
    thud=np.sin(np.cumsum(50+120*np.exp(-t*30))/R*2*np.pi)*np.exp(-t*24)*np.minimum(1,t*900)*0.35
    return (sig/np.abs(raw).max()+thud)*strength
def whoosh_rise(dur):
    n=int(R*dur); x=rng.uniform(-1,1,n); out=np.zeros(n); lp=0.0
    for i in range(n):
        u=i/n; lp+=(x[i]-lp)*(0.01+0.5*u*u); out[i]=lp*(u**1.6)*1.8
    return out
def impact():
    # big logo hit: sub drop + snappy kick + crack + crash wash
    n=int(R*1.6); t=np.arange(n)/R
    sub=np.sin(np.cumsum(38+150*np.exp(-t*9))/R*2*np.pi)*np.exp(-t*3.2)*np.minimum(1,t*1200)
    kick=np.sin(np.cumsum(60+400*np.exp(-t*60))/R*2*np.pi)*np.exp(-t*18)
    crack=(rng.uniform(-1,1,n)-lowpass(rng.uniform(-1,1,n),0.1))*np.exp(-t*45)*0.8
    wash=(rng.uniform(-1,1,n)-lowpass(rng.uniform(-1,1,n),0.35))*np.exp(-t*3.5)*0.22*np.minimum(1,t*80)
    return sub*1.1+kick*0.9+crack+wash
def chime():
    return np.zeros(1)

def choir(dur):
    # a short 'Ahhhh' from a small choir: glottal-pulse voices on an A major chord,
    # each doubled and detuned with its own vibrato, through 'ah' vowel formants
    from scipy.signal import lfilter
    n=int(R*dur); t=np.arange(n)/R
    rng2=np.random.default_rng(11)
    notes=[220.0,277.18,329.63,440.0,554.37]
    src=np.zeros(n)
    for f0 in notes:
        for v in range(3):
            det=1+rng2.uniform(-0.006,0.006)
            vr=rng2.uniform(4.8,6.2); vd=0.006+0.004*rng2.random(); ph0=rng2.uniform(0,6.28)
            vib=1+vd*np.sin(2*np.pi*vr*t+ph0)*np.minimum(1,t/0.35)       # vibrato grows in
            ph=np.cumsum(f0*det*vib)/R
            frac=ph-np.floor(ph)
            pulse=np.where(frac<0.6,np.sin(np.pi*frac/0.6)**2,0.0)       # soft glottal pulse
            src+=(pulse-pulse.mean())*(0.9 if f0<300 else 0.7)
    src+=rng2.normal(0,1,n)*0.06                                         # breath
    def reson(x,f,bw,g):
        r=np.exp(-np.pi*bw/R); th=2*np.pi*f/R
        return lfilter([1-r],[1,-2*r*np.cos(th),r*r],x)*g
    out=reson(src,760,110,1.0)+reson(src,1150,130,0.55)+reson(src,2500,180,0.22)+reson(src,3400,250,0.08)
    # swell in, hold, gentle tail
    att=np.minimum(1,t/0.22)**1.5
    rel=np.clip((dur-t)/0.6,0,1)
    out*=att*rel
    return out/np.abs(out).max()
for k,tt in enumerate([0.36*SLOW,0.66*SLOW,0.84*SLOW]): place(boing([1.0,0.78,0.6][k],[1.0,1.12,1.25][k]),tt)
land=TXT_T+TXT_IN*0.62
place(whoosh_rise(0.5),land-0.5,0.55)
place(impact(),land)
place(choir(LEN-(TXT_T+0.68)),TXT_T+0.68,1.0)
total=reverb(total)
fade=np.ones_like(total); fs=int(R*(LEN-0.3)); fade[fs:]=np.linspace(1,0,len(total)-fs); total*=fade
total=np.tanh(total/max(1e-6,np.abs(total).max())*1.4)/np.tanh(1.4)*0.9
st=np.stack([total,total],1)
with wave.open('intro.wav','wb') as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(R)
    w.writeframes((st*32767).astype(np.int16).tobytes())
print('audio done')
