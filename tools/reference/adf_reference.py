# ADAM reference ADF builder.
# A Python copy of scripts/scr_adf (adam_data_block + build_adf). Keep the two in step:
# any change to the data layout must be made in engine.s, scr_adf.gml AND here.
# Run directly to build a small self-test disk: python adf_reference.py [aga]
import struct, math, random, sys
import os
HERE=os.path.dirname(os.path.abspath(__file__))
REPO=os.path.abspath(os.path.join(HERE,'..','..'))
ENGINE_DIR=os.path.join(REPO,'datafiles','engine')
ENGINE=open(os.path.join(ENGINE_DIR,'engine.bin'),'rb').read()
BOOT=open(os.path.join(ENGINE_DIR,'boot.bin'),'rb').read()

def build(proj, aga):
    depth=proj['depth']; ncol=1<<depth
    actors=proj['actors']; rules=proj['rules']
    blob=bytearray()
    def align(n):
        while len(blob)%n: blob.append(0)
    blob+= b'\0'*80
    align(8)
    off_pal=len(blob)
    for i in range(ncol):
        blob+=struct.pack('>L',proj['pal'][i] if i<len(proj['pal']) else 0)
    align(8)
    off_planes=len(blob)
    px=proj['pixels']
    for p in range(depth):
        for y in range(256):
            for xb in range(40):
                v=0
                for b in range(8):
                    if (px[y*320+xb*8+b]>>p)&1: v|=128>>b
                blob.append(v)
    align(8)
    # sprite blocks
    spr_offs=[]; spr2_offs=[]
    def sblock(img):
        align(8); o=len(blob)
        blob.extend(b'\0\0\0\0')
        for y in range(24):
            w0=w1=0
            for x in range(16):
                v=img[y*16+x]
                if v&1: w0|=0x8000>>x
                if v&2: w1|=0x8000>>x
            blob.extend(struct.pack('>HH',w0,w1))
        blob.extend(b'\0\0\0\0'); return o
    for a in actors:
        spr_offs.append(sblock(proj['sprites'][a['sprite']]['px']))
        if a.get('anim',-1)>=0: spr2_offs.append(sblock(proj['sprites'][a['anim']]['px']))
        else: spr2_offs.append(0)
    align(8)
    off_act=len(blob)
    for i,a in enumerate(actors):
        img=proj['sprites'][a['sprite']]['px']
        xs=[x for y in range(24) for x in range(16) if img[y*16+x]]
        ys=[y for y in range(24) for x in range(16) if img[y*16+x]]
        bx0,bx1=(min(xs),max(xs)) if xs else (0,15)
        by0,by1=(min(ys),max(ys)) if ys else (0,23)
        blob+=struct.pack('>HHHHHHHHHHHL',a['x'],a['y'],a['role'],a['speed'],int(a['visible']),int(a['left']),int(a['up']),bx0,by0,bx1,by1,spr_offs[i])
        blob+=struct.pack('>HLHHHH',a.get('chan',i),spr2_offs[i],a.get('rate',8),a.get('amode',0),a.get('from',1),a.get('fast',0))+b'\0'*8
    align(8)
    off_rules=len(blob)
    for r in rules:
        blob+=struct.pack('>HHHHHHHH',r['when'],r['a'],r['b'],r['n'],r['act'],r['target'],r['value'],0)
    align(8)
    off_sprcol=len(blob)
    for pair in range(4):
        cols=[0,0,0]
        for k,a in enumerate(actors):
            if a.get('chan',k)//2==pair:
                cols=proj['sprites'][a['sprite']]['cols']; break
        for c in cols: blob+=struct.pack('>L',c)
    def text(s):
        o=len(blob); blob.extend(s.upper().encode('ascii','replace')[:40]+b'\0'); return o
    off_over=text(proj['over']); off_win=text(proj['win'])
    align(8)
    # sounds
    sfx_entries=[]
    samples=[]
    for s in proj['sfx']:
        align(8)
        o=len(blob); data=render_sfx(s)
        if len(data)%2: data+=b'\0'
        blob+=data; sfx_entries.append((o,len(data)//2))
    align(8)
    off_sfx=len(blob)
    for o,l in sfx_entries: blob+=struct.pack('>LHH',o,l,0)
    align(8)
    off_grad=0
    if proj.get('grad'):
        off_grad=len(blob)
        for c in proj['grad']: blob+=struct.pack('>H',c)
    align(8)
    off_ground=0
    if proj.get('ground'):
        off_ground=len(blob)
        for c in proj['ground']: blob+=struct.pack('>H',c)
    align(8)
    off_game=0
    g=proj.get('game')
    if g:
        off_game=len(blob)
        def fixed(t,n):
            b=t.upper().encode('ascii','replace')[:n-1]; return b+b'\0'*(n-len(b))
        blob.extend(struct.pack('>HHHHHHHH',len(g['levels']),1 if g['terrain'] else 0,*g['cols'],g['goal'],1 if g['title'] else 0))
        blob.extend(fixed(g['label'],8)+fixed(g['title1'],40)+fixed(g['title2'],40)+fixed(g['levtxt'],16))
        for lv in g['levels']:
            for h in lv: blob.extend(struct.pack('>H',h))
    align(8)
    off_work=len(blob)
    blob+=b'\0'*(depth*10240)
    align(8)
    off_disp=len(blob)
    blob+=b'\0'*(depth*10240)
    player=-1
    for i,a in enumerate(actors):
        if a['role'] in (0,6): player=i; break
    hdr=struct.pack('>4sHHHHHHHHHHHH',b'ADAM',1,1 if aga else 0,depth,len(actors),len(rules),proj['lives'],
                    int(proj['show_score']),int(proj['show_lives']),proj['hud_row'],proj['hud_col'],proj['msg_col'],player & 0xffff)+struct.pack('>L',off_game)
    hdr+=struct.pack('>LLLLLLLLLLLL',off_pal,off_planes,off_act,off_rules,off_sfx,off_over,off_win,off_sprcol,off_disp,off_grad,off_ground,off_work)
    blob[0:80]=hdr
    return bytes(blob)

def render_sfx(s):
    rate=3546895/322
    atk_ms=[2,8,16,24,38,56,68,80,100,250,500,800,1000,3000,5000,8000]
    dr_ms=[6,24,48,72,114,168,204,240,300,750,1500,2400,3000,9000,15000,24000]
    gate=s['len']/50; rel=min(dr_ms[s['rel']]/1000,1.5); total=min(gate+rel,1.5)
    n=int(total*rate); out=bytearray(); ph=0; hi=s['pitch']; frame=0; noise=0; lq=0; env=0; rs=0
    atk=max(.001,atk_ms[s['atk']]/1000); dec=max(.001,dr_ms[s['dec']]/1000); sus=s['sus']/15; rl=max(.001,dr_ms[s['rel']]/1000)
    rnd=12345
    for i in range(n):
        t=i/rate; f=int(i/(rate/50))
        if f!=frame:
            frame=f
            if t<gate: hi=(hi+s['sweep']+256)%256
        hz=(hi*256)*985248/16777216
        ph+=hz/rate; ph-=math.floor(ph)
        w=s['wave']
        if w==0: v=1-4*abs(ph-.5)
        elif w==1: v=ph*2-1
        elif w==2: v=1 if ph<.5 else -1
        else:
            q=int(ph*4)
            if q!=lq:
                rnd=(rnd*1103515245+12345)&0x7fffffff; noise=(rnd/0x3fffffff)-1; lq=q
            v=noise
        if t<gate:
            env= t/atk if t<atk else sus+(1-sus)*max(0,1-(t-atk)/dec); rs=env
        else: env=rs*max(0,1-(t-gate)/rl)
        out.append(int(round(max(-1,min(1,v*env*0.9))*127))&255)
    return out

def adf(game):
    size=(len(game)+511)//512*512
    boot=bytearray(1024); boot[:len(BOOT)]=BOOT
    struct.pack_into('>L',boot,len(BOOT)-4,size)
    s=0
    for i in range(256):
        if i==1: continue
        s+=struct.unpack_from('>L',boot,i*4)[0]
        if s>0xffffffff: s=(s&0xffffffff)+1
    struct.pack_into('>L',boot,4,(~s)&0xffffffff)
    img=bytearray(901120); img[:1024]=boot; img[1024:1024+len(game)]=game
    return bytes(img)

def test_project():
    px=[0]*(320*256)
    for y in range(256):
        for x in range(320):
            v=1+((y//16)%7)
            if 40<x<280 and 100<y<160: v=8+((x//20)%7)
            px[y*320+x]=v
    pal=[0x000022,0x223366,0x334488,0x4455aa,0x5566cc,0x6677dd,0x7788ee,0x8899ff,0xff4444,0xffaa22,0xffff44,0x44ff44,0x44ffff,0x8888ff,0xff88ff,0xffffff]
    def spr(fn,cols):
        return {'px':[fn(x,y) for y in range(24) for x in range(16)],'cols':cols}
    hero=spr(lambda x,y: (1 if (x-7.5)**2+(y-11.5)**2<50 else 0) + (2 if abs(x-7.5)<2 and abs(y-8)<2 else 0),[0xffee00,0x000000,0xffffff])
    ghost=spr(lambda x,y: (3 if (x-7.5)**2+(y-11.5)**2<40 else 0),[0xff0000,0x00ff00,0xff66ff])
    gem=spr(lambda x,y: (2 if abs(x-7.5)+abs(y-11.5)<7 else 0),[0x00ffff,0x00ffff,0x00ffff])
    actors=[dict(x=150,y=200,role=0,speed=2,visible=1,left=0,up=0,sprite=0),
            dict(x=20,y=30,role=4,speed=1,visible=1,left=0,up=0,sprite=1,chan=2),
            dict(x=250,y=60,role=1,speed=2,visible=1,left=1,up=0,sprite=1,chan=3),
            dict(x=100,y=120,role=5,speed=1,visible=1,left=0,up=0,sprite=2,chan=4)]
    rules=[dict(when=0,a=0,b=1,n=1,act=1,target=0,value=0),dict(when=0,a=0,b=1,n=1,act=4,target=0,value=0),
           dict(when=0,a=0,b=3,n=1,act=0,target=0,value=10),dict(when=0,a=0,b=3,n=1,act=5,target=3,value=0),
           dict(when=0,a=0,b=3,n=1,act=2,target=0,value=0),dict(when=4,a=0,b=0,n=1,act=9,target=0,value=0),
           dict(when=2,a=0,b=0,n=3,act=3,target=0,value=0),dict(when=3,a=0,b=0,n=50,act=10,target=0,value=0)]
    sfx=[dict(wave=2,pitch=60,sweep=6,len=8,atk=0,dec=6,sus=0,rel=4)]*8
    return dict(depth=4,pal=pal,pixels=px,sprites=[hero,ghost,gem],actors=actors,rules=rules,sfx=sfx,lives=3,
                show_score=1,show_lives=1,hud_row=0,hud_col=15,msg_col=10,over='GAME OVER - PRESS FIRE',win='YOU WIN')

if __name__=='__main__':
    os.makedirs(os.path.join(HERE,'out'),exist_ok=True)
    aga = len(sys.argv)>1 and sys.argv[1]=='aga'
    p=test_project()
    data=build(p,aga)
    game=ENGINE+data
    open(os.path.join(HERE,'out','test.adf'),'wb').write(adf(game))
    print('game bytes',len(game))
