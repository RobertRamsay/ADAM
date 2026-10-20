# Nebula Strike and Starfire - the shoot 'em up examples (ADAM Pro): a scrolling backdrop
# that loops (across / up), waves of flyers, power-up capsules (P firepower, S speed,
# M a multiple that follows the ship and fires too), tough enemies, a boss and a warp gate.
# Made by gen_examples.py: python gen_examples.py
import math, random
from PIL import Image, ImageDraw
import gen_examples as g

TAU = 2 * math.pi

# ------------------------------------------------------------------ pixel art helpers
# Sprites are drawn as 'L' images with values 0 (clear) and 1..3 (the sprite's three
# colours: 1 main, 2 dark, 3 light), then turned into ADAM sprite dicts of any size.
def new(w, h):
    im = Image.new('L', (w, h), 0)
    return im, ImageDraw.Draw(im)

def rim(im, lx=-1, ly=-1, keep=(2, 3)):
    """body pixels (1) on an edge facing the light (lx, ly) become 3, on the far edge 2"""
    w, h = im.size
    src = im.copy().load()
    px = im.load()
    def clear(x, y):
        return not (0 <= x < w and 0 <= y < h) or src[x, y] == 0
    for y in range(h):
        for x in range(w):
            if src[x, y] != 1: continue
            if (lx and clear(x + lx, y)) or (ly and clear(x, y + ly)): px[x, y] = 3
            elif (lx and clear(x - lx, y)) or (ly and clear(x, y - ly)): px[x, y] = 2
    return im

def outline(im, col=2):
    """a dark edge round everything drawn"""
    w, h = im.size
    src = im.copy().load()
    px = im.load()
    for y in range(h):
        for x in range(w):
            if src[x, y] == 0: continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                xx, yy = x + dx, y + dy
                if not (0 <= xx < w and 0 <= yy < h) or src[xx, yy] == 0:
                    px[x, y] = col
                    break
    return im

def flip_h(im): return im.transpose(Image.FLIP_LEFT_RIGHT)

def spr(name, im, cols):
    w, h = im.size
    return dict(name=name, w=w, h=h, px=list(im.getdata()), cols=list(cols))

def put(im, x, y, v):
    if 0 <= x < im.size[0] and 0 <= y < im.size[1]: im.putpixel((x, y), v)

# 5 x 5 letters for the capsules
LETTER = {'P': ["1111.", "1...1", "1111.", "1....", "1...."],
          'S': [".1111", "1....", ".111.", "....1", "1111."],
          'M': ["1...1", "11.11", "1.1.1", "1...1", "1...1"]}

def capsule(letter, shine):
    """16 x 24 hardware sprite: a rounded capsule with a letter, the shine moves along it"""
    im, d = new(16, 24)
    d.rounded_rectangle([1, 7, 14, 16], radius=4, fill=2)
    d.rounded_rectangle([2, 8, 13, 15], radius=3, fill=1)
    for k in range(3, 13):
        if (k - shine) % 10 in (0, 1): put(im, k, 8, 3)
    for r, row in enumerate(LETTER[letter]):
        for c, ch in enumerate(row):
            if ch == '1': put(im, 6 + c, 9 + r, 3)
    return im

def orb(r, pulse):
    """16 x 24: a glowing ball (an option / a plasma shot)"""
    im, _ = new(16, 24)
    cx, cy = 7.5, 11.5
    rr = r + pulse * 0.6
    for y in range(24):
        for x in range(16):
            dd = math.hypot(x - cx, y - cy)
            if dd <= rr * 0.45: put(im, x, y, 3)
            elif dd <= rr * 0.8: put(im, x, y, 1)
            elif dd <= rr: put(im, x, y, 2)
    return im

def boom(w, h, f, n, seed):
    """explosion frame f of n: a hot core that swells into a ring of fire, then smoke and sparks.
    3 = brightest (yellow / white), 1 = fire, 2 = dark red embers"""
    im, _ = new(w, h)
    rnd = random.Random(seed)
    cx, cy = (w - 1) / 2, (h - 1) / 2
    R = min(w, h) / 2 - 1
    t = (f + 1) / n
    rad = R * (0.35 + 0.65 * math.sqrt(t))
    blobs = [(rnd.uniform(0, TAU), rnd.uniform(0.3, 0.95)) for _ in range(9)]
    for y in range(h):
        for x in range(w):
            dx, dy = (x - cx), (y - cy) * (w / h if w > h else 1)
            dd = math.hypot(dx, dy)
            ang = math.atan2(dy, dx)
            wob = 1 + 0.18 * math.sin(ang * 5 + seed) + 0.1 * math.sin(ang * 9 + f)
            edge = rad * wob
            if dd > edge: continue
            k = dd / max(1, edge)
            n1 = ((x * 7 + y * 13 + f * 5 + seed) % 11) / 11
            if t < 0.35:                                   # the flash
                v = 3 if k < 0.7 else 1
            elif t < 0.7:                                  # a ball of fire
                v = 3 if k < 0.35 else (1 if k < 0.8 else 2)
                if n1 < 0.15 and k > 0.5: v = 2
            else:                                          # burning out: a ring, holes in it
                if k < 0.45: v = 2 if n1 < 0.5 else 0
                elif k < 0.8: v = 1 if n1 > 0.3 else 2
                else: v = 2 if n1 > 0.45 else 0
            put(im, x, y, v)
    for (a, r) in blobs:                                   # sparks flying out
        dist = R * (0.3 + 0.75 * t) * r + 2
        x = int(round(cx + math.cos(a) * dist)); y = int(round(cy + math.sin(a) * dist * (h / w if w > h else 1)))
        put(im, x, y, 3 if t < 0.8 else 1)
        if t > 0.4: put(im, x - int(round(math.cos(a))), y - int(round(math.sin(a))), 2)
    return im

def warp(w, f):
    """a spinning ring portal"""
    im, _ = new(w, w)
    c = (w - 1) / 2
    for y in range(w):
        for x in range(w):
            dd = math.hypot(x - c, y - c)
            a = math.atan2(y - c, x - c)
            if c - 5 <= dd <= c:
                seg = int((a + TAU) / TAU * 12 + f) % 3
                put(im, x, y, (1, 3, 2)[seg])
            elif c - 8 <= dd < c - 5:
                put(im, x, y, 2)
            elif dd < c - 8 and ((int(dd) + f) % 4 == 0):
                put(im, x, y, 1)
    return im

# ------------------------------------------------------------------ project helpers
def blank(i): return dict(name="Sprite %d" % (i + 1), w=16, h=24, px=[0] * 384, cols=[0xffdd33, 0xdd3322, 0xffffff])

class Bank:
    """the sprite bank: pictures added in order, animations made from their slots"""
    def __init__(self):
        self.s = []
        self.idx = {}
    def add(self, name, im, cols):
        self.idx[name] = len(self.s)
        self.s.append(spr(name, im, cols))
        return self.idx[name]
    def __getitem__(self, name): return self.idx[name]

def anims_of(entries):
    """entries: {anim number: (frames, rate, mode)} -> the 21 animations of an actor"""
    out = [dict(frames=[], rate=8, mode=0) for _ in range(21)]
    for k, (fr, rate, mode) in entries.items():
        out[k] = dict(frames=list(fr), rate=rate, mode=mode)
    return out

def act(name, sprite, role, speed, x, y, vis=True, bob=False, pattern=0, enter=0, comeback=True, hits=1, aim=0,
        anims=None, frm=1, fast=0, left=False, up=False):
    a = g.actor(name, sprite, role, speed, x, y, vis=vis, left=left, up=up)
    a.update(bob=bob, pattern=pattern, enter=enter, comeback=comeback, hits=hits, aim=aim, carry=False,
             anim_flip=False, anim_dirs=False, from_level=frm, faster_every=fast)
    a['anims'] = anims_of(anims or {})
    return a

def periodic_hills(base, terms):
    """320 heights that join up at the ends (the picture loops), terms = [(waves per screen, height, phase)]"""
    out = []
    for x in range(320):
        y = base
        for k, amp, ph in terms: y += amp * math.sin(TAU * k * x / 320 + ph)
        out.append(max(100, min(240, int(round(y)))))
    return out

SFX = {0: dict(name="Laser", wave=2, pitch=150, sweep=-14, len=5, atk=0, dec=4, sus=0, rel=3),
       1: dict(name="Explosion", wave=3, pitch=30, sweep=-1, len=16, atk=0, dec=8, sus=2, rel=8),
       2: dict(name="Big boom", wave=3, pitch=18, sweep=-1, len=40, atk=0, dec=11, sus=6, rel=11),
       3: dict(name="Power up", wave=2, pitch=40, sweep=6, len=22, atk=0, dec=6, sus=8, rel=5),
       4: dict(name="Warning", wave=0, pitch=70, sweep=-3, len=30, atk=1, dec=7, sus=10, rel=6),
       5: dict(name="Ready", wave=2, pitch=50, sweep=4, len=16, atk=1, dec=6, sus=6, rel=6),
       6: dict(name="Lose", wave=1, pitch=60, sweep=-3, len=30, atk=0, dec=9, sus=6, rel=9),
       7: dict(name="Warp", wave=0, pitch=24, sweep=9, len=40, atk=2, dec=8, sus=10, rel=9)}
LASER, BOOM, BIGBOOM, POWER, WARNING, READY, LOSE, WARPS = range(8)

def songs():
    main = g.song("Strike force", 140, [
        g.bars("Breakbeat", 3, "Tom fill", 1, "Breakbeat", 3, "Disco claps", 1, "Breakbeat", 3, "Tom fill", 1, "Four on the floor", 7, "Tom fill", 1),
        g.bars("Acid line", 8, "Octave bounce", 8, "Acid line", 4),
        g.bars("Rising chords", 8, "Minor to major", 4, "Rising chords", 8),
        g.bars("", 4, "Arp up", 2, "Arp down", 2, "Hook one", 2, "Hook two", 2, "Arp up", 2, "Trill", 2, "Hook one", 2, "Hook two", 2)], loop_bar=4)
    boss = g.song("Boss", 150, [
        g.bars("Four on the floor", 3, "Tom fill", 1, "Four on the floor", 3, "Tom fill", 1),
        g.bars("Acid line", 8),
        g.bars("Long minor", 4, "Offbeat skank", 4),
        g.bars("Trill", 2, "Arp down", 2, "Trill", 2, "Arp up", 2)])
    return [main, boss]

def group_key(names):
    def key(r):
        w = r['when']
        if w == 14: return "Fire (hold for auto-fire)"
        if w == 11 and names[r['b']]['role'] == 0: return "Ship hit by plasma"
        if w == 11 and names[r['b']]['name'].startswith("Boss"): return "Boss"
        if w == 11: return "Lasers hit enemies"
        if w == 0 and names[r['b']]['name'].startswith("Capsule"): return "Power-up capsules"
        if w == 0 and names[r['b']]['name'].startswith("Warp"): return "Warp gate"
        if w == 0: return "Ship hit by enemies"
        if w == 9: return "Enemies fire"
        if w == 13: return "Boss"
        return "Game flow"
    return key

def common_rules(R, A, enemies, carriers, shooters, laser_snd=True):
    """A: name -> actor index. enemies: [(name, points, back to start or random spot)].
    carriers: {enemy name: capsule it drops}. shooters: [(name, seconds)]"""
    ship, laser, plasma, boom0, big = A['Ship'], A['Laser 1'], A['Plasma 1'], A['Boom 1'], A['Big boom']
    rules = []
    rules += [R(when=14, n=7, act=22, target=laser, value=ship)]
    if laser_snd: rules += [R(when=14, n=7, act=2, value=LASER)]
    for nm, pts, home in enemies:                          # a laser hits an enemy: score, explosion, back again
        e = A[nm]
        rules += [R(when=11, a=laser, b=e, act=0, value=pts), R(when=11, a=laser, b=e, act=24, target=boom0, value=e),
                  R(when=11, a=laser, b=e, act=2, value=BOOM)]
        if nm in carriers:                                 # it drops a capsule
            c = A[carriers[nm]]
            rules += [R(when=11, a=laser, b=e, act=14, target=c, value=e), R(when=11, a=laser, b=e, act=7, target=c)]
        rules += [R(when=11, a=laser, b=e, act=4 if home else 5, target=e)]
    for nm, kind in (("Capsule P", 0), ("Capsule S", 1), ("Capsule M", 2)):   # pick up a capsule
        c = A[nm]
        rules += [R(b=c, act=23, value=kind), R(b=c, act=6, target=c), R(b=c, act=2, value=POWER), R(b=c, act=0, value=500)]
    def hit(when, a, b, boom_at):                          # the ship is hit: explodes, back to the start, loses its power-ups
        return [R(when=when, a=a, b=b, act=1), R(when=when, a=a, b=b, act=24, target=boom0, value=ship),
                R(when=when, a=a, b=b, act=2, value=LOSE), R(when=when, a=a, b=b, act=3),
                R(when=when, a=a, b=b, act=23, value=3),
                R(when=when, a=a, b=b, act=4, target=ship), R(when=when, a=a, b=b, act=16, target=ship)]
    for nm, pts, home in enemies:
        e = A[nm]
        rules += hit(0, ship, e, ship) + [R(a=ship, b=e, act=24, target=boom0, value=e), R(a=ship, b=e, act=4 if home else 5, target=e)]
    rules += hit(0, ship, A['Boss'], ship)
    rules += hit(11, plasma, ship, ship)
    for nm, secs in shooters:                              # enemies fire plasma at the ship while on the screen
        rules += [R(when=9, a=A[nm], n=secs, act=22, target=plasma, value=A[nm])]
    boss = A['Boss']; warpg = A['Warp gate']
    rules += [R(when=11, a=laser, b=boss, act=0, value=5000), R(when=11, a=laser, b=boss, act=24, target=big, value=boss),
              R(when=11, a=laser, b=boss, act=24, target=boom0, value=boss), R(when=11, a=laser, b=boss, act=2, value=BIGBOOM),
              R(when=11, a=laser, b=boss, act=6, target=boss),
              R(when=11, a=laser, b=boss, act=7, target=warpg), R(when=11, a=laser, b=boss, act=3), R(when=11, a=laser, b=boss, act=18, value=0)]
    rules += [R(b=warpg, act=2, value=WARPS), R(b=warpg, act=0, value=1000), R(b=warpg, act=6, target=warpg), R(b=warpg, act=17)]
    return rules

def boss_arrives(R, A, hide, secs=45):
    out = [R(when=13, n=secs, act=7, target=A['Boss']), R(when=13, n=secs, act=18, value=1), R(when=13, n=secs, act=2, value=WARNING),
           R(when=13, n=secs, act=3)]
    for nm in hide: out.append(R(when=13, n=secs, act=6, target=A[nm]))
    return out

def flow(R, A):
    return [R(when=4, act=9), R(when=5, act=18, value=0), R(when=7, act=16, target=A['Ship']), R(when=7, act=2, value=READY)]

def finish(p, songs_list, title1, title2, hud_style, hud_font):
    set_depth(p)                        # first, so the HUD's colours are ones the screen shows
    p['songs'] = songs_list
    p['level_song'] = [0] * 10
    p.update(title_on=True, title1=title1, title2=title2, lev_text="STAGE", goal_on=True, goal=1, goal_label="WARP")
    g.dress_ui(p, hud_style, hud_font, 1, [(1, "SCORE ", 1, 0, 0xffffff, 0x101020, 6), (5, "STAGE ", 16, 0, 0xffe040, 0x101020, 1),
                                           (2, "SHIPS ", 31, 0, 0x60e0ff, 0x101020, 1)])

AGA_DEPTH = 6

def aga_cap():
    # the A1200 versions use 64 colours (16 + 48 in-between shades): the blitter has
    # BOBs to draw every frame, and 6 bitplanes still leave it the time for them
    g.AGA['max'] = 1 << AGA_DEPTH

def set_depth(p):
    if p['machine'] == "A1200":
        p['depth'] = AGA_DEPTH
        assert max(p['pixels']) < (1 << AGA_DEPTH)
    g.AGA['max'] = 128

# ================================================================== NEBULA STRIKE (across)
def nebula_strike():
    aga_cap()
    # 0 sky, 1 white, 2 HUD, 3 orange, 4-6 nebula, 7 cyan, 8-10 steel, 11-12 reds, 13 yellow, 14-15 teal (hills)
    pal = [0x000000, 0xffffff, 0x182040, 0xff8020, 0x281040, 0x582888, 0xc048c0, 0x40d8ff,
           0x303850, 0x6878a0, 0xb8c8e8, 0x881828, 0xe83838, 0xffe040, 0x0c5050, 0x30b8a0]
    im = g.canvas(); P = im.load()
    rnd = random.Random(77)
    T = TAU / 320
    # two bands of nebula that join up at the picture's ends
    for y in range(8, 210):
        for x in range(320):
            band = math.exp(-((y - 70) / 34) ** 2) * (0.75 + 0.25 * math.sin(x * T * 2 + 0.4)) \
                 + 0.8 * math.exp(-((y - 150 - 14 * math.sin(x * T * 3 + 1.1)) / 22) ** 2) * (0.6 + 0.4 * math.sin(x * T * 1 + 2.2))
            wisp = 0.22 * math.sin(x * T * 5 + y / 13) * math.sin(y / 9 - x * T * 3) + 0.12 * math.sin(x * T * 9 + y / 5)
            t = band + wisp - 0.32
            if t > 0: P[x, y] = g.ramp([0, 4, 5, 6], min(1.0, t * 1.15), x, y)
    for i in range(260):                                   # stars: mostly dim, a few bright ones that twinkle into crosses
        x = rnd.randint(0, 319); y = rnd.randint(9, 200)
        if P[x, y] not in (0, 4): continue
        c = rnd.choice([8, 8, 9, 9, 10, 7, 1])
        P[x, y] = c
        if c == 1 and rnd.random() < 0.5:
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                if 0 <= y + dy < 256: P[(x + dx) % 320, y + dy] = 10
    # far spires of an alien city, lit in teal from the nebula, a few lit windows
    def ridge(x): return int(176 + 10 * math.sin(x * T * 2 + 0.5) + 6 * math.sin(x * T * 7 + 1.3))
    towers = [(rnd.randint(0, 319), rnd.randint(18, 48), rnd.randint(5, 11)) for _ in range(16)]
    top = [ridge(x) for x in range(320)]
    for tx, th, tw in towers:
        for x in range(tx - tw // 2, tx + tw // 2 + 1):
            xx = x % 320
            spike = th * (1 - abs(x - tx) / (tw / 2 + 1) * 0.25)
            top[xx] = min(top[xx], ridge(tx) - int(spike))
    for x in range(320):
        for y in range(top[x], 256):
            P[x, y] = 4 if y - top[x] > 1 else g.dmix(15, 4, 0.55, x, y)
    for i in range(70):
        x = rnd.randint(0, 319)
        y = rnd.randint(top[x] + 4, 236)
        if P[x, y] == 4 and P[(x + 1) % 320, y] == 4: P[x, y] = 13 if rnd.random() < 0.6 else 7
    # sky glow above the city
    for x in range(320):
        for y in range(max(9, top[x] - 26), top[x]):
            if P[x, y] == 0 and (g.bayer(x, y) + 0.5) / 64 < 0.35 * (1 - (top[x] - y) / 26): P[x, y] = 4

    # ---------------- sprites
    B = Bank()
    shipc = [pal[9], pal[8], pal[7]]                       # BOBs take the nearest backdrop colours
    def ship_img(flame):
        im2, d = new(32, 16)
        d.polygon([(4, 7), (14, 3), (24, 5), (31, 8), (24, 10), (14, 12), (4, 9)], fill=1)   # hull, nose to the right
        d.polygon([(8, 7), (12, 0), (17, 0), (15, 6)], fill=1)                               # upper wing
        d.polygon([(8, 9), (12, 15), (17, 15), (15, 10)], fill=1)                            # lower wing
        rim(im2, 0, -1)
        d.ellipse([18, 6, 24, 9], fill=3)                                                    # canopy
        put(im2, 19, 6, 2); put(im2, 20, 9, 2)
        d.line([(12, 1), (16, 1)], fill=3); d.line([(12, 14), (16, 14)], fill=2)
        for k in range(flame):                                                               # engine flame
            put(im2, 3 - k, 7, 3); put(im2, 3 - k, 8, 3 if k < flame - 1 else 1)
        put(im2, 0, 8, 0)
        return im2
    B.add("Ship", ship_img(3), shipc); B.add("Ship flame", ship_img(4), shipc); B.add("Ship flame 2", ship_img(2), shipc)
    lasc = [pal[7], pal[9], pal[1]]
    def laser_img(n):
        im2, d = new(16, 16)
        d.line([(1 + n, 7), (15, 7)], fill=1); d.line([(1 + n, 8), (15, 8)], fill=1)
        d.line([(4 + n, 7), (14, 7)], fill=3); d.line([(4 + n, 8), (14, 8)], fill=3)
        put(im2, 0 + n, 7, 2); put(im2, 0 + n, 8, 2)
        return im2
    B.add("Laser", laser_img(0), lasc); B.add("Laser glint", laser_img(2), lasc)
    optc = [0xff9020, 0x903000, 0xfff080]
    for k, pz in enumerate((0, 1, 2, 1)): B.add("Option %d" % (k + 1), orb(5.6, pz), optc)
    plc = [0xff40a0, 0x701050, 0xffe0ff]
    B.add("Plasma", orb(3.2, 0), plc); B.add("Plasma flicker", orb(3.2, 1.2), plc)
    capc = [0xe02828, 0x600808, 0xffffff]; capm = [0x2878ff, 0x081860, 0xffffff]
    for L, cc in (("P", capc), ("S", capc), ("M", capm)):
        for k in range(3): B.add("Capsule %s %d" % (L, k + 1), capsule(L, k * 4), cc)
    dartc = [pal[12], pal[11], pal[13]]
    def dart_img(f):
        im2, d = new(32, 16)
        d.polygon([(0, 8), (10, 4), (22, 2), (30, 5), (30, 11), (22, 14), (10, 12)], fill=1)   # pointing left
        d.polygon([(14, 4), (24, 0), (28, 0), (22, 5)], fill=1)
        d.polygon([(14, 12), (24, 15), (28, 15), (22, 11)], fill=1)
        rim(im2, 0, -1)
        d.ellipse([7, 6, 12, 9], fill=3)
        for k in range(1 + f): put(im2, 31 - k + 1, 7, 3); put(im2, 31 - k + 1, 8, 3)
        put(im2, 31, 6, 2); put(im2, 31, 9, 2)
        return im2
    B.add("Dart", dart_img(0), dartc); B.add("Dart burn", dart_img(1), dartc)
    spinc = [pal[6], pal[5], pal[1]]
    def spin_img(f):
        im2, d = new(32, 16)
        d.ellipse([4, 1, 27, 14], fill=1)
        rim(im2, -1, -1)
        for k in range(6):                                  # vanes that turn
            a = TAU * k / 6 + f * TAU / 24
            x2 = 15.5 + math.cos(a) * 10; y2 = 7.5 + math.sin(a) * 5.5
            d.line([(15.5, 7.5), (x2, y2)], fill=2)
        d.ellipse([12, 5, 19, 10], fill=3)
        put(im2, 15, 7, 2); put(im2, 16, 8, 2)
        return im2
    for k in range(4): B.add("Spinner %d" % (k + 1), spin_img(k), spinc)
    heavyc = [pal[9], pal[8], pal[3]]
    def heavy_img(f):
        im2, d = new(32, 32)
        d.rounded_rectangle([6, 4, 31, 27], radius=7, fill=1)
        d.rectangle([0, 13, 8, 18], fill=1)                # the cannon
        rim(im2, -1, -1)
        for yy in (10, 21): d.line([(10, yy), (28, yy)], fill=2)
        for xx in (14, 22): d.line([(xx, 6), (xx, 25)], fill=2)
        d.ellipse([16, 12, 23, 19], fill=3 if f == 0 else 2)
        put(im2, 19, 15, 1 if f == 0 else 3)
        for k in range(3): put(im2, 26, 7 + k * 8, 3 if (k + f) % 2 else 2)
        return im2
    B.add("Heavy", heavy_img(0), heavyc); B.add("Heavy glow", heavy_img(1), heavyc)
    seekc = [pal[13], pal[3], pal[12]]
    def seek_img(f):
        im2, d = new(16, 16)
        d.ellipse([3, 3, 12, 12], fill=1)
        rim(im2, -1, -1)
        for k in range(8):
            a = TAU * k / 8 + f * 0.4
            put(im2, int(round(7.5 + math.cos(a) * 7)), int(round(7.5 + math.sin(a) * 7)), 2)
        d.ellipse([6, 6, 9, 9], fill=3 if f == 0 else 2)
        return im2
    B.add("Seeker", seek_img(0), seekc); B.add("Seeker blink", seek_img(1), seekc)
    bossc = [pal[9], pal[8], pal[12]]
    def boss_img(f):
        im2, d = new(64, 48)
        d.polygon([(0, 24), (14, 10), (40, 4), (63, 8), (63, 40), (40, 44), (14, 38)], fill=1)
        d.polygon([(30, 4), (44, 0), (56, 0), (50, 6)], fill=1)
        d.polygon([(30, 44), (44, 47), (56, 47), (50, 42)], fill=1)
        rim(im2, -1, -1)
        for xx in (24, 36, 48): d.line([(xx, 8), (xx, 40)], fill=2)
        for yy in (16, 32): d.line([(16, yy), (60, yy)], fill=2)
        d.rectangle([2, 22, 10, 26], fill=2)               # the big gun
        for k in range(3): d.rectangle([18 + k * 12, 6, 21 + k * 12, 8], fill=3)
        r = 7 + f
        d.ellipse([30 - r, 24 - r, 30 + r, 24 + r], fill=2)  # the core: shoot it
        d.ellipse([30 - r + 2, 24 - r + 2, 30 + r - 2, 24 + r - 2], fill=3)
        put(im2, 28, 22, 1); put(im2, 29, 22, 1)
        return im2
    B.add("Boss", boss_img(0), bossc); B.add("Boss pulse", boss_img(1), bossc)
    warpc = [pal[7], pal[5], pal[1]]
    for k in range(3): B.add("Warp %d" % (k + 1), warp(32, k), warpc)
    boomc = [pal[3], pal[12], pal[13]]
    for k in range(6): B.add("Boom %d" % (k + 1), boom(32, 32, k, 6, 3), boomc)
    for k in range(8): B.add("Big boom %d" % (k + 1), boom(64, 48, k, 8, 11), boomc)

    # ---------------- actors (the backdrop flies left: flyers come in from the right, edge 1)
    actors = []
    A = {}
    def add(a):
        A[a['name']] = len(actors); actors.append(a)
    add(act("Ship", B["Ship"], 0, 2, 32, 120, bob=True, anims={0: ([B["Ship"], B["Ship flame"], B["Ship flame 2"]], 3, 0)}))
    for k in range(8):
        add(act("Laser %d" % (k + 1), B["Laser"], 9, 8, 0, 0, vis=False, bob=True, aim=4,
                anims={0: ([B["Laser"], B["Laser glint"]], 3, 0)}))
    for k in range(2):
        add(act("Option %d" % (k + 1), B["Option 1"], 11, 1, 32, 120, vis=False,
                anims={0: ([B["Option 1"], B["Option 2"], B["Option 3"], B["Option 4"]], 4, 0)}))
    for k in range(2):
        add(act("Plasma %d" % (k + 1), B["Plasma"], 9, 3, 0, 0, vis=False, aim=5, anims={0: ([B["Plasma"], B["Plasma flicker"]], 3, 0)}))
    for L in "PSM":
        add(act("Capsule " + L, B["Capsule %s 1" % L], 10, 1, 200, 120, vis=False, enter=1, comeback=False,
                anims={0: ([B["Capsule %s %d" % (L, k + 1)] for k in range(3)], 6, 0)}))
    for k in range(4):                                       # a wave of darts, weaving, one behind the other
        add(act("Dart %d" % (k + 1), B["Dart"], 10, 2, 120 + k * 36, 64, bob=True, pattern=1, enter=1, fast=1,
                anims={0: ([B["Dart"], B["Dart burn"]], 4, 0)}))
    for k, (x, y) in enumerate(((150, 160), (220, 200), (290, 130))):
        add(act("Spinner %d" % (k + 1), B["Spinner 1"], 10, 2, x, y, bob=True, pattern=2, enter=1, left=(k % 2 == 1), fast=1,
                anims={0: ([B["Spinner %d" % (j + 1)] for j in range(4)], 4, 0)}))
    add(act("Heavy", B["Heavy"], 10, 1, 288, 104, bob=True, enter=1, hits=6, frm=2,
            anims={0: ([B["Heavy"], B["Heavy glow"]], 12, 0)}))
    add(act("Seeker", B["Seeker"], 10, 2, 300, 40, bob=True, pattern=3, enter=1, hits=2, frm=3,
            anims={0: ([B["Seeker"], B["Seeker blink"]], 6, 0)}))
    add(act("Boss", B["Boss"], 10, 1, 236, 104, vis=False, bob=True, pattern=5, enter=1, hits=40,
            anims={0: ([B["Boss"], B["Boss pulse"]], 10, 2)}))
    add(act("Warp gate", B["Warp 1"], 10, 1, 230, 112, vis=False, bob=True, pattern=5, enter=1,
            anims={0: ([B["Warp %d" % (k + 1)] for k in range(3)], 4, 0)}))
    for k in range(3):
        add(act("Boom %d" % (k + 1), B["Boom 1"], 12, 1, 0, 0, vis=False, bob=True,
                anims={0: ([B["Boom %d" % (j + 1)] for j in range(6)], 4, 1)}))
    add(act("Big boom", B["Big boom 1"], 12, 1, 0, 0, vis=False, bob=True,
            anims={0: ([B["Big boom %d" % (j + 1)] for j in range(8)], 5, 1)}))

    R = g.R
    enemies = [("Dart 1", 100, True), ("Dart 2", 100, True), ("Dart 3", 100, True), ("Dart 4", 100, True),
               ("Spinner 1", 150, False), ("Spinner 2", 150, False), ("Spinner 3", 150, False),
               ("Heavy", 400, True), ("Seeker", 250, False)]
    rules = common_rules(R, A, enemies, {"Dart 4": "Capsule P", "Spinner 2": "Capsule S", "Heavy": "Capsule M", "Seeker": "Capsule P"},
                         [("Heavy", 2), ("Dart 2", 3), ("Spinner 3", 4), ("Boss", 1)])
    rules += boss_arrives(R, A, ["Dart 1", "Dart 2", "Dart 3", "Dart 4", "Spinner 1", "Spinner 3"])
    rules += flow(R, A)

    sky = [0x02000a, 0x120830, 0x3a1048, 150]
    p = g.make_project("Nebula Strike", pal, im, [], actors, rules, sky, msg_col=13, lives=3, sfx=g.sfx_list(SFX),
                       over="SHIP LOST - GAME OVER", win="THE NEBULA IS FREE! - PRESS FIRE")
    p['sprites'] = B.s + [blank(i) for i in range(len(B.s), 128)]
    p.update(scroll_dir=2, scroll_speed=4)
    lv = [periodic_hills(226, [(2, 6, 0.4), (5, 3, 1.1)]), periodic_hills(220, [(1, 7, 2.0), (3, 6, 0.3), (7, 2, 1.7)]),
          periodic_hills(216, [(2, 9, 1.4), (5, 5, 0.2), (11, 3, 2.5)])]
    p.update(levels_on=True, levels=[dict(seed=2000 + i * 37, hilly=60 + i * 20, base=220, heights=h) for i, h in enumerate(lv)],
             terrain_cols=[15, 14, 4, 5])
    finish(p, songs(), "NEBULA STRIKE", "PRESS FIRE TO LAUNCH", "Metal", 1)
    p['_gk'] = group_key(actors)
    return p

# ================================================================== STARFIRE (up)
def starfire():
    aga_cap()
    # 0 sky, 1 white, 2 HUD, 3 orange, 4-7 hull metal, 8-10 greens, 11-12 reds, 13 yellow, 14 purple, 15 pink
    pal = [0x000000, 0xffffff, 0x101830, 0xff8020, 0x1c2434, 0x405068, 0x8094b4, 0x58e0ff,
           0x0c4428, 0x28a050, 0xa8f060, 0x801818, 0xf04030, 0xffe050, 0x6030a0, 0xff70c0]
    im = g.canvas(); P = im.load()
    rnd = random.Random(31)
    T = TAU / 256
    # nebula wisps in the open space between the station walls
    for y in range(256):
        for x in range(40, 280):
            t = 0.55 * math.exp(-((x - 140 - 50 * math.sin(y * T * 1 + 0.6)) / 46) ** 2) * (0.6 + 0.4 * math.sin(y * T * 2 + 1.3)) \
              + 0.25 * math.sin(x / 17 + y * T * 3) * math.sin(y * T * 5 - x / 29) - 0.18
            if t > 0: P[x, y] = g.ramp([0, 14, 15], min(1.0, t * 1.6), x, y) if t > 0.25 else g.dmix(0, 14, t * 2.5, x, y)
    for i in range(240):
        x = rnd.randint(40, 279); y = rnd.randint(0, 255)
        if P[x, y] != 0: continue
        c = rnd.choice([4, 5, 5, 6, 6, 7, 1])
        P[x, y] = c
    # the station walls either side: plates, ribs and lights, joining up at the top and bottom
    def wall_l(y):
        k = (y // 64) % 4
        return 34 + (0, 10, 4, 14)[k] + int(round(3 * math.sin(y * T * 4)))
    def wall_r(y):
        k = ((y + 32) // 64) % 4
        return 286 - (0, 12, 6, 10)[k] - int(round(3 * math.sin(y * T * 4 + 1)))
    for y in range(256):
        L = wall_l(y); Rr = wall_r(y)
        for x in range(0, L + 1):
            depth = (L - x) / max(1, L)
            v = g.ramp([6, 5, 4], depth * 1.4, x, y)
            if x == L: v = 7 if (y // 8) % 2 else 6               # lit rim facing the middle
            elif x == L - 1: v = 6
            if y % 32 in (0, 1) and x < L - 2: v = 4 if y % 32 == 0 else 6   # plate seams
            if x % 12 == 6 and x < L - 3: v = 4
            P[x, y] = v
        for x in range(Rr, 320):
            depth = (x - Rr) / max(1, 319 - Rr)
            v = g.ramp([5, 4], depth * 1.2, x, y)
            if x == Rr: v = 6
            if y % 32 in (16, 17) and x > Rr + 2: v = 4 if y % 32 == 16 else 5
            if x % 12 == 2 and x > Rr + 3: v = 4
            P[x, y] = v
    for y in range(4, 256, 16):                              # rivets and running lights
        for x in (8, 20):
            if P[x, y] in (4, 5, 6): P[x, y] = 7 if (y // 16) % 3 == 0 else 6
        for x in (300, 312):
            if P[x, y] in (4, 5): P[x, y] = 12 if (y // 16) % 4 == 1 else 6
    for y0 in (40, 168):                                     # girders reaching out from the left wall
        for y in range(y0, y0 + 6):
            for x in range(wall_l(y), 120 if y0 == 40 else 96):
                v = 5 if y in (y0, y0 + 5) else (4 if (x // 4 + y) % 2 else 5)
                if y == y0: v = 6
                if (x - wall_l(y)) % 16 in (0, 1): v = 6
                P[x, y] = v
    for y0 in (104, 232):                                    # and from the right
        for y in range(y0, y0 + 6):
            for x in range(200 if y0 == 104 else 224, wall_r(y) + 1):
                v = 5 if y in (y0, y0 + 5) else (4 if (x // 4 + y) % 2 else 5)
                if y == y0: v = 6
                P[x, y] = v

    # ---------------- sprites
    B = Bank()
    shipc = [0xe8ecf8, 0x2a58c0, 0x60e8ff]                    # hardware sprite: white hull, blue, cyan glow
    def ship_img(flame, lean=0):
        im2, d = new(16, 24)
        d.polygon([(7, 1), (8, 1), (11, 9), (11, 16), (8, 19), (7, 19), (4, 16), (4, 9)], fill=1)
        d.polygon([(4, 10), (0, 17), (0, 19), (5, 17)], fill=2)
        d.polygon([(11, 10), (15, 17), (15, 19), (10, 17)], fill=2)
        d.line([(7, 5), (7, 8)], fill=3); d.line([(8, 5), (8, 8)], fill=3)
        put(im2, 0, 16, 3); put(im2, 15, 16, 3)
        d.line([(4, 12), (4, 16)], fill=2); d.line([(11, 12), (11, 16)], fill=2)
        for k in range(flame):
            put(im2, 7, 20 + k, 3); put(im2, 8, 20 + k, 3 if k < flame - 1 else 2)
        return im2
    B.add("Fighter", ship_img(2), shipc); B.add("Fighter flame", ship_img(3), shipc); B.add("Fighter flame 2", ship_img(1), shipc)
    capm = [0xe8ecf8, 0x2a58c0, 0x60e8ff]                     # the M capsule shares the fighter's colours (one sprite pair)
    def capsule_m(shine):
        im2, d = new(16, 24)
        d.rounded_rectangle([1, 7, 14, 16], radius=4, fill=2)
        for k in range(3, 13):
            if (k - shine) % 10 in (0, 1): put(im2, k, 8, 3)
        for r, row in enumerate(LETTER['M']):
            for c, ch in enumerate(row):
                if ch == '1': put(im2, 6 + c, 9 + r, 1)
        return im2
    for k in range(3): B.add("Capsule M %d" % (k + 1), capsule_m(k * 4), capm)
    optc = [0xff9020, 0x903000, 0xfff080]
    for k, pz in enumerate((0, 1, 2, 1)): B.add("Option %d" % (k + 1), orb(5.6, pz), optc)
    plc = [0xff40a0, 0x701050, 0xffe0ff]
    B.add("Plasma", orb(3.2, 0), plc); B.add("Plasma flicker", orb(3.2, 1.2), plc)
    capc = [0xe02828, 0x600808, 0xffffff]
    for L in "PS":
        for k in range(3): B.add("Capsule %s %d" % (L, k + 1), capsule(L, k * 4), capc)
    lasc = [pal[7], pal[14], pal[1]]
    def laser_img(n):
        im2, d = new(16, 16)
        d.line([(7, n), (7, 15)], fill=1); d.line([(8, n), (8, 15)], fill=1)
        d.line([(7, 1 + n), (7, 12)], fill=3); d.line([(8, 1 + n), (8, 12)], fill=3)
        put(im2, 7, 15, 2); put(im2, 8, 15, 2)
        return im2
    B.add("Laser", laser_img(0), lasc); B.add("Laser glint", laser_img(2), lasc)
    sauc = [pal[9], pal[8], pal[10]]
    def saucer_img(f):
        im2, d = new(32, 24)
        d.ellipse([1, 9, 30, 19], fill=1)
        rim(im2, 0, -1)
        d.ellipse([10, 3, 21, 13], fill=3)                   # the glass dome
        d.arc([10, 3, 21, 13], 200, 340, fill=1)
        for k in range(6):
            put(im2, 4 + ((k * 5 + f * 2) % 24), 15, 3)
        d.line([(6, 18), (25, 18)], fill=2)
        return im2
    for k in range(3): B.add("Saucer %d" % (k + 1), saucer_img(k), sauc)
    dartc = [pal[12], pal[11], pal[13]]
    def dart_img(f):
        im2, d = new(16, 24)
        d.polygon([(7, 23), (8, 23), (12, 12), (15, 4), (11, 6), (8, 2), (7, 2), (4, 6), (0, 4), (3, 12)], fill=1)   # nose down
        rim(im2, -1, 0)
        d.line([(7, 9), (7, 15)], fill=3); d.line([(8, 9), (8, 15)], fill=2)
        for k in range(1 + f): put(im2, 7, 1 - k + 1, 3); put(im2, 8, 1 - k + 1, 3)
        return im2
    B.add("Dart", dart_img(0), dartc); B.add("Dart burn", dart_img(1), dartc)
    turc = [pal[5], pal[4], pal[12]]
    def turret_img(f):
        im2, d = new(16, 16)
        d.ellipse([1, 1, 14, 14], fill=1)
        rim(im2, -1, -1)
        d.ellipse([5, 5, 10, 10], fill=2)
        d.ellipse([6, 6, 9, 9], fill=3 if f == 0 else 2)
        return im2
    B.add("Turret", turret_img(0), turc); B.add("Turret blink", turret_img(1), turc)
    cruc = [pal[14], pal[4], pal[15]]
    def cruiser_img(f):
        im2, d = new(48, 32)
        d.polygon([(24, 31), (34, 22), (46, 18), (47, 8), (36, 4), (30, 0), (18, 0), (12, 4), (1, 8), (0, 18), (14, 22)], fill=1)
        rim(im2, -1, -1)
        d.line([(24, 4), (24, 26)], fill=2)
        for xx in (10, 38): d.ellipse([xx - 3, 8, xx + 3, 14], fill=3 if f == 0 else 2)
        d.rectangle([20, 2, 28, 6], fill=3 if f else 2)
        return im2
    B.add("Cruiser", cruiser_img(0), cruc); B.add("Cruiser glow", cruiser_img(1), cruc)
    bossc = [pal[6], pal[4], pal[12]]
    def boss_img(f):
        im2, d = new(64, 48)
        d.polygon([(0, 14), (10, 6), (22, 4), (32, 0), (42, 4), (54, 6), (63, 14), (63, 26), (52, 34), (40, 38), (32, 47), (24, 38), (12, 34), (0, 26)], fill=1)
        rim(im2, -1, -1)
        for xx in (16, 32, 48): d.line([(xx, 8), (xx, 32)], fill=2)
        d.line([(6, 20), (58, 20)], fill=2)
        for xx in (6, 56): d.rectangle([xx - 2, 26, xx + 2, 36], fill=2)   # side guns
        r = 7 + f
        d.ellipse([32 - r, 22 - r, 32 + r, 22 + r], fill=2)
        d.ellipse([32 - r + 2, 22 - r + 2, 32 + r - 2, 22 + r - 2], fill=3)
        put(im2, 30, 19, 1); put(im2, 31, 19, 1)
        return im2
    B.add("Boss", boss_img(0), bossc); B.add("Boss pulse", boss_img(1), bossc)
    warpc = [pal[7], pal[14], pal[1]]
    for k in range(3): B.add("Warp %d" % (k + 1), warp(32, k), warpc)
    boomc = [pal[3], pal[12], pal[13]]
    for k in range(6): B.add("Boom %d" % (k + 1), boom(32, 32, k, 6, 5), boomc)
    for k in range(8): B.add("Big boom %d" % (k + 1), boom(64, 48, k, 8, 17), boomc)

    # ---------------- actors (the backdrop moves down: flyers come in from the top, edge 0)
    actors = []
    A = {}
    def add(a):
        A[a['name']] = len(actors); actors.append(a)
    add(act("Ship", B["Fighter"], 0, 2, 152, 200, anims={0: ([B["Fighter"], B["Fighter flame"], B["Fighter flame 2"]], 3, 0)}))
    add(act("Capsule M", B["Capsule M 1"], 10, 1, 150, 40, vis=False, comeback=False,
            anims={0: ([B["Capsule M %d" % (k + 1)] for k in range(3)], 6, 0)}))
    for k in range(2):
        add(act("Option %d" % (k + 1), B["Option 1"], 11, 1, 152, 200, vis=False,
                anims={0: ([B["Option 1"], B["Option 2"], B["Option 3"], B["Option 4"]], 4, 0)}))
    for k in range(2):
        add(act("Plasma %d" % (k + 1), B["Plasma"], 9, 3, 0, 0, vis=False, aim=5, anims={0: ([B["Plasma"], B["Plasma flicker"]], 3, 0)}))
    for L in "PS":
        add(act("Capsule " + L, B["Capsule %s 1" % L], 10, 1, 150, 40, vis=False, comeback=False,
                anims={0: ([B["Capsule %s %d" % (L, k + 1)] for k in range(3)], 6, 0)}))
    for k in range(8):
        add(act("Laser %d" % (k + 1), B["Laser"], 9, 8, 0, 0, vis=False, bob=True, aim=1,
                anims={0: ([B["Laser"], B["Laser glint"]], 3, 0)}))
    for k in range(4):                                       # saucers weave down in a column
        add(act("Saucer %d" % (k + 1), B["Saucer 1"], 10, 2, 140, 10 + k * 34, bob=True, pattern=1, fast=1,
                anims={0: ([B["Saucer %d" % (j + 1)] for j in range(3)], 5, 0)}))
    for k, (x, y) in enumerate(((70, 60), (200, 120), (240, 20))):
        add(act("Dart %d" % (k + 1), B["Dart"], 10, 3, x, y, bob=True, pattern=2, left=(k % 2 == 1), fast=1,
                anims={0: ([B["Dart"], B["Dart burn"]], 4, 0)}))
    add(act("Turret 1", B["Turret"], 10, 1, 22, 60, bob=True, pattern=4, hits=2, anims={0: ([B["Turret"], B["Turret blink"]], 12, 0)}))
    add(act("Turret 2", B["Turret"], 10, 1, 268, 180, bob=True, pattern=4, hits=2, anims={0: ([B["Turret"], B["Turret blink"]], 12, 0)}))
    add(act("Cruiser", B["Cruiser"], 10, 1, 136, 30, bob=True, hits=8, frm=2, anims={0: ([B["Cruiser"], B["Cruiser glow"]], 10, 0)}))
    add(act("Boss", B["Boss"], 10, 1, 128, 24, vis=False, bob=True, pattern=5, hits=50,
            anims={0: ([B["Boss"], B["Boss pulse"]], 10, 2)}))
    add(act("Warp gate", B["Warp 1"], 10, 1, 144, 60, vis=False, bob=True, pattern=5,
            anims={0: ([B["Warp %d" % (k + 1)] for k in range(3)], 4, 0)}))
    for k in range(3):
        add(act("Boom %d" % (k + 1), B["Boom 1"], 12, 1, 0, 0, vis=False, bob=True,
                anims={0: ([B["Boom %d" % (j + 1)] for j in range(6)], 4, 1)}))
    add(act("Big boom", B["Big boom 1"], 12, 1, 0, 0, vis=False, bob=True,
            anims={0: ([B["Big boom %d" % (j + 1)] for j in range(8)], 5, 1)}))

    R = g.R
    enemies = [("Saucer 1", 100, True), ("Saucer 2", 100, True), ("Saucer 3", 100, True), ("Saucer 4", 100, True),
               ("Dart 1", 150, False), ("Dart 2", 150, False), ("Dart 3", 150, False),
               ("Turret 1", 200, False), ("Turret 2", 200, False), ("Cruiser", 500, True)]
    rules = common_rules(R, A, enemies, {"Saucer 4": "Capsule P", "Dart 2": "Capsule S", "Cruiser": "Capsule M", "Turret 2": "Capsule P"},
                         [("Turret 1", 2), ("Turret 2", 3), ("Cruiser", 2), ("Boss", 1)])
    rules += boss_arrives(R, A, ["Saucer 1", "Saucer 2", "Saucer 3", "Saucer 4", "Dart 1", "Dart 3"])
    rules += flow(R, A)

    sky = [0x000008, 0x0a0626, 0x1c0838, 128]
    p = g.make_project("Starfire", pal, im, [], actors, rules, sky, msg_col=13, lives=3, sfx=g.sfx_list(SFX),
                       over="FIGHTER LOST - GAME OVER", win="THE STATION IS SAFE! - PRESS FIRE")
    p['sprites'] = B.s + [blank(i) for i in range(len(B.s), 128)]
    p.update(scroll_dir=1, scroll_speed=4)
    p.update(levels_on=True, levels=[dict(seed=3000 + i * 37, hilly=0, base=230, heights=[240] * 320) for i in range(3)],
             hills_on=False, terrain_cols=[4, 5, 4, 6])
    finish(p, songs(), "STARFIRE", "PRESS FIRE TO LAUNCH", "Neon", 4)
    p['_gk'] = group_key(actors)
    return p
