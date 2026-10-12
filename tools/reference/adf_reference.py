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
    blob+= b'\0'*92                          # header (HDR_SIZE)
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
    # sprite dicts: px is w x h (default 16 x 24); pixel (x, y), 0 outside
    def sw(s): return s.get('w',16)
    def sh(s): return s.get('h',24)
    def pix(s,x,y):
        if x<0 or y<0 or x>=sw(s) or y>=sh(s): return 0
        return s['px'][y*sw(s)+x]
    def sblock(s):
        # hardware sprite: the top-left 16 x 24 pixels
        align(8); o=len(blob)
        blob.extend(b'\0\0\0\0')
        for y in range(24):
            w0=w1=0
            for x in range(16):
                v=pix(s,x,y)
                if v&1: w0|=0x8000>>x
                if v&2: w1|=0x8000>>x
            blob.extend(struct.pack('>HH',w0,w1))
        blob.extend(b'\0\0\0\0'); return o
    def bimg(s,cmap,bw,bh):
        # BOB image (engine.s A_BSIZE): bw/16 x bh mask words, then depth planes
        # the same size; sprite pixel 1-3 becomes backdrop colour cmap[0-2]
        align(8); o=len(blob)
        for y in range(bh):
            for wx in range(0,bw,16):
                m=0
                for x in range(16):
                    if pix(s,wx+x,y): m|=0x8000>>x
                blob.extend(struct.pack('>H',m))
        for p in range(depth):
            for y in range(bh):
                for wx in range(0,bw,16):
                    w=0
                    for x in range(16):
                        v=pix(s,wx+x,y)
                        if v and (cmap[v-1]>>p)&1: w|=0x8000>>x
                    blob.extend(struct.pack('>H',w))
        return o
    # actor dict: bob=1 draws it with the blitter, bobmap = backdrop colours for pixels 1-3;
    # a BOB is its sprite's size, a hardware sprite 16 x 24
    def asize(a):
        s=proj['sprites'][a['sprite']]
        if a.get('bob'): return sw(s),sh(s)
        return 16,24
    def flipped(s):
        w,h=sw(s),sh(s)
        return dict(s,px=[s['px'][y*w+(w-1-x)] for y in range(h) for x in range(w)])
    plans=[]
    for a in actors:
        bw,bh=asize(a)
        if a.get('bob'): mk=lambda s,a=a,bw=bw,bh=bh: bimg(s,a['bobmap'],bw,bh)
        else: mk=sblock
        spr_offs.append(mk(proj['sprites'][a['sprite']]))
        # a hopper's crouch frame (two-frame animation of version 4)
        if a['role']==7 and a.get('anim',-1)>=0: spr2_offs.append(mk(proj['sprites'][a['anim']]))
        else: spr2_offs.append(0)
        plan=anim_plan(a)
        if plan:
            made={(a['sprite'],False):spr_offs[-1]}
            def img(si,fl,mk=mk):
                if (si,fl) not in made:
                    sp=proj['sprites'][si]
                    made[(si,fl)]=mk(flipped(sp) if fl else sp)
                return made[(si,fl)]
            ents=[]
            dirs=dirs_on(a)
            for ei,(frames,rate,mode,fl) in enumerate(plan):
                right=[img(f,fl) for f in frames]
                left=[img(f,not fl) for f in frames] if a.get('flip') and not dirs and ei<4 else right
                ents.append((len(frames),rate,mode,right,left))
            plans.append(ents)
        else: plans.append(None)
    align(8)
    # animation tables (engine.s AN_*): 4 x { n, rate, mode, 0, 8 right offsets, 8 left offsets }
    anim_offs=[]
    for ents in plans:
        if not ents: anim_offs.append(0); continue
        align(8); anim_offs.append(len(blob))
        for n,rate,mode,right,left in ents:
            blob.extend(struct.pack('>HHHH',n,rate,mode,0))
            for side in (right,left):
                for k in range(8): blob.extend(struct.pack('>L',side[k%n] if k<n else side[0]))
    align(8)
    off_act=len(blob)
    for i,a in enumerate(actors):
        s=proj['sprites'][a['sprite']]
        bw,bh=asize(a)
        xs=[x for y in range(bh) for x in range(bw) if pix(s,x,y)]
        ys=[y for y in range(bh) for x in range(bw) if pix(s,x,y)]
        bx0,bx1=(min(xs),max(xs)) if xs else (0,bw-1)
        by0,by1=(min(ys),max(ys)) if ys else (0,bh-1)
        bsize=(bh<<6)|(bw//16+1) if a.get('bob') else 0
        blob+=struct.pack('>HHHHHHHHHHHL',min(a['x'],320-bw),min(a['y'],256-bh),a['role'],a['speed'],int(a['visible']),int(a['left']),int(a['up']),bx0,by0,bx1,by1,spr_offs[i])
        aflags=0                                       # A_AMODE bit 0: 8 directions, bit 1: Fire
        if plans[i] and dirs_on(a) and len(plans[i])>=12: aflags|=1
        if plans[i] and len(plans[i])>12: aflags|=2
        blob+=struct.pack('>HLHHHHHHHH',a.get('chan',i),spr2_offs[i],a.get('rate',8),aflags,a.get('from',1),a.get('fast',0),
                          1 if a.get('bob') else 0,320-bw,256-bh,bsize)
        blob+=struct.pack('>L',anim_offs[i])
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
        # $RRGGBB per line: $0RGB high nibbles, then on AGA the low nibbles (the engine writes them with LOCT)
        for c in proj['grad']: blob+=struct.pack('>H',((c>>12)&0xf00)|((c>>8)&0xf0)|((c>>4)&0xf))
        if aga:
            for c in proj['grad']: blob+=struct.pack('>H',((c>>8)&0xf00)|((c>>4)&0xf0)|(c&0xf))
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
    # music table (engine.s M_*): proj['songs'] = list of MOD files as bytes (up to 4),
    # proj['level_song'] = song index per level (10 entries, -1 = none)
    off_music=0
    songs=list(proj.get('songs',[]))[:4]
    if songs:
        align(8)
        off_music=len(blob)
        ls=list(proj.get('level_song',[]))
        lvb=bytearray()
        for lv in range(10):
            v=ls[lv] if lv<len(ls) else -1
            lvb.append(v if 0<=v<len(songs) else 0xff)
        blob.extend(struct.pack('>HH',len(songs),0)+bytes(lvb)+struct.pack('>H',0))
        tab=len(blob)
        blob.extend(b'\0'*(8*len(songs)))
        for i,m in enumerate(songs):
            if len(m)<1084: continue          # not a MOD: the engine keeps quiet
            align(8)
            struct.pack_into('>LL',blob,tab+i*8,len(blob),len(m))
            blob.extend(m)
        align(8)
    off_work=len(blob)
    blob+=b'\0'*(depth*10240)
    align(8)
    off_disp=len(blob)
    blob+=b'\0'*(depth*10240)
    off_disp2=off_back=0
    if any(a.get('bob') for a in actors):       # BOBs: second display + background, 8 spare bytes each
        blob+=b'\0'*8
        off_disp2=len(blob); blob+=b'\0'*(depth*10240+8)
        off_back=len(blob); blob+=b'\0'*(depth*10240+8)
    player=-1
    for i,a in enumerate(actors):
        if a['role'] in (0,6): player=i; break
    hdr=struct.pack('>4sHHHHHHHHHHHH',b'ADAM',5,1 if aga else 0,depth,len(actors),len(rules),proj['lives'],
                    int(proj['show_score']),int(proj['show_lives']),proj['hud_row'],proj['hud_col'],proj['msg_col'],player & 0xffff)+struct.pack('>L',off_game)
    hdr+=struct.pack('>LLLLLLLLLLLLLLL',off_pal,off_planes,off_act,off_rules,off_sfx,off_over,off_win,off_sprcol,off_disp,off_grad,off_ground,off_work,off_music,off_disp2,off_back)
    blob[0:92]=hdr
    return bytes(blob)

# ---- animations (data block version 5); scr_project.gml anim_plan() does the same
# actor dict: anims = 12 x {frames: [sprite indexes, up to 8], rate: 2..30, mode: 0 loop / 1 once / 2 ping-pong}
# (0 Idle, 1 Walk, 2 Jump, 3 Fall, 4..11 = N NE E SE S SW W NW), dirs = use the 8 directions
# instead of Walk, flip = frames turn round to face left (in 8 directions: a missing
# side is the other side turned round); or the version 4 two-frame animation:
# anim = second sprite, rate, amode (1 = only while moving)
DIR_CHAINS=[  # (entry, turned round) tried in order for each direction; 1 = Walk
    [(4,0),(1,0)],                        # N
    [(5,0),(11,1),(6,0),(10,1),(1,0)],    # NE
    [(6,0),(10,1),(1,0)],                 # E
    [(7,0),(9,1),(6,0),(10,1),(1,0)],     # SE
    [(8,0),(1,0)],                        # S
    [(9,0),(7,1),(10,0),(6,1),(1,2)],     # SW  (2 = Walk, turned round when flip is on)
    [(10,0),(6,1),(1,2)],                 # W
    [(11,0),(5,1),(10,0),(6,1),(1,2)]]    # NW

def anim_entries(a):
    out=[]
    for k in range(21):
        e=a.get('anims',[])[k] if k<len(a.get('anims',[])) else {}
        fr=[f for f in e.get('frames',[])][:8]
        out.append((fr,max(2,min(30,e.get('rate',8))),max(0,min(2,e.get('mode',0))),0) if fr else None)
    return out

def anims_used(a):
    return any(e for e in anim_entries(a))

def dirs_on(a):
    """the 8 directions are used (instead of Walk) when any of them has frames"""
    return any(e for e in anim_entries(a)[4:12])

def fire_used(a):
    return any(e for e in anim_entries(a)[12:21])

def resolve_dirs(ents,base_k,walk,flip):
    """8 directions from entries base_k..base_k+7 with DIR_CHAINS (entry 1 = walk)"""
    dirs=[]
    for chain in DIR_CHAINS:
        got=None
        for k,t in chain:
            if t==1 and not flip: continue
            src=walk if k==1 else ents[k-4+base_k]
            if src:
                fr,rt,md,_=src
                got=(fr,rt,md,1 if (t==1 or (t==2 and flip)) else 0); break
        dirs.append(got)
    for d in range(8):                         # nothing at all: east (or west)
        if not dirs[d]: dirs[d]=dirs[2] or dirs[6]
    return dirs

def anim_plan(a):
    """None for one frame, else 4 (12 with 8 directions, 21 with Fire) x (frames, rate, mode, turned round)"""
    base=a['sprite']
    if anims_used(a):
        ents=anim_entries(a)
        flip=bool(a.get('flip'))
        idle,walk,jump,fall=ents[:4]
        if dirs_on(a):
            dirs=resolve_dirs(ents,4,walk or idle,flip)
            dirs=[d or ([base],8,0,0) for d in dirs]
            if not idle: idle=([base],8,3,0)              # stand facing the last direction
            if not walk: walk=dirs[2]
        else:
            if not idle: idle=walk if walk else ([base],8,0,0)
            if not walk: walk=idle
            dirs=None
        if not jump: jump=walk
        if not fall: fall=jump
        out=[idle,walk,jump,fall]
        if fire_used(a):
            if dirs is None: dirs=[walk]*8                # not used without 8 directions
            fstand=ents[12]
            fd=resolve_dirs(ents,13,fstand,flip)
            if not fstand: fstand=fd[2] or fd[6] or idle
            fd=[d or fstand for d in fd]
            return out+dirs+[fstand]+fd
        return out+dirs if dirs else out
    if a.get('anim',-1)>=0 and a['role']!=7:
        rate=max(2,min(30,a.get('rate',8)))
        both=([base,a['anim']],rate,0,0)
        idle=([base],rate,0,0) if a.get('amode',0) else both
        return [idle,both,both,both]
    return None

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
