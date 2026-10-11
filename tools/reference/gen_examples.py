# Generates the example projects (datafiles/examples/*.adam; Firefly Night is the ADAM Pro / BOB one)
# plus test ADFs and previews in tools/reference/out.
# Usage: python gen_examples.py
import json, math, random, struct, sys, os
from PIL import Image, ImageDraw
import art
from adf_reference import build, adf, ENGINE, ENGINE_DIR, HERE, REPO

W,H=320,256
def gun(v): return round(v/17)*17
def q(c): return (gun((c>>16)&255)<<16)|(gun((c>>8)&255)<<8)|gun(c&255)

def palette_default():
    p=[0x000000,0xffffff,0x0055aa,0xff8800,0x1a2a4a,0x33598c,0x5c9cd6,0xa8d8ff,0x1e4a1e,0x3f8a2e,0x7acc44,0x6a4426,0xb07a45,0xdd3322,0xffdd33,0x8a8a8a]
    import colorsys
    for i in range(16,128):
        k=i-16; hue=(k%16)*16/255; row=k//16
        sat,val=[(255,255),(170,255),(90,255),(255,190),(255,120),(140,140),(0,(k%16)*17)][row]
        r,g,b=colorsys.hsv_to_rgb(hue,sat/255,val/255)
        p.append((int(r*255)<<16)|(int(g*255)<<8)|int(b*255))
    return p

PRESETS=[[2,60,6,8,0,6,0,4],[1,120,-8,12,0,8,0,6],[3,40,-1,25,0,10,0,9],[0,30,4,14,0,7,4,5],[3,14,0,6,0,5,0,3],[2,40,3,30,2,6,8,6],[0,50,-2,30,0,9,6,8],[2,90,0,3,0,3,0,2]]
NAMES=["Coin","Laser","Explosion","Jump","Hit","Power up","Lose","Blip"]
def sfx_list(over=None):
    out=[]
    for i,p in enumerate(PRESETS):
        d=dict(name=NAMES[i],kind=0,wave=p[0],pitch=p[1],sweep=p[2],len=p[3],atk=p[4],dec=p[5],sus=p[6],rel=p[7],
               smp="",smp_rate=0,smp_len=0,smp_file="",rate=11025,bits=8,gain=100,trim_a=0,trim_b=1000)
        if over and i in over: d.update(over[i])
        out.append(d)
    return out

# ---- songs for the Music page: loops copied from ADAM's built-in library (global.MUS_LIB, lib = its index)
MUS_ROOT=18; MIN=0x37; MAJ=0x47
def ldrums(name,lib,pat):
    notes=[MUS_ROOT if c in "KSHOTC" else 0 for c in pat]; insts=["KSHOTC".index(c) if c in "KSHOTC" else 0 for c in pat]
    return dict(name=name,cat=0,lib=lib,inst=0,notes=notes,insts=insts,arps=[0]*16)
def ltone(name,lib,cat,inst,notes,arps=None):
    return dict(name=name,cat=cat,lib=lib,inst=inst,notes=list(notes),insts=[inst]*16,arps=list(arps or [0]*16))
LIB={
    "Four on the floor":ldrums("Four on the floor",0,"K.H.K.H.K.H.K.H."),
    "Rock beat":ldrums("Rock beat",1,"K.H.S.H.K.KHS.H."),
    "Breakbeat":ldrums("Breakbeat",2,"K.H.S..KK.H.S.HC"),
    "Half time":ldrums("Half time",3,"K...H...S...H..."),
    "Disco claps":ldrums("Disco claps",4,"K.H.C.H.K.H.C.HO"),
    "Tom fill":ldrums("Tom fill",6,"T.T.TT.TS.S.SSSC"),
    "Root pulse":ltone("Root pulse",7,1,6,[13,0,0,0]*4),
    "Octave bounce":ltone("Octave bounce",8,1,7,[13,0,25,0]*4),
    "Walking bass":ltone("Walking bass",9,1,6,[13,0,0,0,16,0,0,0,18,0,0,0,20,0,18,0]),
    "Offbeat bass":ltone("Offbeat bass",10,1,6,[0,0,13,0]*4),
    "Acid line":ltone("Acid line",11,1,7,[13,13,25,13,0,13,23,13,13,0,25,0,16,13,18,13]),
    "Minor to major":ltone("Minor to major",14,2,9,[13]+[0]*7+[21]+[0]*7,[MIN]+[0]*7+[MAJ]+[0]*7),
    "Offbeat skank":ltone("Offbeat skank",15,2,8,[0,0,13,0]*4,[0,0,MIN,0]*4),
    "Rising chords":ltone("Rising chords",16,2,9,[13,0,0,0,16,0,0,0,18,0,0,0,20,0,0,0],[MIN,0,0,0,MAJ,0,0,0,MIN,0,0,0,MIN,0,0,0]),
    "Long minor":ltone("Long minor",17,2,9,[13]+[0]*15,[MIN]+[0]*15),
    "Arp up":ltone("Arp up",18,3,12,[13,16,20,25]*4),
    "Arp down":ltone("Arp down",19,3,12,[25,20,16,13]*4),
    "Hook one":ltone("Hook one",20,3,10,[13,0,0,16,0,0,20,0,18,0,16,0,15,0,13,0]),
    "Hook two":ltone("Hook two",21,3,11,[25,0,23,0,20,0,0,0,18,0,20,0,23,0,0,0]),
    "Long notes":ltone("Long notes",22,3,10,[20]+[0]*7+[18]+[0]*7),
    "Trill":ltone("Trill",23,3,12,[25,27,25,27,25,27,25,27,23,25,23,25,23,25,23,25]),
}
def song(name,bpm,lanes,loop_bar=0):
    # lanes: 4 lists of loop names per bar ('' = empty bar)
    loops=[]; out=[]
    for lane in lanes:
        row=[-1]*128
        for b,n in enumerate(lane):
            if not n: continue
            if n not in [l['name'] for l in loops]: loops.append(LIB[n])
            row[b]=[l['name'] for l in loops].index(n)
        out.append(row)
    return dict(name=name,kind=0,bpm=bpm,speed=6,swing=0,loop_bar=loop_bar,arr=dict(bars=max(len(l) for l in lanes),lanes=out,loops=loops))
def bars(*parts):
    # bars("A",4,"B",2) -> ["A","A","A","A","B","B"]
    out=[]
    for i in range(0,len(parts),2): out+=[parts[i]]*parts[i+1]
    return out

FONT=[]
import re
FONT=[int(v,16) for v in re.findall(r'\$([0-9a-f]{2})',open(os.path.join(ENGINE_DIR,'font.inc')).read())]
def text(px,s,x,y,c):
    for i,ch in enumerate(s.upper()):
        o=ord(ch)
        if o<32 or o>95: o=32
        for r in range(8):
            b=FONT[(o-32)*8+r]
            for k in range(8):
                if b&(128>>k):
                    xx=x+i*8+k; yy=y+r
                    if 0<=xx<W and 0<=yy<H: px[yy*W+xx]=c

def actor(name,sprite,role,speed,x,y,anim=-1,rate=8,moving=False,vis=True,left=False,up=False):
    return dict(name=name,sprite=sprite,role=role,speed=speed,x=x,y=y,visible=vis,start_left=left,start_up=up,anim_sprite=anim,anim_rate=rate,anim_moving=moving,from_level=1,faster_every=0)
def R(when=0,a=0,b=1,n=1,act=0,target=0,value=10): return dict(when=when,a=a,b=b,n=n,act=act,target=target,value=value,group=-1)

def auto_groups(p):
    names=p['actors']
    def key(r):
        if p['name']=="Gem Hunter":
            if r['when']==0 and r['b'] in (1,2,3,4): return "Hoppers hit the hero"
            if r['when']==0: return "Collecting gems"
            if r['when']==6: return "Jump sounds"
            return "Game and level flow"
        if p['name']=="Firefly Night" and r['when']==0:
            return "Catching fireflies" if names[r['b']]['name'].startswith("Firefly") else "Bats"
        if r['when']==0:
            tgt=names[r['b']]['name'] if r['b']<len(names) else "?"
            return names[r['a']]['name']+" touches "+tgt
        if r['when'] in (1,6): return "Controls and sounds"
        if r['when']==2: return "Timers"
        return "Game flow"
    order=[]; 
    for r in p['rules']:
        k=key(r)
        if k not in order: order.append(k)
    p['groups']=[dict(name=k,collapsed=False,enabled=True) for k in order]
    for r in p['rules']: r['group']=order.index(key(r))
    p['rules']=sorted(p['rules'],key=lambda r:r['group'])

def make_project(name,pal16,img,sprites,actors,rules,sky,hud_col=1,msg_col=14,lives=3,over="GAME OVER - PRESS FIRE",win="YOU WIN! - PRESS FIRE",sfx=None,songs=None):
    pal=palette_default(); pal[:16]=pal16
    spr=[]
    for i in range(32):
        if i<len(sprites):
            n,a,cols=sprites[i]; spr.append(dict(name=n,px=art.px(a),cols=cols))
        else: spr.append(dict(name="Sprite %d"%(i+1),px=[0]*384,cols=[0xffdd33,0xdd3322,0xffffff]))
    return dict(version=1,name=name,machine="A500_600",depth=4,pal=pal,pixels=list(img.getdata()),sprites=spr,actors=actors,rules=rules,
                sfx=sfx or sfx_list(),lives=lives,show_score=True,show_lives=True,hud_row=0,hud_colour=hud_col,msg_colour=msg_col,
                over_text=over,win_text=win,solid=[0]*128,levels_on=False,levels=[],terrain_cols=[10,9,11,12],goal_on=False,goal=20,goal_label='GEMS',title_on=False,title1=name.upper(),title2='PRESS FIRE TO START',lev_text='LEVEL',sky_on=True,sky_top=sky[0],sky_mid=sky[1],sky_bot=sky[2],sky_mid_y=sky[3],
                songs=songs or [],level_song=[-1]*10)

def canvas(): return Image.new('P',(W,H),0)

# ordered (Bayer 8 x 8) dithering - the same matrix as global.BAYER8 in ADAM
BAYER8=[0,32,8,40,2,34,10,42, 48,16,56,24,50,18,58,26, 12,44,4,36,14,46,6,38, 60,28,52,20,62,30,54,22,
        3,35,11,43,1,33,9,41, 51,19,59,27,49,17,57,25, 15,47,7,39,13,45,5,37, 63,31,55,23,61,29,53,21]
def bayer(x,y): return BAYER8[(y&7)*8+(x&7)]
def dmix(a,b,t,x,y):
    # colour a at t=0 to colour b at t=1, dithered
    return b if (bayer(x,y)+0.5)/64<t else a
def ramp(cols,t,x,y):
    # dithered gradient through a list of palette colours, t 0..1
    t=max(0.0,min(1.0,t)); pos=t*(len(cols)-1); k=min(int(pos),len(cols)-2)
    return dmix(cols[k],cols[k+1],pos-k,x,y)

def terrain(seed, hilly, base):
    st=[seed & 0x7fffffff]
    def rnd():
        st[0]=(st[0]*1103515245+12345) % 2147483648
        return st[0]/2147483648
    freqs=[(45,70),(20,30),(9,14)]; amps=[14,7,3]
    terms=[]
    for k in range(3):
        f=1.0/(freqs[k][0]+rnd()*(freqs[k][1]-freqs[k][0])); ph=rnd()*6.283185307179586
        terms.append((f,ph,amps[k]*hilly/100.0))
    out=[]
    for x in range(320):
        y=base
        for f,ph,a in terms: y+=math.sin(x*f+ph)*a
        out.append(max(100,min(240,math.floor(y+0.5))))
    return out

# ------------------------------------------------------------------ GEM HUNTER
def gem_hunter():
    pal=[0x000000,0xffffff,0x1c4f9c,0xffb040,0x4a3a78,0x8a7ab8,0xe0e0ff,0xfff0b0,0x1e5a2a,0x3f9a2e,0x8adc4a,0x6a4426,0xb07a45,0xdd3322,0xffdd33,0x2e6e3a]
    im=canvas(); d=ImageDraw.Draw(im); P=im.load()
    # sun: pale core, orange rim, then a dithered glow fading into the copper sky (colour 0)
    sx,sy=228,92
    for y in range(40,150):
        for x in range(170,290):
            r=math.hypot(x-sx,y-sy)
            if r<=20: P[x,y]=7
            elif r<=27: P[x,y]=dmix(7,3,(r-20)/7,x,y)
            elif r<=44: P[x,y]=dmix(3,0,(r-27)/17,x,y)
    def ridge(x): return int(130-abs(((x+40)%110)-55)*1.1-10*math.sin(x/17))
    for x in range(320):                                                     # far mountains, lit from the sun
        y=ridge(x); lit=(x+40)%110<55                                        # faces sloping down to the right face the sun
        for yy in range(y,256):
            dep=(yy-y)/45
            if lit: c=ramp([5,4],dep,x,yy)
            else: c=4 if yy-y>2 else dmix(5,4,0.75,x,yy)                    # shadow side, a glint on the ridge
            if y<96 and yy-y<7: c=dmix(6,c,(yy-y)/7,x,yy)                    # snow caps, melting into the rock
            P[x,yy]=c
    def hill(x): return int(150+math.sin(x/23)*8+math.sin(x/9)*3)
    for x in range(320):                                                     # distant green hills, darker further down
        y=hill(x)
        for yy in range(y,256): P[x,yy]=dmix(10,15,0.5,x,yy) if yy-y<2 else ramp([15,8],(yy-y-2)/38,x,yy)
    rnd=random.Random(3)
    for t in range(12):                                                      # far trees, a lit edge on the sun side
        x=rnd.randint(8,310); base=hill(x)+3
        d.polygon([(x,base-12),(x-4,base),(x+4,base)],fill=8)
        for yy in range(base-11,base+1):
            hw=(yy-(base-12))*4//12
            if hw>0: P[x+hw,yy]=dmix(8,15,0.5,x+hw,yy)
    d.rectangle([0,0,319,11],fill=2)
    hero_cols=[0xffd23a,0x3a2410,0xffffff]; hop_cols=[0xff5060,0x601020,0xffffff]; cloud_cols=[0xffffff,0xa8b8d0,0xd8e4f4]
    def grid(fn): return ["".join(".123"[fn(x,y)] for x in range(16)) for y in range(24)]
    def hero(x,y):
        v=1 if math.hypot(x-7.5,y-9.5)<=7.4 else 0
        if x in(5,10) and y in(7,8): v=2
        if y==12 and 5<=x<=10: v=2
        if y==11 and x in(4,11): v=2
        if x in(5,10) and y==6: v=3
        if 17<=y<=22 and x in(5,6,9,10): v=2
        return v
    def hero2(x,y):
        v=hero(x,y)
        if 17<=y<=22 and x in(5,6,9,10): v=1 if math.hypot(x-7.5,y-9.5)<=7.4 else 0
        if 17<=y<=22 and ((x in(4,5) and y<21) or (x in(10,11) and y<21) or (y>=21 and x in(3,4,11,12))): v=2
        return v
    art.A['gh_hero']=grid(hero); art.A['gh_hero2']=grid(hero2)
    # the gem shares the hero's colour pair (gold), so 4 hoppers still fit the 8 hardware sprites
    sprites=[("Hero","gh_hero",hero_cols),("Hopper","hop2",hop_cols),("Gem","gem",hero_cols),("Cloud","cloud",cloud_cols),
             ("Hero walk","gh_hero2",hero_cols),("Hopper squat","hop",hop_cols),("Gem sparkle","gem2",hero_cols),("Cloud puff","cloud2",cloud_cols),
             ("Pop","pop",cloud_cols),("Pop big","pop2",cloud_cols)]
    def hop(name,x,frm,left=False):
        a=actor(name,1,7,1,x,120,5,10,left=left); a['from_level']=frm; a['faster_every']=3; return a
    actors=[actor("Hero",0,6,2,24,120,4,6,True),
            hop("Hopper A",170,1),hop("Hopper B",280,1,True),hop("Hopper C",120,2,True),hop("Hopper D",230,3),
            actor("Cloud",3,2,1,60,20,7,25),
            actor("Gem",2,8,1,60,30,6,12),
            actor("Pop",8,5,1,0,0,9,4,vis=False)]
    rules=[]
    for b in (1,2,3,4):
        rules+=[R(b=b,act=1),R(b=b,act=2,value=4),R(b=b,act=2,value=6),
                R(b=b,act=14,target=7,value=0),R(b=b,act=15,target=7),
                R(b=b,act=4,target=0),R(b=b,act=16,target=0)]
    rules+=[R(b=6,act=0,value=10),R(b=6,act=2,value=0),R(b=6,act=17),R(b=6,act=14,target=6,value=5),
            R(when=6,a=0,act=2,value=3)]
    for b in (1,2,3,4): rules.append(R(when=6,a=b,act=2,value=1))
    rules+=[R(when=4,act=9),
            R(when=7,act=14,target=6,value=5),R(when=7,act=16,target=0),R(when=7,act=2,value=5)]
    sfx=sfx_list({0:dict(name="Gem",wave=2,pitch=80,sweep=10,len=6,atk=0,dec=5,sus=0,rel=4),
                  1:dict(name="Squidge",wave=1,pitch=12,sweep=5,len=6,atk=1,dec=4,sus=2,rel=3),
                  3:dict(name="Jump",wave=2,pitch=24,sweep=6,len=10,atk=0,dec=6,sus=2,rel=4),
                  4:dict(name="Pop",wave=3,pitch=90,sweep=-12,len=3,atk=0,dec=3,sus=0,rel=3),
                  5:dict(name="Get ready",wave=2,pitch=40,sweep=3,len=20,atk=2,dec=6,sus=8,rel=6),
                  6:dict(name="Ouch",wave=0,pitch=46,sweep=-1,len=26,atk=1,dec=8,sus=9,rel=7)})
    tune=song("Hilltop",125,[
        bars("Half time",2,"Rock beat",5,"Tom fill",1,"Rock beat",7,"Tom fill",1),
        bars("Root pulse",4,"Walking bass",4,"Root pulse",4,"Walking bass",4),
        bars("Long minor",2,"Minor to major",2,"Long minor",2,"Minor to major",2,"Long minor",2,"Minor to major",2,"Long minor",2,"Minor to major",2),
        bars("",4,"Hook one",1,"Hook two",1,"Hook one",1,"Hook two",1,"",4,"Hook one",1,"Hook two",1,"Hook one",1,"Hook two",1)],loop_bar=2)
    p=make_project("Gem Hunter",pal,im,sprites,actors,rules,[0x101848,0x5a6ac8,0xffa850,150],hud_col=1,msg_col=14,sfx=sfx,
                   win="CONGRATULATIONS! ALL 10 LEVELS DONE",songs=[tune])
    p['level_song']=[0]*10
    levels=[]
    for i in range(10):
        seed=1000+i*37; hilly=60+i*8
        levels.append(dict(seed=seed,hilly=hilly,base=200,heights=terrain(seed,hilly,200)))
    p.update(levels_on=True,levels=levels,terrain_cols=[10,9,11,12],goal_on=True,goal=20,goal_label="GEMS",
             title_on=True,title1="GEM HUNTER",title2="PRESS FIRE TO START",lev_text="LEVEL")
    return p

# ------------------------------------------------------------------ DEEP DIVE
def deep_dive():
    pal=[0x000000,0xffffff,0x204060,0xff9040,0x2a3a50,0x506070,0xc0f0ff,0x80e0ff,0x1a5a3a,0x2f8f4a,0x6acc6a,0x8a7040,0xd8c070,0xe04060,0xffe060,0xa0a8b0]
    im=canvas(); d=ImageDraw.Draw(im); P=im.load()
    # surface ripples, with a dithered shimmer under them
    for x in range(320):
        y=14+round(math.sin(x/9)*2)
        d.line([(x,12),(x,y)],fill=6)
        for yy in range(y+1,y+7): P[x,yy]=dmix(7,0,(yy-y)/7,x,yy)
    # light rays: slanted beams that fade out with depth (pattern dither over the copper water)
    for k in range(5):
        x0=30+k*70
        for y in range(16,180):
            w=3+y//30; xs=x0+y//6
            for x in range(xs,min(320,xs+w)):
                edge=min(x-xs+1,xs+w-x)/2.5                                  # soft sides
                if (bayer(x,y)+0.5)/64<min(1,edge)*0.5*(1-(y-16)/164): P[x,y]=7
    # sand dunes: a lit crest blending down into darker sand
    for x in range(320):
        y=212+round(math.sin(x/29)*8+math.sin(x/11)*3)
        for yy in range(y,256): P[x,yy]=ramp([12,11],(yy-y)/9,x,yy)
    for i in range(160):
        rnd=random.Random(i)
        x=rnd.randint(0,319); y=rnd.randint(222,254); im.putpixel((x,y),12)
    # rocks, lit from above
    for (x,y,r) in [(40,214,18),(270,210,22),(150,222,12)]:
        ry=r/1.4
        for yy in range(int(y-ry),int(y+ry)+1):
            for xx in range(x-r,x+r+1):
                u=(xx-x)/r; v=(yy-y)/ry
                if u*u+v*v<=1 and 0<=xx<W: P[xx,yy]=ramp([15,5,4],(u+v)*0.45+0.5,xx,yy)
    # seaweed
    for k,x0 in enumerate([18,70,95,190,230,300]):
        top=150+(k*13)%40
        for y in range(top,222):
            x=x0+round(math.sin(y/8+k)*3)
            d.line([(x,y),(x+2,y)],fill=9 if (y//6)%2 else 10)
    # coral
    for (x,y) in [(120,214),(205,212),(258,190)]:
        for a in range(-60,61,30):
            ex=x+round(math.sin(math.radians(a))*16); ey=y-round(math.cos(math.radians(a))*20)
            d.line([(x,y),(ex,ey)],fill=13,width=3); d.ellipse([ex-3,ey-3,ex+3,ey+3],fill=3)
    # bubbles
    rnd=random.Random(7)
    for i in range(18):
        x=rnd.randint(10,310); y=rnd.randint(30,190); r=rnd.randint(2,5)
        d.ellipse([x-r,y-r,x+r,y+r],outline=6)
    d.rectangle([0,0,319,11],fill=2)
    px=list(im.getdata()); text(px,"FIND THE PEARLS - MIND THE SHARK",28,246,1); im.putdata(px)
    diver=[0xffcc30,0x203040,0x90f0ff]; jelly=[0xff80c0,0xff60a0,0xffd0f0]; shark=[0x000000,0x6a7a8a,0xe0e8f0]; pearl=[0xfff0f8,0xa080a0,0xffffff]
    sprites=[("Diver","diver",diver),("Jellyfish","jelly",jelly),("Shark","shark",shark),("Pearl","pearl",pearl),
             ("Diver kick","diver2",diver),("Jelly swim","jelly2",jelly),("Shark tail","shark2",shark),("Pearl shine","pearl2",pearl)]
    actors=[actor("Diver",0,0,2,150,110,4,7,True),actor("Jelly 1",1,3,1,70,40,5,12,up=False),actor("Jelly 2",1,3,1,240,150,5,12,up=True),
            actor("Shark",2,2,2,10,175,6,6),actor("Pearl",3,5,1,200,120,7,10),actor("Pearl 2",3,5,1,40,90,7,14)]
    rules=[R(b=1,act=1),R(b=1,act=4,target=0),R(b=1,act=2,value=4),R(b=1,act=3),
           R(b=2,act=1),R(b=2,act=4,target=0),R(b=2,act=2,value=4),R(b=2,act=3),
           R(b=3,act=1),R(b=3,act=4,target=0),R(b=3,act=2,value=2),R(b=3,act=3),
           R(b=4,act=0,value=25),R(b=4,act=5,target=4),R(b=4,act=2,value=0),
           R(b=5,act=0,value=25),R(b=5,act=5,target=5),R(b=5,act=2,value=0),
           R(when=1,act=2,value=7),R(when=2,n=15,act=11,target=3),R(when=3,n=300,act=10),R(when=4,act=9),R(when=5,act=2,value=5),
           R(when=5,act=18,value=0)]
    sfx=sfx_list({7:dict(name="Bubble",wave=0,pitch=70,sweep=5,len=6,atk=0,dec=4,sus=0,rel=3)})
    tune=song("Undertow",100,[
        bars("Half time",16),
        bars("",2,"Offbeat bass",14),
        bars("Long minor",4,"Minor to major",4,"Long minor",4,"Minor to major",4),
        bars("",4,"Long notes",4,"Hook two",2,"Long notes",2,"Hook two",2,"Long notes",2)])
    return make_project("Deep Dive",pal,im,sprites,actors,rules,[0x70d8f0,0x1868a8,0x021028,95],sfx=sfx,msg_col=14,
                        win="YOU FOUND THEM ALL!",over="OUT OF AIR - PRESS FIRE",songs=[tune])

# ------------------------------------------------------------------ STAR CATCHER
def star_catcher():
    pal=[0x000000,0xffffff,0x182848,0xff8030,0x403850,0x8070a0,0xc0c8ff,0x90a0ff,0x2a1840,0x6a3a8a,0xb070e0,0x6a4030,0xc08050,0xe05040,0xffe070,0x9098a8]
    im=canvas(); d=ImageDraw.Draw(im); P=im.load()
    rnd=random.Random(11)
    # nebula: soft dithered clouds over the copper sky, brightest in the middle
    for y in range(14,220):
        for x in range(0,230):
            u=(x-90)/100; v=(y-112)/42
            t=1-math.sqrt(u*u+v*v)
            t+=0.18*math.sin(x/9+y/13)*math.sin(y/7-x/23)                    # wisps
            if t>0: P[x,y]=ramp([0,8,9,10],t*1.25,x,y)
    for i in range(220):
        x=rnd.randint(0,319); y=rnd.randint(14,255); c=rnd.choice([1,15,15,6,14])
        im.putpixel((x,y),c)
        if rnd.random()<0.08:
            for dx,dy in((1,0),(-1,0),(0,1),(0,-1)):
                if 0<=x+dx<W and 0<=y+dy<H: im.putpixel((x+dx,y+dy),15)
    # planet: banded, lit from the top left, dithered into shadow
    cx,cy,r=250,215,70
    L=(-0.55,-0.6,0.58); ln=math.sqrt(sum(c*c for c in L)); L=[c/ln for c in L]
    for y in range(cy-r,min(H,cy+r)):
        for x in range(cx-r,min(W,cx+r)):
            u=(x-cx)/r; v=(y-cy)/r
            if u*u+v*v>1: continue
            w=math.sqrt(max(0.0,1-u*u-v*v))
            lum=u*L[0]+v*L[1]+w*L[2]
            band=[12,3,11][int((v*r+r)//9)%3]
            P[x,y]=ramp([band,4,2],(0.55-lum)/0.75,x,y)
    for a in range(200,341):                                                 # rings, dithered as they go behind
        for th in (0,1):
            t=math.radians(a); x=int(cx+math.cos(t)*110); y=int(cy+math.sin(t)*(22-th))
            if 0<=x<W and 0<=y<H: P[x,y]=dmix(7,15,abs(a-270)/70,x,y)
    # moon with a dithered terminator
    for y in range(26,66):
        for x in range(26,70):
            if (x-46)**2+(y-46)**2<=16*16:
                k=math.hypot(x-56,y-42)/16                                   # distance from the dark disc
                if k>1: P[x,y]=15
                elif k>0.7: P[x,y]=dmix(0,15,(k-0.7)/0.3,x,y)
    d.ellipse([34,44,40,50],fill=4)
    d.rectangle([0,0,319,11],fill=2)
    ship=[0xe8e8f0,0x3050a0,0xff9020]; rock=[0x9a7a5a,0x4a3a2a,0xc0a080]; ufo=[0x60e060,0x206030,0xb0ffb0]; star=[0xffe040,0xc08000,0xffffff]
    sprites=[("Rocket","ship",ship),("Asteroid","rock",rock),("UFO","ufo",ufo),("Star","star",star),
             ("Rocket flame","ship2",ship),("Asteroid spin","rock2",rock),("UFO lights","ufo2",ufo),("Star twinkle","star2",star)]
    actors=[actor("Rocket",0,0,3,150,200,4,4),actor("Asteroid 1",1,1,1,40,40,5,16,left=False,up=False),actor("Asteroid 2",1,1,2,260,100,5,16,left=True,up=True),
            actor("UFO",2,4,1,10,20,6,12),actor("Star",3,5,1,160,90,7,10)]
    rules=[R(b=1,act=1),R(b=1,act=4,target=0),R(b=1,act=2,value=2),R(b=1,act=3),
           R(b=2,act=1),R(b=2,act=4,target=0),R(b=2,act=2,value=2),R(b=2,act=3),
           R(b=3,act=1),R(b=3,act=4,target=0),R(b=3,act=4,target=3),R(b=3,act=2,value=6),
           R(b=4,act=0,value=10),R(b=4,act=5,target=4),R(b=4,act=2,value=0),
           R(when=1,act=2,value=1),R(when=2,n=20,act=11,target=3),R(when=3,n=250,act=10),R(when=4,act=9),R(when=5,act=2,value=5),
           R(when=5,act=18,value=0)]
    tune=song("Orbit",130,[
        bars("Four on the floor",7,"Tom fill",1,"Four on the floor",7,"Tom fill",1),
        bars("Octave bounce",16),
        bars("Rising chords",16),
        bars("",4,"Arp up",2,"Arp down",2,"Arp up",2,"Arp down",2,"Arp up",2,"Arp down",2)])
    return make_project("Star Catcher",pal,im,sprites,actors,rules,[0x000000,0x1a0838,0x0a1840,140],msg_col=14,
                        win="GALAXY SAVED! - PRESS FIRE",over="SHIP LOST - PRESS FIRE",songs=[tune])

# ------------------------------------------------------------------ DODGE BALL
def dodge_ball():
    pal=[0x000000,0xffffff,0x200040,0xff9020,0x180828,0x301850,0xff40c0,0x40e0ff,0x101830,0x2a2a60,0x6060c0,0x402060,0x8040a0,0xff3040,0xfff060,0x9090b0]
    im=canvas(); d=ImageDraw.Draw(im); P=im.load()
    # skyline, glowing from the street below
    rnd=random.Random(5)
    x=0
    while x<320:
        w=rnd.randint(14,30); h=rnd.randint(20,70)
        for yy in range(128-h,129):
            for xx in range(x,min(320,x+w-1)): P[xx,yy]=ramp([4,5,11],(yy-(128-h))/max(1,h),xx,yy)
        for wy in range(128-h+4,126,6):
            for wx in range(x+3,x+w-4,5):
                if rnd.random()<0.35: d.rectangle([wx,wy,wx+1,wy+2],fill=14)
        x+=w
    # floor: neon glow at the horizon fading into the dark, then the perspective grid
    for yy in range(128,256):
        for xx in range(320): P[xx,yy]=ramp([11,5,4],(yy-128)/70,xx,yy)
    for i in range(-20,21):
        d.line([(160,118),(160+i*40,256)],fill=12)
    yy=130; k=2
    while yy<256:
        d.line([(0,int(yy)),(319,int(yy))],fill=12); yy+=k; k*=1.35
    d.line([(0,128),(319,128)],fill=6,width=2)
    # neon frame
    d.rectangle([2,14,317,253],outline=6); d.rectangle([4,16,315,251],outline=7)
    d.rectangle([0,0,319,11],fill=2)
    px=list(im.getdata()); text(px,"DODGE THE BALLS!",96,40,1); im.putdata(px)
    blob=[0x40e0ff,0x103060,0xffffff]; red=[0xff3040,0x601020,0xffc0c0]; yel=[0xffe040,0x806000,0xffffff]; gem=[0xff40ff,0x601060,0xffffff]
    sprites=[("Player","blob",blob),("Red ball","ball",red),("Yellow ball","ball",yel),("Bonus","gem",gem),
             ("Player squash","blob2",blob),("Red ball spin","ball2",red),("Yellow ball spin","ball2",yel),("Bonus sparkle","gem2",gem)]
    actors=[actor("Player",0,0,3,150,180,4,8,True),actor("Red 1",1,1,2,30,30,5,8),actor("Red 2",1,1,2,270,40,5,8,left=True),
            actor("Yellow 1",2,1,1,60,200,6,8,up=True),actor("Yellow 2",2,1,1,240,190,6,8,left=True,up=True),actor("Bonus",3,5,1,160,100,7,10)]
    rules=[]
    for b in (1,2,3,4):                                                      # a hit: a life, back home, and a moment's safety
        rules+=[R(b=b,act=1),R(b=b,act=4,target=0),R(b=b,act=2,value=2),R(b=b,act=3),R(b=b,act=16,target=0)]
    rules+=[R(b=5,act=0,value=50),R(b=5,act=5,target=5),R(b=5,act=2,value=5),
            R(when=2,n=1,act=0,value=1),R(when=2,n=8,act=11,target=1),R(when=2,n=12,act=11,target=3),
            R(when=2,n=16,act=11,target=2),R(when=3,n=300,act=10),R(when=4,act=9),R(when=5,act=2,value=5),
            R(when=5,act=18,value=0)]
    tune=song("Neon",140,[
        bars("Breakbeat",3,"Disco claps",1,"Breakbeat",3,"Disco claps",1,"Breakbeat",3,"Disco claps",1,"Breakbeat",3,"Tom fill",1),
        bars("Acid line",16),
        bars("Offbeat skank",16),
        bars("",8,"Trill",2,"Hook two",2,"Trill",2,"Hook two",2)])
    return make_project("Dodge Ball",pal,im,sprites,actors,rules,[0x300050,0xb02090,0xffa040,118],msg_col=14,
                        win="CHAMPION! - PRESS FIRE",over="KNOCKED OUT - PRESS FIRE",songs=[tune])

# ------------------------------------------------------------------ FIREFLY NIGHT (ADAM Pro: BOBs)
def firefly_night():
    # 0 copper sky, 2 HUD, 4-7 meadow greens, 8 trees, 9-10 moon, 11-12 bark, 14 glow, 15 mist
    pal=[0x000000,0xffffff,0x14183a,0xffb040,0x0a1810,0x16301e,0x2a5232,0x6a9a4a,0x0c0c16,0xfff4c8,0xc8c4a0,0x3a2818,0x806040,0xff5040,0xffee70,0x50608a]
    im=canvas(); d=ImageDraw.Draw(im); P=im.load()
    rnd=random.Random(21)
    for i in range(90):                                                      # stars, a few brighter ones
        x=rnd.randint(0,319); y=rnd.randint(14,120); P[x,y]=1 if rnd.random()<0.25 else 15
    mx,my=246,52                                                             # moon: pale core, soft edge, dithered haze
    for y in range(14,110):
        for x in range(190,310):
            r=math.hypot(x-mx,y-my)
            if r<=15: P[x,y]=9 if math.hypot(x-mx+4,y-my+4)<=12 else dmix(9,10,0.6,x,y)
            elif r<=17: P[x,y]=10
            elif r<=34: P[x,y]=dmix(15,0,(r-17)/17,x,y)
    def far(x): return int(150+math.sin(x/31)*10+math.sin(x/13+1)*4)
    for x in range(320):                                                     # far hills, moonlit edge, darker down
        y=far(x)
        for yy in range(y,256): P[x,yy]=dmix(15,5,0.6,x,yy) if yy-y<2 else ramp([6,5,4],(yy-y-2)/90,x,yy)
    def tree(x,base,h):                                                      # fir silhouettes, a moonlit right edge
        for yy in range(base-h,base+1):
            hw=(yy-(base-h))*7//h+((yy-(base-h))%7)//3
            for xx in range(x-hw,x+hw+1):
                if 0<=xx<W: P[xx,yy]=8
            if 0<=x+hw<W and hw>1: P[x+hw,yy]=dmix(8,15,0.4,x+hw,yy)
        d.rectangle([x-1,base,x+1,base+5],fill=11)
    for x,h in [(14,46),(40,34),(286,40),(306,52)]: tree(x,far(x)+6,h)
    def near(x): return int(206+math.sin(x/37)*7+math.sin(x/11)*2)
    for x in range(320):                                                     # the meadow, lit from the moon side
        y=near(x)
        for yy in range(y,256): P[x,yy]=dmix(7,6,0.5,x,yy) if yy-y<2 else ramp([6,5,4],(yy-y-2)/40,x,yy)
    for i in range(70):                                                      # grass tufts
        x=rnd.randint(2,317); y=near(x)+rnd.randint(2,40)
        if y<255: d.line([(x,y),(x+rnd.choice((-1,1)),y-3)],fill=7)
    d.rectangle([0,0,319,11],fill=2)
    px=list(im.getdata()); text(px,"CATCH THE FIREFLIES - MIND THE BATS",20,246,1); im.putdata(px)
    def grid(fn): return ["".join(".123"[fn(x,y)] for x in range(16)) for y in range(24)]
    def owl(x,y,flap=False):
        inb=lambda xx,yy: ((xx-7.5)/6.5)**2+((yy-12.5)/8.5)**2<=1
        v=0
        if inb(x,y):
            v=1
            if not (inb(x-1,y) and inb(x+1,y) and inb(x,y-1) and inb(x,y+1)): v=2
            if ((x-7.5)/3.6)**2+((y-15.5)/4.6)**2<=1: v=3                     # pale belly
        for ex in (5,10):                                                    # big eyes
            if math.hypot(x-ex,y-9)<=1.9: v=3
            if (x,y) in ((ex,9),(ex,10)): v=2
        if (x,y) in ((7,11),(8,11),(7,12),(8,12)): v=2                         # beak
        if y in (3,4,5) and x in (3,4,12,11) and (y-3)<=(1 if x in (3,12) else 2): v=2   # ear tufts
        if y in (21,22) and x in (5,6,9,10): v=2                               # feet
        if flap and 11<=y<=15 and x in (0,1,14,15): v=2 if y in (11,15) else 1   # wings out
        if not flap and 12<=y<=16 and x in (1,14): v=2                         # wings folded
        return v
    def firefly(x,y,big=True):
        v=0
        r=math.hypot(x-7.5,y-15.5)
        if r<=(4.2 if big else 2.4): v=1                                     # the glowing tail
        if 6<=x<=9 and 9<=y<=13: v=2                                         # body
        if (x,y) in ((7,8),(8,8),(6,8),(9,8)): v=2                           # head
        if (x in (4,5) and y in (9,10)) or (x in (10,11) and y in (9,10)): v=3   # wings
        return v
    def bat(x,y,up=False):
        v=0
        if ((x-7.5)/2.6)**2+((y-12)/3.6)**2<=1: v=1                          # body
        for side in (-1,1):
            for k in range(1,8):
                wx=round(7.5+side*(1.5+k)); top=(9-(k//2) if up else 10+(k//3))
                bot=top+4-(k%3 if not up else (k%2))
                if wx==x and top<=y<=bot: v=1 if y<bot else 2
        if (x,y) in ((6,8),(9,8),(6,7),(9,7)): v=2                           # ears
        if (x,y) in ((6,11),(9,11)): v=3                                     # eyes
        return v
    art.A['ff_owl']=grid(lambda x,y: owl(x,y)); art.A['ff_owl2']=grid(lambda x,y: owl(x,y,True))
    art.A['ff_fly']=grid(lambda x,y: firefly(x,y)); art.A['ff_fly2']=grid(lambda x,y: firefly(x,y,False))
    art.A['ff_bat']=grid(lambda x,y: bat(x,y)); art.A['ff_bat2']=grid(lambda x,y: bat(x,y,True))
    owl_c=[0xa0703a,0x2a1808,0xf0e0b0]; fly_c=[0xffee70,0x3a2818,0xffffff]; bat_c=[0x5a3a7a,0x160c22,0xff4040]
    sprites=[("Owl","ff_owl",owl_c),("Firefly","ff_fly",fly_c),("Bat","ff_bat",bat_c),
             ("Owl flap","ff_owl2",owl_c),("Firefly blink","ff_fly2",fly_c),("Bat flap","ff_bat2",bat_c)]
    actors=[actor("Owl",0,0,2,150,110,3,8,True),
            actor("Bat 1",2,4,1,16,24,5,6),actor("Bat 2",2,2,2,200,70,5,6,left=True),actor("Bat 3",2,1,1,280,170,5,6,left=True,up=True)]
    spots=[(30,40),(80,150),(120,30),(170,180),(220,120),(260,40),(40,190),(100,90),(150,60),(200,30),(270,200),(300,100)]
    for i,(x,y) in enumerate(spots):
        a=actor("Firefly %d"%(i+1),1,1,1+(i%3==0),x,y,4,6+(i%5)*2,left=i%2==1,up=i%3==1); a['bob']=True
        actors.append(a)
    nfly=len(spots); first=4
    rules=[]
    for b in range(first,first+nfly):
        rules+=[R(b=b,act=0,value=10),R(b=b,act=5,target=b),R(b=b,act=2,value=0)]
    for b in (1,2,3):
        rules+=[R(b=b,act=1),R(b=b,act=4,target=0),R(b=b,act=2,value=4),R(b=b,act=3),R(b=b,act=16,target=0)]
    rules+=[R(when=2,n=20,act=11,target=1),R(when=3,n=600,act=10),R(when=4,act=9),
            R(when=5,act=2,value=5),R(when=5,act=16,target=0),R(when=5,act=18,value=0)]
    sfx=sfx_list({0:dict(name="Glow",wave=0,pitch=96,sweep=6,len=5,atk=0,dec=4,sus=0,rel=4),
                  4:dict(name="Swoop",wave=1,pitch=30,sweep=-4,len=10,atk=0,dec=6,sus=2,rel=5),
                  5:dict(name="Night falls",wave=0,pitch=34,sweep=1,len=30,atk=4,dec=8,sus=8,rel=9)})
    tune=song("Moonlight",95,[
        bars("Half time",8,"Rock beat",7,"Tom fill",1),
        bars("",2,"Root pulse",6,"Walking bass",8),
        bars("Long minor",4,"Minor to major",4,"Long minor",4,"Minor to major",4),
        bars("",4,"Long notes",4,"Arp up",2,"Hook one",2,"Arp down",2,"Hook two",2)],loop_bar=2)
    p=make_project("Firefly Night",pal,im,sprites,actors,rules,[0x02030c,0x101a48,0x34305e,165],hud_col=1,msg_col=14,sfx=sfx,
                   win="THE JAR IS FULL! - PRESS FIRE",over="THE BATS WIN - PRESS FIRE",songs=[tune])
    p.update(title_on=True,title1="FIREFLY NIGHT",title2="PRESS FIRE TO START")
    return p

# ------------------------------------------------------------------ helpers
def bob_flags(p):
    # as actors_bob_flags in scr_ws_actors (ADAM Pro): set to BOB, or a sprite actor after the 8th
    out=[]; spr=0
    for a in p['actors'][:32]:
        b=bool(a.get('bob')) or spr>=8
        if not b: spr+=1
        out.append(b)
    return out

def pal_nearest(p,rgb):
    # as pal_nearest in scr_adf: nearest backdrop colour, never colour 0
    best=1; bd=-1
    for c in range(1,1<<p['depth']):
        v=p['pal'][c]
        d=(((v>>16)&255)-((rgb>>16)&255))**2*3+(((v>>8)&255)-((rgb>>8)&255))**2*4+((v&255)-(rgb&255))**2*2
        if bd<0 or d<bd: bd=d; best=c
    return best

def alloc(p):
    acts=p['actors']; key=['']*4; used=[0]*4; owner=[-1]*4; chan=[]; conf=[]; bob=bob_flags(p)
    for i,a in enumerate(acts[:32]):
        if bob[i]: chan.append(-1); conf.append(False); continue
        k=str([q(c) for c in p['sprites'][a['sprite']]['cols']]); pp=-1; cf=False
        for j in range(4):
            if pp<0 and used[j]==1 and key[j]==k: pp=j
        for j in range(4):
            if pp<0 and used[j]==0: pp=j
        for j in range(4):
            if pp<0 and used[j]<2: pp=j; cf=True
        if used[pp]==0: key[pp]=k; owner[pp]=i
        chan.append(pp*2+used[pp]); used[pp]+=1; conf.append(cf)
    return chan,conf,owner

# whole-colour line blending for copper bars - as COPPER_BLEND / copper_blend_lines in scr_gfx
COPPER_BLEND='AAAABAAABAABABABBABBBABBBB'
COPPER_BLEND_SOLID=4

def copper_blend_share(p0,p1):
    # share of B in COPPER_BLEND over [p0,p1) - letters are 1 wide, past the end counts as B
    s=0.0; p=p0
    while p<p1-1e-6:
        c=math.floor(p); e=min(c+1,p1)
        if c>=len(COPPER_BLEND) or (c>=0 and COPPER_BLEND[c]=='B'): s+=e-p
        p=e
    return s/(p1-p0)

def copper_blend_lines(q):
    # q: one rounded colour per line (bands); blend neighbouring bands between their middle lines
    cols=[]; mids=[]; lens=[]; start=0
    for i in range(1,len(q)+1):
        if i==len(q) or q[i]!=q[start]:
            cols.append(q[start]); mids.append((start+i-1)/2); lens.append(i-start); start=i
    # leave out sliver bands (much shorter than their neighbours), shortest first, never the end bands
    while True:
        pick=-1
        for k in range(1,len(lens)-1):
            if lens[k]*4<lens[k-1]+lens[k+1] and (pick<0 or lens[k]<lens[pick]): pick=k
        if pick<0: break
        del cols[pick]; del mids[pick]; del lens[pick]
    n=len(COPPER_BLEND)-COPPER_BLEND_SOLID
    out=[]; b=0; span=-1; carry=0.0
    for j in range(len(q)):
        while b+1<len(cols) and j>=mids[b+1]: b+=1
        if j<mids[b] or b+1>=len(cols): out.append(cols[b]); continue
        if span!=b: span=b; carry=0.0
        l=mids[b+1]-mids[b]; f=(j-mids[b])/l
        carry+=copper_blend_share(COPPER_BLEND_SOLID+f*n,COPPER_BLEND_SOLID+(f+1/l)*n)
        if carry>=0.5: out.append(cols[b+1]); carry-=1
        else: out.append(cols[b])
    return out

def sky_table(p,aga=False):
    # 256 x $RRGGBB as the machine shows them: 12-bit steps (A500/600) or 24-bit (A1200), bands blended
    mx,sc=(255,1) if aga else (15,17)
    q=[]; my=max(1,min(254,p['sky_mid_y']))
    for i in range(256):
        a,b,t=p['sky_top'],p['sky_mid'],i/my
        if i>my: a,b,t=p['sky_mid'],p['sky_bot'],(i-my)/(255-my)
        c=[]
        for s in (16,8,0):
            ca=(a>>s)&255; cb=(b>>s)&255
            c.append(max(0,min(mx,round((ca+(cb-ca)*t)/sc)))*sc)
        q.append((c[0]<<16)|(c[1]<<8)|c[2])
    return copper_blend_lines(q)

def ground_table(p):
    if not any(p.get('solid',[])): return None
    out=[]
    for x in range(W):
        g=256
        for y in range(H):
            if p['solid'][p['pixels'][y*W+x]]: g=y; break
        out.append(g)
    return out

def game_block(p):
    if not (p['levels_on'] or p['goal_on'] or p['title_on']): return None
    lv=[l['heights'] for l in p['levels']] if p['levels_on'] and p['levels'] else [[256]*320]
    return dict(levels=lv,terrain=p['levels_on'] and bool(p['levels']),cols=p['terrain_cols'],goal=p['goal'] if p['goal_on'] else 0,
                title=p['title_on'],label=p['goal_label'],title1=p['title1'],title2=p['title2'],levtxt=p['lev_text'])

def to_builder(p):
    chan,conf,owner=alloc(p)
    spr=[dict(px=s['px'],cols=[q(c) for c in s['cols']]) for s in p['sprites']]
    # pair colours = owner's colours: emulate by giving each actor's sprite the owner colours is the same as build_test's rule
    acts=[]
    for i,a in enumerate(p['actors'][:32]):
        d=dict(x=a['x'],y=a['y'],role=a['role'],speed=a['speed'],visible=int(a['visible']),left=int(a['start_left']),up=int(a['start_up']),
               sprite=a['sprite'],chan=max(0,chan[i]),anim=a['anim_sprite'],rate=a['anim_rate'],amode=int(a['anim_moving']),**{'from':a['from_level'],'fast':a['faster_every']})
        if chan[i]<0:
            d['bob']=1; d['bobmap']=[pal_nearest(p,c) for c in p['sprites'][a['sprite']]['cols']]
        acts.append(d)
    return dict(depth=p['depth'],pal=[q(c) for c in p['pal']],pixels=p['pixels'],sprites=spr,actors=acts,rules=p['rules'],
                sfx=[s for s in p['sfx']],lives=p['lives'],show_score=1,show_lives=1,hud_row=0,hud_col=p['hud_colour'],msg_col=p['msg_colour'],
                over=p['over_text'],win=p['win_text'],grad=sky_table(p),ground=ground_table(p),game=game_block(p)), conf

def preview(p,fn):
    pal=[q(c) for c in p['pal']]; g=sky_table(p)
    im=Image.new('RGB',(W,H))
    for y in range(H):
        sc=g[y]; sr=(sc>>16)&255; sg=(sc>>8)&255; sb=sc&255
        for x in range(W):
            v=p['pixels'][y*W+x]
            if v==0: im.putpixel((x,y),(sr,sg,sb))
            else: c=pal[v]; im.putpixel((x,y),((c>>16)&255,(c>>8)&255,c&255))
    chan,conf,owner=alloc(p)
    for i,a in enumerate(p['actors'][:32]):
        s=p['sprites'][a['sprite']]
        if chan[i]<0: oc=[pal[pal_nearest(p,c)] for c in s['cols']]        # BOB: nearest backdrop colours
        else: oc=p['sprites'][p['actors'][owner[chan[i]//2]]['sprite']]['cols']
        for yy in range(24):
            for xx in range(16):
                v=s['px'][yy*16+xx]
                if v: c=q(oc[v-1]); im.putpixel((a['x']+xx,a['y']+yy),((c>>16)&255,(c>>8)&255,c&255))
    im.resize((640,512),Image.NEAREST).save(fn)

if __name__=='__main__':
    OUT=os.path.join(HERE,'out'); os.makedirs(OUT,exist_ok=True)
    for fn,make in [('gem_hunter',gem_hunter),('deep_dive',deep_dive),('star_catcher',star_catcher),('dodge_ball',dodge_ball),
                    ('firefly_night',firefly_night)]:
        p=make()
        auto_groups(p)
        json.dump(p,open(os.path.join(REPO,'datafiles','examples','%s.adam'%fn),'w'),separators=(',',':'))
        bp,conf=to_builder(p)
        # build_test's pair colour rule takes the first actor on the pair
        open(os.path.join(OUT,'%s.adf'%fn),'wb').write(adf(ENGINE+build(bp,False)))
        preview(p,os.path.join(OUT,'%s.png'%fn))
        print(fn,'conflicts' if any(conf) else 'ok', len(json.dumps(p)))
