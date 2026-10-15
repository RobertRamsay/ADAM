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
    actors=proj['actors']; rules=proj['rules'][:128]
    blob=bytearray()
    def align(n):
        while len(blob)%n: blob.append(0)
    blob+= b'\0'*104                         # header (HDR_SIZE)
    sc=proj.get('scroll')                     # scrolling backdrop: dict(dir 1 up / 2 right / 3 down / 4 left, speed 1..16)
    if sc and (proj.get('tiles') or not sc.get('dir')): sc=None
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
                left=[img(f,not fl) for f in frames] if a.get('flip') and not dirs and (ei<4 or ei==12) else right
                ents.append((len(frames),rate,mode,right,left))
            plans.append(ents)
        else: plans.append(None)
    align(8)
    # animation tables (engine.s AN_*): 4 x { n, rate, mode, 0, 16 right offsets, 16 left offsets }
    anim_offs=[]
    for ents in plans:
        if not ents: anim_offs.append(0); continue
        align(8); anim_offs.append(len(blob))
        for n,rate,mode,right,left in ents:
            blob.extend(struct.pack('>HHHH',n,rate,mode,0))
            for side in (right,left):
                for k in range(16): blob.extend(struct.pack('>L',side[k] if k<n else side[0]))
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
        ts=proj['tiles'].get('size',16) if proj.get('tiles') else 16
        ww,wh=(proj['tiles']['w']*ts,proj['tiles']['h']*ts) if proj.get('tiles') else (320,256)
        up=a.get('aim',0) if a['role']==9 else int(a['up'])   # A_UP of a shot (role 9) = its aim
        blob+=struct.pack('>HHHHHHHHHHHL',min(a['x'],ww-bw),min(a['y'],wh-bh),a['role'],a['speed'],int(a['visible']),int(a['left']),up,bx0,by0,bx1,by1,spr_offs[i])
        aflags=0                                       # A_AMODE bit 0: 8 directions, bit 1: Fire
        if plans[i] and dirs_on(a) and len(plans[i])>=12: aflags|=1
        if plans[i] and len(plans[i])>12: aflags|=2
        blob+=struct.pack('>HLHHHHHHHH',a.get('chan',i),spr2_offs[i],1 if a.get('carry') else 0,aflags,a.get('from',1),a.get('fast',0),
                          1 if a.get('bob') else 0,ww-bw,wh-bh,bsize)
        blob+=struct.pack('>L',anim_offs[i])
        # shoot 'em up (version 9): A_PAT, A_ENTER (byte: comes back, byte: edge 0 top 1 right
        # 2 bottom 3 left), A_HP (hits to destroy), A_RANK (an option's place behind the player)
        rank=0
        if a['role']==11: rank=min(6,1+sum(1 for b in actors[:i] if b['role']==11))
        blob+=struct.pack('>HHHH',max(0,min(5,a.get('pattern',0))),(256 if a.get('comeback') else 0)|(a.get('enter',0)&3),
                          max(1,min(99,a.get('hits',1))),rank)
    align(8)
    off_rules=len(blob)
    for r in rules:
        more=r.get('more',[])[:4]          # AND DO lines: R_NAND, then 8 bytes each (engine.s AND_SIZE)
        sv=lambda d: max(0,min(len(proj['sfx'])-1,d['value'])) if d['act']==2 else d['value']   # sound: below the count
        blob+=struct.pack('>HHHHHHHH',r['when'],r['a'],r['b'],r['n'],r['act'],r['target'],sv(r),len(more))
        for m in more: blob+=struct.pack('>HHHH',m['act'],m['target'],sv(m),0)
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
    # sounds: a table entry for every sound (up to 64), but only the sounds a rule
    # or a dug tile plays take chip RAM (scr_adf sfx_used_on_disk); the rest are length 0
    nsnd=max(1,min(64,len(proj['sfx'])))
    used=[False]*nsnd
    for r in rules:
        for d in [r]+r.get('more',[])[:4]:
            if d['act']==2: used[max(0,min(nsnd-1,d['value']))]=True
    if proj.get('tiles'):
        for td in proj['tiles']['tiles']:
            if td.get('sound',-1)>=0: used[max(0,min(nsnd-1,td['sound']))]=True
    sfx_entries=[]
    for k,s in enumerate(proj['sfx'][:nsnd]):
        if not used[k]: sfx_entries.append((0,0)); continue
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
    # tile world (engine.s T_*): proj['tiles'] = dict(w, h, dig, size (8/16/32/64), tiles=[dict(name,
    # px (size x size colour indexes), solid, dig, hard, points, goal, sound (-1 none), becomes)],
    # map=[w*h tile numbers]). More than 256 tile types: map cells are words.
    off_tiles=0; tile_fix=None
    t=proj.get('tiles')
    if t:
        align(8)
        off_tiles=len(blob)
        nt=len(t['tiles'])
        S=t.get('size',16); sh={8:3,16:4,32:5,64:6}[S]
        ncol=320//S+2; nrow=256//S+2; tline=ncol*S//8; ring=nrow*S*tline
        wcell=nt>256
        blob.extend(struct.pack('>HHHH',t['w'],t['h'],nt,(1 if t.get('dig') else 0)|(2 if wcell else 0)))
        tile_fix=len(blob)
        blob.extend(b'\0'*20)                  # T_IMG T_MAP T_WMAP T_BUF T_BUFPL, filled in below
        tools=t.get('tools',[])[:6] if t.get('dig') else []
        blob.extend(struct.pack('>HHHHHHL',S,sh,tline,ncol,nrow,len(tools),ring))
        for td in t['tiles']:
            fl=(1 if td.get('solid') else 0)|(2 if td.get('dig') else 0)|(4 if td.get('goal') else 0)|(8 if td.get('ladder') else 0)
            snd=td.get('sound',-1); snd=0xff if snd<0 else max(0,min(nsnd-1,snd))
            bec=td.get('becomes',0)
            if bec>=nt: bec=0
            blob.extend(struct.pack('>BBHHH',fl,snd,max(1,td.get('hard',10)),td.get('points',0),bec))
        for td in t['tiles']:
            nm=td['name'].upper().encode('ascii','replace')[:4]
            blob.extend(nm+b'\0'*(4-len(nm)))
        # the space bar menu's tools (engine.s TL_*): 0 dig, 1 build with the tile carried, 2 put a tile
        for tl in tools:
            tt=tl.get('tile',0)
            if tt<0 or tt>=nt: tt=0
            nm=tl['name'].upper().encode('ascii','replace')[:8]
            act=max(0,min(3,tl.get('act',0)))
            if act==3: tt=max(4,min(64,tl.get('reach',20))); act|=0x100 if tl.get('auto') else 0
            blob.extend(struct.pack('>HH',act,tt)+nm+b'\0'*(8-len(nm)))
        align(8)
        off_img=len(blob)
        for td in t['tiles']:
            for p in range(depth):
                for y in range(S):
                    w=0
                    for x in range(S):
                        if (td['px'][y*S+x]>>p)&1: w|=1<<(S-1-x)
                    blob.extend(w.to_bytes(S//8,'big'))
        align(8)
        off_map=len(blob)
        if wcell: blob.extend(b''.join(struct.pack('>H',v) for v in t['map']))
        else: blob.extend(bytes(t['map']))
        align(8)
        struct.pack_into('>LL',blob,tile_fix,off_img,off_map)
    # custom HUD (engine.s UI_*, ADAM Pro): proj['ui'] = dict(bottom, rows, font (512 bytes or None),
    # panel (320 x rows*8 colour indexes or None), fields = [ui_ref field dicts])
    off_ui=0
    u=proj.get('ui')
    if u:
        import ui_ref
        align(8)
        off_ui=len(blob)
        blob.extend(struct.pack('>HHHH',1|(2 if u.get('bottom') else 0),u['rows'],len(u['fields']),0))
        ufix=len(blob)
        blob.extend(b'\0'*8)
        for f in u['fields']: blob.extend(ui_ref.field_bytes(f))
        align(8)
        off_font=0
        if u.get('font'):
            off_font=len(blob); blob.extend(bytes(u['font'])); align(8)
        off_panel=0
        if u.get('panel'):
            off_panel=len(blob)
            pp=u['panel']; h=u['rows']*8
            for pl in range(depth):
                for y in range(h):
                    for bx in range(40):
                        v=0
                        for k in range(8):
                            if (min(pp[y*320+bx*8+k],(1<<depth)-1)>>pl)&1: v|=0x80>>k
                        blob.append(v)
            align(8)
        struct.pack_into('>LL',blob,ufix,off_font,off_panel)
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
    anybob=any(a.get('bob') for a in actors)
    if anybob and not sc:                       # BOBs: second display + background, 8 spare bytes each
        blob+=b'\0'*8                           # (a scrolling game keeps its BOBs in the scroll buffers)
        off_disp2=len(blob); blob+=b'\0'*(depth*10240+8)
        off_back=len(blob); blob+=b'\0'*(depth*10240+8)
    # scrolling backdrop (engine.s SC_*): its block, then the buffers in cleared memory after the data
    off_scroll=0
    if sc:
        align(8)
        off_scroll=len(blob)
        nbuf=3 if anybob else 1
        blob.extend(struct.pack('>HHLHH',sc['dir'],max(1,min(16,sc.get('speed',4))),0,nbuf,0))
        align(8)
    # tile world: the map as played and the scrolling picture go in cleared memory after the data
    bss=0
    if t:
        size_now=(len(blob)+7)//8*8
        bufpl=(2*ring+8+7)//8*8                # the ring, kept twice
        off_wmap=size_now
        off_buf=off_wmap+(t['w']*t['h']*(2 if wcell else 1)+7)//8*8
        bss=off_buf+depth*bufpl-size_now
        struct.pack_into('>LLL',blob,tile_fix+8,off_wmap,off_buf,bufpl)
    if sc:
        size_now=(len(blob)+7)//8*8
        pl=25600 if sc['dir'] in (1,3) else 36864   # SCR_PLV / SCR_PLH
        bss=nbuf*(depth*pl+16)
        struct.pack_into('>L',blob,off_scroll+4,size_now)
    proj['_need']=((len(blob)+7)//8*8)+bss if (t or sc) else 0     # bytes needed from the data start
    player=-1
    for i,a in enumerate(actors):
        if a['role'] in (0,6): player=i; break
    hdr=struct.pack('>4sHHHHHHHHHHHH',b'ADAM',9,1 if aga else 0,depth,len(actors),len(rules),proj['lives'],
                    int(proj['show_score']),int(proj['show_lives']),proj['hud_row'],proj['hud_col'],proj['msg_col'],player & 0xffff)+struct.pack('>L',off_game)
    hdr+=struct.pack('>LLLLLLLLLLLLLLL',off_pal,off_planes,off_act,off_rules,off_sfx,off_over,off_win,off_sprcol,off_disp,off_grad,off_ground,off_work,off_music,off_disp2,off_back)
    hdr+=struct.pack('>LLL',off_tiles,off_ui,off_scroll)
    blob[0:104]=hdr
    return bytes(blob)

# ---- animations (data block version 8, 16 frames); scr_project.gml anim_plan() does the same
# actor dict: anims = 12 x {frames: [sprite indexes, up to 16], rate: 2..30, mode: 0 loop / 1 once / 2 ping-pong}
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
        fr=[f for f in e.get('frames',[])][:16]
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
    filt=s.get('filt',0); fspeed=s.get('fspeed',0); fdepth=s.get('fdepth',0)
    cap=3 if (filt>0 and fspeed>0 and fdepth>0) else 1.5     # scr_sfx.gml sfx_max_seconds
    gate=s['len']/50; rel=min(dr_ms[s['rel']]/1000,cap); total=min(gate+rel,cap)
    n=int(total*rate); out=bytearray(); ph=0; hi=s['pitch']; frame=0; noise=0; lq=0; env=0; rs=0
    atk=max(.001,atk_ms[s['atk']]/1000); dec=max(.001,dr_ms[s['dec']]/1000); sus=s['sus']/15; rl=max(.001,dr_ms[s['rel']]/1000)
    rnd=12345
    fbase=(filt/16)**2; frate=fspeed*0.25; fdep=fdepth/15*3; lp1=lp2=0; peak=0; fl=[]
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
        if filt>0:
            c=fbase*2**(fdep*math.sin(2*math.pi*frate*t)) if frate>0 else fbase
            c=max(.002,min(1,c))
            lp1+=c*(v-lp1); lp2+=c*(lp1-lp2)
            fl.append(lp2*env); peak=max(peak,abs(fl[-1]))
        else: out.append(int(round(max(-1,min(1,v*env*0.9))*127))&255)
    if filt>0:
        g=0.9/peak if peak>0 else 0
        for x in fl: out.append(int(round(max(-1,min(1,x*g))*127))&255)
    return out

def adf(game,need=0):
    """need = bytes the game uses from the data start (tile world: data + cleared memory)"""
    size=(len(game)+511)//512*512
    bss=max(0,len(ENGINE)+need-size)
    boot=bytearray(1024); boot[:len(BOOT)]=BOOT
    struct.pack_into('>LL',boot,len(BOOT)-8,size,bss)
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
