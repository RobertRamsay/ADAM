# Generates the four example projects (datafiles/examples/*.adam) plus test ADFs and previews in tools/reference/out.
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

def make_project(name,pal16,img,sprites,actors,rules,sky,hud_col=1,msg_col=14,lives=3,over="GAME OVER - PRESS FIRE",win="YOU WIN! - PRESS FIRE",sfx=None):
    pal=palette_default(); pal[:16]=pal16
    spr=[]
    for i in range(32):
        if i<len(sprites):
            n,a,cols=sprites[i]; spr.append(dict(name=n,px=art.px(a),cols=cols))
        else: spr.append(dict(name="Sprite %d"%(i+1),px=[0]*384,cols=[0xffdd33,0xdd3322,0xffffff]))
    return dict(version=1,name=name,machine="A500_600",depth=4,pal=pal,pixels=list(img.getdata()),sprites=spr,actors=actors,rules=rules,
                sfx=sfx or sfx_list(),lives=lives,show_score=True,show_lives=True,hud_row=0,hud_colour=hud_col,msg_colour=msg_col,
                over_text=over,win_text=win,solid=[0]*128,levels_on=False,levels=[],terrain_cols=[10,9,11,12],goal_on=False,goal=20,goal_label='GEMS',title_on=False,title1=name.upper(),title2='PRESS FIRE TO START',lev_text='LEVEL',sky_on=True,sky_top=sky[0],sky_mid=sky[1],sky_bot=sky[2],sky_mid_y=sky[3])

def canvas(): return Image.new('P',(W,H),0)

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
    im=canvas(); d=ImageDraw.Draw(im)
    d.ellipse([196,60,260,124],fill=3); d.ellipse([208,72,248,112],fill=7)   # sun
    for x in range(320):                                                     # far mountains
        y=int(130-abs(((x+40)%110)-55)*1.1-10*math.sin(x/17))
        d.line([(x,y),(x,255)],fill=4)
        if y<94: d.line([(x,y),(x,min(94,y+6))],fill=6)
    for x in range(320):                                                     # distant green hills
        y=int(150+math.sin(x/23)*8+math.sin(x/9)*3)
        d.line([(x,y),(x,255)],fill=15)
    rnd=random.Random(3)
    for t in range(12):                                                      # far trees
        x=rnd.randint(8,310); base=int(150+math.sin(x/23)*8+math.sin(x/9)*3)+3
        d.polygon([(x,base-12),(x-4,base),(x+4,base)],fill=8)
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
    p=make_project("Gem Hunter",pal,im,sprites,actors,rules,[0x101848,0x5a6ac8,0xffa850,150],hud_col=1,msg_col=14,sfx=sfx,
                   win="CONGRATULATIONS! ALL 10 LEVELS DONE")
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
    im=canvas(); d=ImageDraw.Draw(im)
    # surface ripples
    for x in range(320):
        y=14+round(math.sin(x/9)*2)
        d.line([(x,12),(x,y)],fill=6)
    # light rays
    for k in range(5):
        x0=30+k*70
        for y in range(16,170,3):
            w=2+y//40
            if (y//3)%2==0: d.line([(x0+y//6,y),(x0+y//6+w,y)],fill=7)
    # sand dunes
    for x in range(320):
        y=212+round(math.sin(x/29)*8+math.sin(x/11)*3)
        d.line([(x,y),(x,255)],fill=11)
        d.line([(x,y),(x,y+3)],fill=12)
    for i in range(160):
        rnd=random.Random(i)
        x=rnd.randint(0,319); y=rnd.randint(222,254); im.putpixel((x,y),12)
    # rocks
    for (x,y,r) in [(40,214,18),(270,210,22),(150,222,12)]:
        d.ellipse([x-r,y-r//1.4,x+r,y+r//1.4],fill=4); d.ellipse([x-r+4,y-r//1.4+2,x+r-6,y],fill=5)
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
           R(when=1,act=2,value=7),R(when=2,n=15,act=11,target=3),R(when=3,n=300,act=10),R(when=4,act=9),R(when=5,act=2,value=5)]
    sfx=sfx_list({7:dict(name="Bubble",wave=0,pitch=70,sweep=5,len=6,atk=0,dec=4,sus=0,rel=3)})
    return make_project("Deep Dive",pal,im,sprites,actors,rules,[0x70d8f0,0x1868a8,0x021028,95],sfx=sfx,msg_col=14,
                        win="YOU FOUND THEM ALL!",over="OUT OF AIR - PRESS FIRE")

# ------------------------------------------------------------------ STAR CATCHER
def star_catcher():
    pal=[0x000000,0xffffff,0x182848,0xff8030,0x403850,0x8070a0,0xc0c8ff,0x90a0ff,0x2a1840,0x6a3a8a,0xb070e0,0x6a4030,0xc08050,0xe05040,0xffe070,0x9098a8]
    im=canvas(); d=ImageDraw.Draw(im)
    rnd=random.Random(11)
    for i in range(220):
        x=rnd.randint(0,319); y=rnd.randint(14,255); c=rnd.choice([1,15,15,6,14])
        im.putpixel((x,y),c)
        if rnd.random()<0.08:
            for dx,dy in((1,0),(-1,0),(0,1),(0,-1)):
                if 0<=x+dx<W and 0<=y+dy<H: im.putpixel((x+dx,y+dy),15)
    # nebula wisps
    for i in range(900):
        a=rnd.random()*6.28; r=rnd.random()**0.5*60
        x=int(90+math.cos(a)*r*1.6); y=int(110+math.sin(a)*r*0.6)
        if 0<=x<W and 0<=y<H and rnd.random()<0.5: im.putpixel((x,y),8 if r>35 else 9)
    # planet with shading and rings
    cx,cy,r=250,215,70
    d.ellipse([cx-r,cy-r,cx+r,cy+r],fill=11)
    for y in range(cy-r,cy+r):
        for x in range(cx-r,cx+r):
            if (x-cx)**2+(y-cy)**2<=r*r and 0<=y<H:
                band=((y-cy)//9)%3
                c=[12,3,11][band]
                if (x-cx+20)**2+(y-cy+20)**2>r*r*1.1: c=4 if c!=3 else 13
                im.putpixel((x,y),c)
    d.arc([cx-110,cy-22,cx+110,cy+22],200,340,fill=7,width=2)
    # moon
    d.ellipse([30,30,62,62],fill=15); d.ellipse([40,26,72,58],fill=0); d.ellipse([34,44,40,50],fill=4)
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
           R(when=1,act=2,value=1),R(when=2,n=20,act=11,target=3),R(when=3,n=250,act=10),R(when=4,act=9),R(when=5,act=2,value=5)]
    return make_project("Star Catcher",pal,im,sprites,actors,rules,[0x000000,0x1a0838,0x0a1840,140],msg_col=14,
                        win="GALAXY SAVED! - PRESS FIRE",over="SHIP LOST - PRESS FIRE")

# ------------------------------------------------------------------ DODGE BALL
def dodge_ball():
    pal=[0x000000,0xffffff,0x200040,0xff9020,0x180828,0x301850,0xff40c0,0x40e0ff,0x101830,0x2a2a60,0x6060c0,0x402060,0x8040a0,0xff3040,0xfff060,0x9090b0]
    im=canvas(); d=ImageDraw.Draw(im)
    # skyline
    rnd=random.Random(5)
    x=0
    while x<320:
        w=rnd.randint(14,30); h=rnd.randint(20,70)
        d.rectangle([x,128-h,x+w-2,128],fill=5)
        for wy in range(128-h+4,126,6):
            for wx in range(x+3,x+w-4,5):
                if rnd.random()<0.35: d.rectangle([wx,wy,wx+1,wy+2],fill=14)
        x+=w
    # floor + perspective grid
    d.rectangle([0,128,319,255],fill=4)
    for i in range(-10,21):
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
    for b in (1,2,3,4):
        rules+=[R(b=b,act=1),R(b=b,act=4,target=0),R(b=b,act=2,value=2),R(b=b,act=3)]
    rules+=[R(b=5,act=0,value=50),R(b=5,act=5,target=5),R(b=5,act=2,value=5),
            R(when=2,n=1,act=0,value=1),R(when=2,n=8,act=11,target=1),R(when=2,n=12,act=11,target=3),
            R(when=2,n=16,act=11,target=2),R(when=3,n=300,act=10),R(when=4,act=9),R(when=5,act=2,value=5)]
    return make_project("Dodge Ball",pal,im,sprites,actors,rules,[0x300050,0xb02090,0xffa040,118],msg_col=14,
                        win="CHAMPION! - PRESS FIRE",over="KNOCKED OUT - PRESS FIRE")

# ------------------------------------------------------------------ helpers
def alloc(p):
    acts=p['actors']; key=['']*4; used=[0]*4; owner=[-1]*4; chan=[]; conf=[]
    for i,a in enumerate(acts[:8]):
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
    for i,a in enumerate(p['actors']):
        acts.append(dict(x=a['x'],y=a['y'],role=a['role'],speed=a['speed'],visible=int(a['visible']),left=int(a['start_left']),up=int(a['start_up']),
                         sprite=a['sprite'],chan=chan[i],anim=a['anim_sprite'],rate=a['anim_rate'],amode=int(a['anim_moving']),**{'from':a['from_level'],'fast':a['faster_every']}))
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
    for i,a in enumerate(p['actors']):
        oc=p['sprites'][p['actors'][owner[chan[i]//2]]['sprite']]['cols']
        s=p['sprites'][a['sprite']]
        for yy in range(24):
            for xx in range(16):
                v=s['px'][yy*16+xx]
                if v: c=q(oc[v-1]); im.putpixel((a['x']+xx,a['y']+yy),((c>>16)&255,(c>>8)&255,c&255))
    im.resize((640,512),Image.NEAREST).save(fn)

if __name__=='__main__':
    OUT=os.path.join(HERE,'out'); os.makedirs(OUT,exist_ok=True)
    for fn,make in [('gem_hunter',gem_hunter),('deep_dive',deep_dive),('star_catcher',star_catcher),('dodge_ball',dodge_ball)]:
        p=make()
        auto_groups(p)
        json.dump(p,open(os.path.join(REPO,'datafiles','examples','%s.adam'%fn),'w'),separators=(',',':'))
        bp,conf=to_builder(p)
        # build_test's pair colour rule takes the first actor on the pair
        open(os.path.join(OUT,'%s.adf'%fn),'wb').write(adf(ENGINE+build(bp,False)))
        preview(p,os.path.join(OUT,'%s.png'%fn))
        print(fn,'conflicts' if any(conf) else 'ok', len(json.dumps(p)))
