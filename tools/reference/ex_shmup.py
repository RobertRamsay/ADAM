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
    # (x, y) is outside the picture or empty
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

# the picture turned round left to right
def flip_h(im): return im.transpose(Image.FLIP_LEFT_RIGHT)

# an 'L' picture -> an ADAM sprite dict of its size
def spr(name, im, cols):
    w, h = im.size
    return dict(name=name, w=w, h=h, px=list(im.getdata()), cols=list(cols))

# a fixed coin toss for pixel (x, y): about one in three is True (lit windows)
def hash_bit(x, y): return ((x * 73856093) ^ (y * 19349663)) % 7 < 3

# sets pixel (x, y), ignored outside the picture
def put(im, x, y, v):
    if 0 <= x < im.size[0] and 0 <= y < im.size[1]: im.putpixel((x, y), v)

# ------------------------------------------------------------------ shaded pictures
# Bigger sprites are modelled as a relief (a height for every pixel: bevelled slabs and
# domes) and lit from the upper left, which gives five tones from a sprite's three
# colours: dark, dark / main dithered, main, main / light dithered, light.
def edge_dist(mask):
    """how far each set pixel of 'L' picture mask is from its edge (1 = on the edge)"""
    w, h = mask.size
    m = mask.load()
    d = [[0.0] * w for _ in range(h)]
    # the distance at (xx, yy), 0 outside
    def at(xx, yy):
        if 0 <= xx < w and 0 <= yy < h: return d[yy][xx]
        return 0.0
    for yy in range(h):
        for xx in range(w):
            if m[xx, yy]:
                d[yy][xx] = min(at(xx - 1, yy) + 1, at(xx, yy - 1) + 1, at(xx - 1, yy - 1) + 1.4, at(xx + 1, yy - 1) + 1.4)
    for yy in range(h - 1, -1, -1):
        for xx in range(w - 1, -1, -1):
            if m[xx, yy]:
                d[yy][xx] = min(d[yy][xx], at(xx + 1, yy) + 1, at(xx, yy + 1) + 1, at(xx + 1, yy + 1) + 1.4, at(xx - 1, yy + 1) + 1.4)
    return d

class Relief:
    """a height map built from slabs (crisp bevelled plates) and domes (soft, dithered shading),
    rendered to sprite colours 1..3"""
    # an empty w x h relief
    def __init__(self, w, h):
        self.w = w; self.h = h
        self.z = [[None] * w for _ in range(h)]
        self.soft = [[False] * w for _ in range(h)]
    # raises pixel (x, y) to v
    def _up(self, x, y, v, soft):
        if self.z[y][x] is None or v > self.z[y][x]:
            self.z[y][x] = v; self.soft[y][x] = soft
    def slab(self, shape, top=1.5, slope=2.0, base=0.0):
        """shape(d) draws the outline with fill=255 on an ImageDraw; the slab rises from base by slope
        a pixel from its edge, up to base + top (the default: a plate with a one pixel bevel)"""
        mask = Image.new('L', (self.w, self.h), 0)
        shape(ImageDraw.Draw(mask))
        d = edge_dist(mask)
        m = mask.load()
        for y in range(self.h):
            for x in range(self.w):
                if m[x, y]: self._up(x, y, base + min(top, d[y][x] * slope), slope < 1.5)
        return self
    # a slab from a polygon's corners
    def poly(self, pts, top=1.5, slope=2.0, base=0.0):
        return self.slab(lambda d: d.polygon(pts, fill=255), top, slope, base)
    # a slab from a rectangle (x0, y0, x1, y1)
    def box(self, x0, y0, x1, y1, top=1.5, slope=2.0, base=0.0):
        return self.slab(lambda d: d.rectangle([x0, y0, x1, y1], fill=255), top, slope, base)
    # half an ellipsoid, centre (cx, cy), radii rx / ry, top high
    def dome(self, cx, cy, rx, ry, top, base=0.0):
        for y in range(self.h):
            for x in range(self.w):
                dd = ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2
                if dd <= 1: self._up(x, y, base + top * math.sqrt(1 - dd), True)
        return self
    def render(self, out=-1.0):
        """-> 'L' picture: 0 clear, 2 dark, 1 main, 3 light"""
        im, _ = new(self.w, self.h)
        # the height at (x, y), out outside the shape
        def zz(x, y):
            if 0 <= x < self.w and 0 <= y < self.h and self.z[y][x] is not None: return self.z[y][x]
            return out
        for y in range(self.h):
            for x in range(self.w):
                if self.z[y][x] is None: continue
                gx = (zz(x + 1, y) - zz(x - 1, y)) / 2
                gy = (zz(x, y + 1) - zz(x, y - 1)) / 2
                lit = (gx * 0.5 + gy * 0.6 + 0.62) / math.sqrt(gx * gx + gy * gy + 1)
                ch = (x + y) & 1
                if not self.soft[y][x]:                       # a plate: a lit edge, a dark edge, flat between
                    if lit < 0.36: v = 2
                    elif lit < 0.72: v = 1
                    else: v = 3
                elif lit < 0.30: v = 2
                elif lit < 0.46: v = 2 if ch else 1
                elif lit < 0.76: v = 1
                elif lit < 0.88: v = 3 if ch else 1
                else: v = 3
                im.putpixel((x, y), v)
        return im

# the picture with every pixel of colour a made colour b
def recolour(im, a, b):
    return im.point(lambda v: b if v == a else v)

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
    """explosion frame f of n: a white-hot flash that swells into balls of fire flying apart, which
    cool and shrink to embers. 3 = brightest (yellow), 1 = fire, 2 = dark red embers"""
    im, _ = new(w, h)
    rnd = random.Random(seed)
    cx, cy = (w - 1) / 2, (h - 1) / 2
    R = min(w, h) / 2 - 1
    wide = w / h if w > h else 1.0
    t = f / max(1, n - 1)
    # the puffs of fire: (direction, how far out it flies, size); the first is the middle
    puffs = [(0.0, 0.0, 1.0)] + [(rnd.uniform(0, TAU), rnd.uniform(0.5, 0.8), rnd.uniform(0.42, 0.6)) for _ in range(6)]
    sparks = [(rnd.uniform(0, TAU), rnd.uniform(0.6, 1.0)) for _ in range(6)]
    spread = 1 - (1 - t) ** 2                              # they fly apart fast, then slow down
    size = min(1.0, 0.45 + t * 2.2) * (1.0 - 0.55 * max(0.0, t - 0.45) / 0.55)
    temp = 1.15 - 0.95 * t
    for y in range(h):
        for x in range(w):
            heat = 0.0
            for a, dist, sz in puffs:
                px = cx + math.cos(a) * dist * R * spread * 0.5 * wide
                py = cy + math.sin(a) * dist * R * spread * 0.5
                rr = R * sz * size
                v = 1 - math.hypot(x - px, y - py) / max(0.5, rr)
                if dist == 0: v *= 1 - 0.75 * t            # the middle burns out first
                if v > heat: heat = v
            if heat <= 0: continue
            nz = ((x * 73856093) ^ (y * 19349663) ^ ((f * 7 + seed) * 83492791)) % 997 / 997
            v = heat * temp + (nz - 0.5) * 0.16
            if v > 0.62: put(im, x, y, 3)
            elif v > 0.34: put(im, x, y, 1)
            elif v > 0.10: put(im, x, y, 2)
    for a, far in sparks:                                  # sparks flying out
        dist = (R - 1) * (0.25 + 0.75 * spread) * far
        x = int(round(cx + math.cos(a) * dist * wide)); y = int(round(cy + math.sin(a) * dist))
        if t < 0.85: put(im, x, y, 3 if t < 0.5 else 1)
        if 0.2 < t < 0.95: put(im, x - int(round(math.cos(a))), y - int(round(math.sin(a))), 2)
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
    # an empty bank
    def __init__(self):
        self.s = []
        self.idx = {}
    # adds picture im as sprite name -> its slot
    def add(self, name, im, cols):
        self.idx[name] = len(self.s)
        self.s.append(spr(name, im, cols))
        return self.idx[name]
    # bank['name'] -> its slot
    def __getitem__(self, name): return self.idx[name]

def anims_of(entries):
    """entries: {anim number: (frames, rate, mode)} -> the 21 animations of an actor"""
    out = [dict(frames=[], rate=8, mode=0) for _ in range(21)]
    for k, (fr, rate, mode) in entries.items():
        out[k] = dict(frames=list(fr), rate=rate, mode=mode)
    return out

# a shoot 'em up actor: gen_examples.actor plus the flyer settings (pattern, enter edge,
# comes back, hits to destroy, aim) and its 21 animations
def act(name, sprite, role, speed, x, y, vis=True, bob=False, pattern=0, enter=0, comeback=True, hits=1, aim=0,
        anims=None, frm=1, fast=0, left=False, up=False):
    a = g.actor(name, sprite, role, speed, x, y, vis=vis, left=left, up=up)
    a.update(bob=bob, pattern=pattern, enter=enter, comeback=comeback, hits=hits, aim=aim, carry=False,
             anim_flip=False, anim_dirs=False, from_level=frm, faster_every=fast)
    a['anims'] = anims_of(anims or {})
    return a

# this pass is making the A1200 version of an example
def p_aga(): return bool(g.AGA['on'])

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

# the two songs: 0 the stage music (levels start with it), 1 the boss tune (DO 18 at the boss)
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

# the Logic page groups of a shoot 'em up: a key(rule) function for auto_groups (p['_gk'])
def group_key(names):
    # the group name of rule r
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

# rules: secs seconds into the level (WHEN 13) the boss shows, its music starts, a warning
# sounds, the ship blinks and the actors in hide go
def boss_arrives(R, A, hide, secs=45):
    out = [R(when=13, n=secs, act=7, target=A['Boss']), R(when=13, n=secs, act=18, value=1), R(when=13, n=secs, act=2, value=WARNING),
           R(when=13, n=secs, act=3)]
    for nm in hide: out.append(R(when=13, n=secs, act=6, target=A[nm]))
    return out

# rules: no lives left = game over; music at game start; at each level start the ship goes home and 'ready' plays
def flow(R, A):
    return [R(when=4, act=9), R(when=5, act=18, value=0), R(when=7, act=16, target=A['Ship']), R(when=7, act=2, value=READY)]

# the common end of a shoot 'em up project: depth, songs, title, goal 1 'WARP', and the HUD (score, stage, ships)
def finish(p, songs_list, title1, title2, hud_style, hud_font):
    set_depth(p)                        # first, so the HUD's colours are ones the screen shows
    p['songs'] = songs_list
    p['level_song'] = [0] * 10
    p.update(title_on=True, title1=title1, title2=title2, lev_text="STAGE", goal_on=True, goal=1, goal_label="WARP")
    g.dress_ui(p, hud_style, hud_font, 1, [(1, "SCORE ", 1, 0, 0xffffff, 0x101020, 6), (5, "STAGE ", 16, 0, 0xffe040, 0x101020, 1),
                                           (2, "SHIPS ", 31, 0, 0x60e0ff, 0x101020, 1)])

def level_looks(p, looks):
    """named palettes for the later levels: looks = [(name, {colour number: $RRGGBB})], level 2 starts with
    the first, level 3 with the second... On the A1200 the in-between colours made from a changed
    colour are mixed again (g.AGA['order'], as make_project mixed them)"""
    pals = []
    n = 1 << p['depth']
    for name, new in looks:
        full = list(p['pal'])
        for i, c in new.items(): full[i] = c
        if p['machine'] == "A1200":
            for i, (a, b, k) in enumerate(g.AGA['order']):
                full[16 + i] = g.rgb_mix(full[a], full[b], k / g.AGA['steps'])
        pals.append(dict(name=name, cols=[full[i] if i < n and full[i] != p['pal'][i] else -1 for i in range(128)]))
    p['palettes'] = pals
    p['level_pal'] = [0] + list(range(1, len(pals) + 1)) + [0] * (9 - len(pals))

AGA_DEPTH = 6
NEBULA_DEPTH = 6                    # Nebula Strike's A1200 version: 64 colours
STARFIRE_DEPTH = 5                  # Starfire's: 32 are all its picture uses, and a bitplane less is a sixth less to blit

def aga_cap(depth=AGA_DEPTH):
    # the A1200 versions use 64 colours (16 + 48 in-between shades), or 32 with depth 5: the
    # blitter has BOBs to draw every frame, and every bitplane less leaves it more time for them
    g.AGA['max'] = 1 << depth
    g.AGA['depth'] = depth

# A1200: the bitplanes aga_cap asked for; then gives dmix its full 128 back for the next example
def set_depth(p):
    if p['machine'] == "A1200":
        p['depth'] = g.AGA.get('depth', AGA_DEPTH)
        assert max(p['pixels']) < (1 << p['depth'])
    g.AGA['max'] = 128

# ================================================================== NEBULA STRIKE (across)
def nebula_strike():
    aga_cap(NEBULA_DEPTH)
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
    # nearer blocks in front of the spires: steel walls lit from the left, rows of windows, a red lamp on the tall ones
    for i in range(11):
        bx = (i * 29 + rnd.randint(0, 9)) % 320; bw = rnd.randint(12, 24); bh = rnd.randint(18, 52)
        by = 232 - bh
        for x in range(bx, bx + bw):
            xx = x % 320
            for y in range(by, 256):
                c = 8
                if y == by: c = 9
                elif x - bx < 2: c = g.dmix(8, 9, 0.5, xx, y)
                elif x == bx + bw - 1: c = 2
                elif (x - bx) % 4 == 3 and (y - by) % 5 == 3 and hash_bit(xx, y): c = 13 if (xx + y) % 3 else 7
                P[xx, y] = c
        if bh > 40:
            P[(bx + bw // 2) % 320, by - 1] = 8; P[(bx + bw // 2) % 320, by - 2] = 8; P[(bx + bw // 2) % 320, by - 3] = 12
    # sky glow above the city
    for x in range(320):
        for y in range(max(9, top[x] - 26), top[x]):
            if P[x, y] == 0 and (g.bayer(x, y) + 0.5) / 64 < 0.35 * (1 - (top[x] - y) / 26): P[x, y] = 4

    # ---------------- sprites
    B = Bank()
    shipc = [pal[9], pal[8], pal[10]]                      # BOBs take the nearest backdrop colours: three steels
    # the ship facing right; flame = the exhaust frame
    def ship_img(flame):
        r = Relief(32, 16)
        r.poly([(7, 6), (11, 0), (17, 0), (16, 6)])                                          # tail fin
        r.poly([(7, 9), (12, 15), (19, 15), (17, 9)])                                        # wing
        r.poly([(4, 6), (14, 4), (24, 5), (31, 8), (24, 10), (14, 11), (4, 9)], 1.5, 2.0, 1.5)   # hull, nose to the right
        im2 = r.render()
        d = ImageDraw.Draw(im2)
        d.ellipse([18, 5, 24, 8], fill=2)                                                    # canopy
        put(im2, 20, 6, 3); put(im2, 21, 6, 3)
        d.line([(9, 8), (16, 8)], fill=2)                                                    # a seam along the hull
        for k in range(flame):                                                               # engine flame
            put(im2, 3 - k, 7, 3); put(im2, 3 - k, 8, 3 if k < flame - 1 else 1)
        put(im2, 0, 8, 0)
        return im2
    B.add("Ship", ship_img(3), shipc); B.add("Ship flame", ship_img(4), shipc); B.add("Ship flame 2", ship_img(2), shipc)
    lasc = [pal[7], pal[9], pal[1]]
    # a laser bolt; n = how far it has grown from the gun
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
    # a dart fighter facing left, frame f
    def dart_img(f):
        r = Relief(32, 16)
        r.poly([(14, 4), (24, 0), (29, 0), (23, 5)])                                         # fins
        r.poly([(14, 11), (24, 15), (29, 15), (23, 10)])
        r.poly([(0, 8), (10, 4), (22, 3), (30, 5), (30, 10), (22, 12), (10, 11), (0, 7)], 1.5, 2.0, 1.5)   # pointing left
        im2 = r.render()
        d = ImageDraw.Draw(im2)
        d.ellipse([7, 6, 12, 9], fill=2)                                                     # canopy
        put(im2, 8, 7, 3); put(im2, 9, 7, 3)
        d.line([(15, 8), (27, 8)], fill=2)
        for k in range(1 + f): put(im2, 31 - k, 7, 3); put(im2, 31 - k, 8, 3)                # the engine burns
        return im2
    B.add("Dart", dart_img(0), dartc); B.add("Dart burn", dart_img(1), dartc)
    spinc = [pal[6], pal[5], pal[1]]
    # a spinner saucer, frame f
    def spin_img(f):
        r = Relief(32, 16)
        r.dome(15.5, 7.5, 13.4, 7.4, 3.0)
        r.dome(15.5, 7.0, 4.6, 3.4, 3.0, 2.4)
        im2 = r.render()
        for k in range(6):                                  # lamps that go round the rim
            a = TAU * (k + f / 4) / 6
            xx = int(round(15.5 + math.cos(a) * 10.4)); yy = int(round(7.5 + math.sin(a) * 5.2))
            put(im2, xx, yy, 3); put(im2, xx + 1, yy, 2)
        return im2
    for k in range(4): B.add("Spinner %d" % (k + 1), spin_img(k), spinc)
    heavyc = [pal[15], pal[14], pal[1]]
    # a heavy gunship, 32 x 32: armour plates, a cannon, a lamp that beats; frame f
    def heavy_img(f):
        r = Relief(32, 32)
        r.box(0, 13, 10, 18)                                                                 # the cannon
        r.slab(lambda d: d.rounded_rectangle([6, 4, 31, 27], radius=7, fill=255))
        r.slab(lambda d: d.rounded_rectangle([10, 7, 28, 24], radius=4, fill=255), 1.5, 2.0, 1.5)
        r.box(24, 1, 30, 5); r.box(24, 26, 30, 30)                                           # engine pods
        r.dome(19, 15.5, 5.2, 5.2, 3.0, 3.0)
        im2 = r.render()
        d = ImageDraw.Draw(im2)
        d.ellipse([17, 13, 21, 17], fill=2 if f else 3)                                      # the lamp
        put(im2, 18, 14, 3 if f else 1)
        for xx in (1, 3, 5): put(im2, xx, 15, 2); put(im2, xx, 16, 2)                        # the cannon's vents
        for k in range(3): put(im2, 29, 9 + k * 6, 3 if (k + f) % 2 else 2)
        return im2
    B.add("Heavy", heavy_img(0), heavyc); B.add("Heavy glow", heavy_img(1), heavyc)
    seekc = [pal[3], pal[11], pal[13]]
    # a seeker mine: a ball with spikes, frame f
    def seek_img(f):
        r = Relief(16, 16)
        r.dome(7.5, 7.5, 5.4, 5.4, 4.0)
        im2 = r.render()
        for k in range(8):
            a = TAU * k / 8 + f * 0.4
            put(im2, int(round(7.5 + math.cos(a) * 7)), int(round(7.5 + math.sin(a) * 7)), 1)
            put(im2, int(round(7.5 + math.cos(a) * 6)), int(round(7.5 + math.sin(a) * 6)), 2)
        for xx in (7, 8):
            for yy in (7, 8): put(im2, xx, yy, 3 if f == 0 else 2)
        return im2
    B.add("Seeker", seek_img(0), seekc); B.add("Seeker blink", seek_img(1), seekc)
    bossc = [pal[12], pal[11], pal[13]]
    # the boss, 64 x 48: a crimson warship, nose left, its yellow core beats; frame f
    def boss_img(f):
        r = Relief(64, 48)
        r.poly([(30, 5), (44, 0), (57, 0), (51, 7)])                                         # fins
        r.poly([(30, 42), (44, 47), (57, 47), (51, 40)])
        r.poly([(0, 24), (14, 10), (40, 4), (63, 8), (63, 39), (40, 43), (14, 37), (0, 23)])
        r.poly([(12, 23), (20, 13), (42, 9), (58, 12), (58, 35), (42, 38), (20, 34)], 1.5, 2.0, 1.5)
        r.box(1, 21, 13, 26, 1.5, 2.0, 1.0)                                                  # the big gun
        r.box(52, 14, 62, 20, 1.5, 2.0, 2.0); r.box(52, 27, 62, 33, 1.5, 2.0, 2.0)          # engines
        im2 = r.render()
        d = ImageDraw.Draw(im2)
        for k in range(3):                                                                   # ports along the top
            d.rectangle([24 + k * 9, 12, 27 + k * 9, 13], fill=3 if (k + f) % 2 else 2)
        d.line([(22, 30), (50, 30)], fill=2)
        rr = 6 + f
        d.ellipse([30 - rr - 2, 23 - rr - 2, 29 + rr + 2, 22 + rr + 2], fill=2)             # the core: shoot it
        d.ellipse([30 - rr, 23 - rr, 29 + rr, 22 + rr], fill=3)
        d.ellipse([27, 20, 32, 25], fill=1)
        put(im2, 28, 21, 3); put(im2, 29, 21, 3)
        for yy in (16, 17, 29, 30): put(im2, 63, yy, 3)                                      # the engines glow
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
    # adds actor a; A[name] = its index
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
    p['steady25'] = not p_aga()         # A500 / 600: one even pace, 25 frames a second (it cannot keep up 50)
    p['_gk'] = group_key(actors)
    return p

# ================================================================== STARFIRE (up)
def starfire():
    aga_cap(STARFIRE_DEPTH)
    # 0 sky, 1 white, 2 deep shadow, 3 orange, 4-7 hull metal (dark to bright), 8 cyan lights,
    # 9-10 greens, 11-12 reds, 13 yellow, 14 purple, 15 pink (nebula)
    pal = [0x000000, 0xffffff, 0x0c1020, 0xff8020, 0x1c2438, 0x3a4a66, 0x6880a4, 0xa8c0dc,
           0x40d8ff, 0x107838, 0x70e050, 0x901820, 0xf04030, 0xffe050, 0x5028a0, 0xe060c8]
    im = g.canvas(); P = im.load()
    rnd = random.Random(31)
    T = TAU / 256
    # a dithered run through cols in a few even steps (so the A1200 version needs few in-between colours)
    def qramp(cols, t, x, y, steps=5):
        t = max(0.0, min(1.0, t)); pos = t * (len(cols) - 1); k = min(int(pos), len(cols) - 2)
        return g.dmix(cols[k], cols[k + 1], round((pos - k) * steps) / steps, x, y)
    # ---------------- deep space: a nebula of cloud noise that joins up top to bottom
    # a fixed random number 0..1 for lattice point (ix, iy) of size o
    def hsh(o, ix, iy):
        v = math.sin(ix * 127.1 + iy * 311.7 + o * 74.7) * 43758.5453
        return v - math.floor(v)
    # smooth noise 0..1 at (x, y), three sizes of cloud, the same at y and y + 256
    def cloud(x, y):
        t = 0.0; amp = 0.5
        for o in range(3):
            cell = 64 >> o; n = 256 // cell
            fx = x / cell; fy = y / cell
            ix = int(math.floor(fx)); iy = int(math.floor(fy))
            ux = fx - ix; uy = fy - iy
            ux = ux * ux * (3 - 2 * ux); uy = uy * uy * (3 - 2 * uy)
            a = hsh(o, ix, iy % n); b = hsh(o, ix + 1, iy % n)
            c = hsh(o, ix, (iy + 1) % n); e = hsh(o, ix + 1, (iy + 1) % n)
            t += amp * ((a * (1 - ux) + b * ux) * (1 - uy) + (c * (1 - ux) + e * ux) * uy)
            amp *= 0.5
        return t / 0.875
    for y in range(256):
        mid = 160 + 56 * math.sin(y * T + 0.6) + 18 * math.sin(y * T * 3 + 2.0)
        for x in range(320):
            env = math.exp(-((x - mid) / 72) ** 2)
            v = cloud(x, y) * (0.45 + 0.6 * env) - 0.45
            if v > 0: P[x, y] = qramp([0, 14, 14, 15], min(1.0, v * 2.0), x, y)
    for i in range(330):                                     # stars: mostly dim, a few bright crosses
        x = rnd.randint(0, 319); y = rnd.randint(0, 255)
        if P[x, y] != 0: continue
        c = rnd.choice([4, 4, 4, 5, 5, 5, 6, 6, 7, 8, 13, 1])
        P[x, y] = c
        if c == 1 and rnd.random() < 0.6:
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                if 0 <= x + dx < 320: P[x + dx, (y + dy) % 256] = 6

    # ---------------- the station: a hull either side of the flight lane, stepped in blocks
    WL = [44, 44, 44, 58, 58, 58, 58, 48, 48, 36, 36, 36, 50, 50, 50, 44]     # left hull width in each 16 lines
    WR = [40, 40, 52, 52, 52, 38, 38, 38, 46, 46, 60, 60, 60, 60, 46, 46]     # right
    # the hull's width on line y, 45 degree corners between the blocks
    def width(tab, y):
        b, yy = divmod(y % 256, 16)
        w0 = tab[b]
        d = tab[(b + 1) % 16] - w0; hf = abs(d) // 2
        if d and yy >= 16 - hf: return w0 + int(round(d * (yy - (16 - hf)) / (2 * hf)))
        d = w0 - tab[(b - 1) % 16]; hf = abs(d) // 2
        if d and yy < hf: return tab[(b - 1) % 16] + int(round(d * (yy + hf) / (2 * hf)))
        return w0
    # what stands on each hull; sx = pixels in from the screen's edge
    BOX = [[(10, 52, 40, 84), (8, 120, 24, 150), (14, 200, 34, 232)],        # raised blocks (sx0, y0, sx1, y1)
           [(27, 172, 51, 204), (8, 16, 26, 44), (10, 100, 28, 124)]]
    VENT = [[(10, 8, 30, 24), (8, 164, 26, 176)], [(10, 60, 28, 76), (12, 228, 34, 240)]]
    TANK = [[(20, 104, 8), (22, 244, 6)], [(18, 140, 8)]]                    # round tanks (sx, y, radius)
    # the hull's height at sx pixels in from the edge on line y (side 0 left, 1 right), None in space
    def hull(side, sx, y):
        y %= 256
        w = width(WR if side else WL, y)
        if sx < 0 or sx >= w: return None
        u = w - 1 - sx                                       # pixels from the edge by the flight lane
        z = 3.0
        if u < 2: z = 1.0 + u * 2.0                          # the lip round the hull
        elif u < 5: z = 5.0
        elif u == 5: z = 2.2
        if sx < 7: z = max(z, 3.0 + 3.2 * math.sqrt(max(0.0, 1 - ((sx - 3) / 3.5) ** 2)))   # a pipe down the outside
        if u > 5 and sx >= 7:
            col = (sx - 7) // 14                             # plates: seams between them
            if (sx - 7) % 14 == 0 or (y + col * 12 + side * 8) % 32 == 0: z -= 1.3
        for (x0, y0, x1, y1) in BOX[side]:
            if x0 <= sx <= x1 and y0 <= y <= y1:
                z = max(z, 3.0 + min(2.6, 1.3 * (1 + min(sx - x0, x1 - sx, y - y0, y1 - y))))
        for (x0, y0, x1, y1) in VENT[side]:
            if x0 <= sx <= x1 and y0 <= y <= y1:
                z = 1.6 + (1.6 if (y - y0) % 3 == 1 and x0 < sx < x1 else 0.0)
        for (cx, cy, r) in TANK[side]:
            dd = ((sx - cx) ** 2 + (y - cy) ** 2) / (r * r)
            if dd <= 1: z = max(z, 3.0 + r * 0.7 * math.sqrt(1 - dd))
        return z
    # the hull's height at screen pixel (x, y), 0 in space
    def hz(x, y):
        v = hull(0, x, y) if x < 160 else hull(1, 319 - x, y)
        if v is None: return 0.0
        return v
    for y in range(256):
        for x in list(range(0, 64)) + list(range(256, 320)):
            side = 0 if x < 160 else 1
            sx = x if side == 0 else 319 - x
            if hull(side, sx, y) is None: continue
            gx = (hz(x + 1, y) - hz(x - 1, y)) / 2 if 0 < x < 319 else 0.0
            gy = (hz(x, y + 1) - hz(x, y - 1)) / 2
            lit = (gx * 0.5 + gy * 0.6 + 0.62) / math.sqrt(gx * gx + gy * gy + 1)
            plate = (hsh(7, (sx - 7) // 14, (y + ((sx - 7) // 14) * 12 + side * 8) % 256 // 32) - 0.5) * 0.16
            P[x, y] = qramp([2, 4, 5, 6, 7], 0.5 + (lit - 0.62) * 1.25 + plate, x, y, 4)
    # lights and paint on the hulls
    # sets hull pixel (sx in from the edge of that side, y) to colour c
    def paint(side, sx, y, c):
        x = sx if side == 0 else 319 - sx
        if 0 <= x < 320: P[x, y % 256] = c
    for side in (0, 1):
        tab = WR if side else WL
        for y in range(256):                                 # a strip of cyan lights along the lip
            w = width(tab, y)
            if w == tab[(y % 256) // 16] and y % 16 in (5, 6, 7, 8, 9, 10): paint(side, w - 3, y, 8)
        for k, (x0, y0, x1, y1) in enumerate(BOX[side]):
            for sx in range(x0 + 4, x1 - 3, 3):              # rows of windows on the blocks, most of them lit
                for yy in range(y0 + 5, y1 - 4, 5):
                    lit = hsh(9, sx + side * 50, yy) < 0.62
                    paint(side, sx, yy, 13 if lit else 2); paint(side, sx + 1, yy, 13 if lit else 2)
            paint(side, x0 + 2, y0 + 2, 12); paint(side, x1 - 2, y1 - 2, 12)     # red warning lights
        for (cx, cy, r) in TANK[side]:
            paint(side, cx - r // 2, cy - r // 2, 1)         # a glint on each tank
            paint(side, cx - r // 2 + 1, cy - r // 2, 7)
    # the turrets' gun pads: yellow and black hazard stripes round the first block of each hull
    for side in (0, 1):
        x0, y0, x1, y1 = BOX[side][0]
        for sx in range(x0, x1 + 1):
            for yy in range(y0, y1 + 1):
                if min(sx - x0, x1 - sx, yy - y0, y1 - yy) in (1, 2):
                    paint(side, sx, yy, 13 if (sx + yy) // 3 % 2 else 2)
        for sx in range(x0 + 3, x1 - 2):                     # a plain floor inside them
            for yy in range(y0 + 3, y1 - 2):
                paint(side, sx, yy, g.dmix(4, 5, 0.5, sx, yy))
    # docking arms reaching into the lane: open girders, the stars show through
    for side, y0, reach in ((0, 20, 122), (0, 150, 98), (1, 86, 118), (1, 214, 96)):
        for sx in range(width(WR if side else WL, y0 + 4) - 1, reach):
            for r in range(10):
                c = -1
                if r == 0: c = 7
                elif r == 1: c = 6
                elif r == 8: c = 5
                elif r == 9: c = 4
                elif (sx + r) % 14 < 2 or (sx - r) % 14 < 2: c = 5       # cross bracing
                if sx % 28 in (0, 1) and 1 < r < 8: c = 6                # uprights
                if c >= 0: paint(side, sx, y0 + r, c)
        for sx in range(reach, reach + 8):                   # the pad on the end, a red lamp on it
            for r in range(-2, 12):
                c = 5
                if r == -2 or sx == reach: c = 7
                elif r == 11 or sx == reach + 7: c = 4
                paint(side, sx, y0 + r, c)
        for sx in (reach + 3, reach + 4):
            for r in (4, 5): paint(side, sx, y0 + r, 12)
        paint(side, reach + 3, y0 + 4, 13)

    # ---------------- sprites
    B = Bank()
    shipc = [0x9ab8f0, 0x2848b0, 0xffffff]                    # hardware sprite: pale blue hull, deep blue, white
    def ship_img(flame, bank=0):
        """the fighter (16 x 24 hardware sprite), nose up; flame = exhaust frame, bank -1 rolling left, 1 right"""
        r = Relief(16, 24)
        xl = 2 if bank < 0 else 0                             # the wing it rolls onto is seen end on: shorter
        xr = 13 if bank > 0 else 15
        r.poly([(5, 9), (xl, 15), (xl, 19), (5, 17)])
        r.poly([(10, 9), (xr, 15), (xr, 19), (10, 17)])
        r.poly([(7, 1), (8, 1), (10, 8), (10, 17), (8, 20), (7, 20), (5, 17), (5, 8)], 1.5, 2.0, 1.5)
        im2 = r.render()
        for yy in range(7, 11):                               # canopy
            put(im2, 7, yy, 2); put(im2, 8, yy, 2)
        put(im2, 8 if bank > 0 else 7, 7, 3)
        for xx in (xl, xr):                                   # guns on the wing tips
            for yy in range(12, 16): put(im2, xx, yy, 2 if yy > 12 else 3)
        if bank < 0:                                          # the far wing catches the light
            for yy in range(10, 19):
                for xx in range(11, 16):
                    if im2.getpixel((xx, yy)) == 1 and (xx + yy) & 1: put(im2, xx, yy, 3)
        if bank > 0:                                          # or lies in shadow
            for yy in range(10, 19):
                for xx in range(0, 5):
                    if im2.getpixel((xx, yy)) == 1 and (xx + yy) & 1: put(im2, xx, yy, 2)
        for k in range(flame):                                # the engine's flame
            put(im2, 7, 21 + k, 3 if k < flame - 1 else 1); put(im2, 8, 21 + k, 3 if k < flame - 1 else 1)
        return im2
    for nm, bk in (("Fighter", 0), ("Fighter left", -1), ("Fighter right", 1)):
        B.add(nm, ship_img(2, bk), shipc); B.add(nm + " flame", ship_img(3, bk), shipc); B.add(nm + " flame 2", ship_img(1, bk), shipc)
    # the M capsule, in the fighter's colours (one sprite pair); shine = where the shine is
    def capsule_m(shine):
        im2, d = new(16, 24)
        d.rounded_rectangle([1, 7, 14, 16], radius=4, fill=2)
        for k in range(3, 13):
            if (k - shine) % 10 in (0, 1): put(im2, k, 8, 1)
        for r, row in enumerate(LETTER['M']):
            for c, ch in enumerate(row):
                if ch == '1': put(im2, 6 + c, 9 + r, 3)
        return im2
    for k in range(3): B.add("Capsule M %d" % (k + 1), capsule_m(k * 4), shipc)
    optc = [0xff9020, 0x903000, 0xfff080]
    for k, pz in enumerate((0, 1, 2, 1)): B.add("Option %d" % (k + 1), orb(5.6, pz), optc)
    plc = [0xff40a0, 0x701050, 0xffe0ff]
    B.add("Plasma", orb(3.2, 0), plc); B.add("Plasma flicker", orb(3.2, 1.2), plc)
    capc = [0xe02828, 0x600808, 0xffffff]
    for L in "PS":
        for k in range(3): B.add("Capsule %s %d" % (L, k + 1), capsule(L, k * 4), capc)
    lasc = [pal[8], pal[14], pal[1]]
    # twin laser bolts from the wing guns, going up: white heads, cyan tails; n = how far they have grown.
    # Cyan and white are each one bitplane, so the blitter draws two of the four planes the cheap way
    def laser_img(n):
        im2, _ = new(16, 16)
        for x0 in (0, 14):
            for yy in range(n, 12):
                v = 3 if yy < 6 + n else 1
                put(im2, x0, yy, v); put(im2, x0 + 1, yy, v)
        return im2
    B.add("Laser", laser_img(0), lasc); B.add("Laser glint", laser_img(2), lasc)
    sauc = [pal[10], pal[9], pal[1]]
    # a saucer, 32 x 24: a disc with a glass dome, lamps running round its rim; frame f of 4
    def saucer_img(f):
        r = Relief(32, 24)
        r.dome(15.5, 13, 15.4, 9.4, 3.2)
        r.dome(15.5, 11.5, 6.6, 5.6, 4.5, 2.0)
        im2 = r.render()
        for yy in range(24):
            for xx in range(32):
                dd = ((xx - 15.5) / 6.6) ** 2 + ((yy - 11.5) / 5.6) ** 2
                v = im2.getpixel((xx, yy))
                if dd <= 0.72:                                # the glass: a tone lighter
                    if v == 2: put(im2, xx, yy, 1)
                    elif v == 1 and (xx + yy) & 1: put(im2, xx, yy, 3)
                elif dd <= 1.15 and v: put(im2, xx, yy, 2)   # its dark seat
        for k in range(8):
            a = TAU * (k + f / 4) / 8
            xx = int(round(15.5 + math.cos(a) * 12.4)); yy = int(round(13 + math.sin(a) * 7.0))
            put(im2, xx, yy, 3)
        return im2
    for k in range(4): B.add("Saucer %d" % (k + 1), saucer_img(k), sauc)
    dartc = [pal[3], pal[11], pal[13]]
    # a dart diving down, frame f
    def dart_img(f):
        r = Relief(16, 24)
        r.poly([(7, 23), (8, 23), (11, 12), (15, 3), (11, 6), (8, 3), (7, 3), (4, 6), (0, 3), (4, 12)])
        r.poly([(7, 21), (8, 21), (10, 11), (8, 5), (7, 5), (5, 11)], 1.5, 2.0, 1.5)
        im2 = r.render()
        for yy in range(11, 17): put(im2, 7, yy, 2); put(im2, 8, yy, 2)   # the canopy
        put(im2, 7, 15, 3); put(im2, 7, 16, 3)
        for k in range(1 + f): put(im2, 7, 2 - k, 3); put(im2, 8, 2 - k, 3)    # the engine burns at the back
        return im2
    B.add("Dart", dart_img(0), dartc); B.add("Dart burn", dart_img(1), dartc)
    turc = [pal[12], pal[11], pal[13]]
    # a gun turret on the hull, 16 x 16; its twin guns point across the lane (side 0: to the right), frame f
    def turret_img(f, side):
        r = Relief(16, 16)
        r.poly([(4, 1), (11, 1), (14, 4), (14, 11), (11, 14), (4, 14), (1, 11), (1, 4)])
        r.dome(6.5, 7.5, 4.6, 4.6, 3.0, 1.5)
        im2 = r.render()
        for yy in (5, 9):                                     # the guns
            for xx in range(10, 16): put(im2, xx, yy, 3 if xx == 15 and f == 0 else 1); put(im2, xx, yy + 1, 2)
        for xx in (6, 7):                                     # its eye blinks
            for yy in (7, 8): put(im2, xx, yy, 3 if f == 0 else 2)
        if side: im2 = flip_h(im2)
        return im2
    B.add("Turret", turret_img(0, 0), turc); B.add("Turret blink", turret_img(1, 0), turc)
    B.add("Turret R", turret_img(0, 1), turc); B.add("Turret R blink", turret_img(1, 1), turc)
    cruc = [pal[6], pal[4], pal[1]]
    # a cruiser, 48 x 32, nose down: a spine, swept wings, an engine pod on each; frame f
    def cruiser_img(f):
        r = Relief(48, 32)
        r.poly([(18, 5), (3, 8), (0, 17), (7, 23), (19, 21)])
        r.poly([(29, 5), (44, 8), (47, 17), (40, 23), (28, 21)])
        r.poly([(20, 0), (27, 0), (31, 9), (28, 25), (24, 31), (23, 31), (19, 25), (16, 9)], 1.5, 2.0, 1.5)
        r.poly([(22, 3), (25, 3), (27, 10), (25, 15), (22, 15), (20, 10)], 1.5, 2.0, 3.0)
        r.dome(8, 13, 4.6, 6.4, 3.4, 1.6)
        r.dome(39, 13, 4.6, 6.4, 3.4, 1.6)
        im2 = r.render()
        d = ImageDraw.Draw(im2)
        d.line([(23, 17), (23, 24)], fill=2); d.line([(24, 17), (24, 24)], fill=2)   # the bridge
        put(im2, 23, 23, 3); put(im2, 23, 24, 3)
        for cx in (8, 39):                                    # the pods' lamps beat
            d.ellipse([cx - 2, 11, cx + 1, 14], fill=3 if f == 0 else 2)
            put(im2, cx - 1, 12, 1 if f == 0 else 3)
        for xx in (21, 26):                                   # the engines at the back
            put(im2, xx, 0, 3); put(im2, xx, 1, 3 if f else 1)
        for xx in (3, 44):                                    # wing guns
            for yy in range(18, 24): put(im2, xx, yy, 2)
        return im2
    B.add("Cruiser", cruiser_img(0), cruc); B.add("Cruiser glow", cruiser_img(1), cruc)
    bossc = [pal[12], pal[11], pal[13]]
    # the boss, 64 x 48: a crimson dreadnought, nose down, its yellow core beats; frame f
    def boss_img(f):
        r = Relief(64, 48)
        r.poly([(32, 47), (40, 38), (52, 34), (63, 26), (63, 12), (54, 5), (42, 3), (32, 0), (22, 3), (10, 5), (0, 12), (0, 26), (12, 34), (24, 38)])
        r.poly([(23, 5), (40, 5), (46, 16), (40, 35), (32, 44), (31, 44), (23, 35), (17, 16)], 1.5, 2.0, 1.5)
        r.poly([(27, 30), (36, 30), (36, 34), (32, 39), (31, 39), (27, 34)], 1.5, 2.0, 3.0)
        r.box(1, 20, 14, 24, 1.5, 2.0, 1.0); r.box(49, 20, 62, 24, 1.5, 2.0, 1.0)
        r.dome(9, 17, 7.5, 9, 4.0, 2.0)
        r.dome(54.5, 17, 7.5, 9, 4.0, 2.0)
        im2 = r.render()
        d = ImageDraw.Draw(im2)
        for xx in (5, 57):                                    # side guns
            d.rectangle([xx, 27, xx + 2, 39], fill=2)
            d.line([(xx, 27), (xx, 39)], fill=1)
            put(im2, xx + 1, 39, 3)
        for cx in (9, 54):                                    # lamps on the pods
            d.ellipse([cx - 2, 14, cx + 2, 18], fill=2)
            put(im2, cx, 16, 3); put(im2, cx - 1, 15, 3 if f else 1)
        for k in range(4):                                    # a row of ports along the top
            d.rectangle([22 + k * 6, 8, 24 + k * 6, 9], fill=3 if (k + f) % 2 else 2)
        rr = 6 + f
        d.ellipse([32 - rr - 2, 21 - rr - 2, 31 + rr + 2, 20 + rr + 2], fill=2)     # the core: shoot it
        d.ellipse([32 - rr, 21 - rr, 31 + rr, 20 + rr], fill=3)
        d.ellipse([29, 18, 34, 23], fill=1)
        put(im2, 30, 19, 3); put(im2, 31, 19, 3)
        d.line([(31, 34), (31, 41)], fill=2); d.line([(32, 34), (32, 41)], fill=1)  # the prow
        return im2
    B.add("Boss", boss_img(0), bossc); B.add("Boss pulse", boss_img(1), bossc)
    warpc = [pal[8], pal[14], pal[1]]
    for k in range(3): B.add("Warp %d" % (k + 1), warp(32, k), warpc)
    boomc = [pal[3], pal[12], pal[13]]
    for k in range(6): B.add("Boom %d" % (k + 1), boom(32, 32, k, 6, 5), boomc)
    for k in range(8): B.add("Big boom %d" % (k + 1), boom(64, 48, k, 8, 17), boomc)

    # ---------------- actors (the backdrop moves down: flyers come in from the top, edge 0)
    actors = []
    A = {}
    # adds actor a; A[name] = its index
    def add(a):
        A[a['name']] = len(actors); actors.append(a)
        return a
    # the three flame frames of fighter picture nm
    def burn(nm): return [B[nm], B[nm + " flame"], B[nm + " flame 2"]]
    turn = {0: (burn("Fighter"), 3, 0), 4: (burn("Fighter"), 3, 0), 8: (burn("Fighter"), 3, 0)}
    for k in (5, 6, 7): turn[k] = (burn("Fighter right"), 3, 0)          # it rolls into a turn
    for k in (9, 10, 11): turn[k] = (burn("Fighter left"), 3, 0)
    ship = add(act("Ship", B["Fighter"], 0, 2, 152, 200, anims=turn))
    ship['anim_dirs'] = True
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
    # The A500 / 600 version is a little lighter - three saucers and two darts, not four and three -
    # and runs at a steady 25 frames a second (steady25): its 68000 cannot draw this many BOBs 50
    # times a second, and one even pace plays better than speeding up whenever the screen empties
    aga = p_aga()
    nsau = 4 if aga else 3
    ndart = 3 if aga else 2
    for k in range(nsau):                                    # saucers weave down in a column
        add(act("Saucer %d" % (k + 1), B["Saucer 1"], 10, 2, 144, 10 + k * 34, bob=True, pattern=1, fast=1,
                anims={0: ([B["Saucer %d" % (j + 1)] for j in range(4)], 4, 0)}))
    for k, (x, y) in enumerate(((84, 60), (200, 120), (224, 20))[:ndart]):
        add(act("Dart %d" % (k + 1), B["Dart"], 10, 3, x, y, bob=True, pattern=2, left=(k % 2 == 1), fast=1,
                anims={0: ([B["Dart"], B["Dart burn"]], 4, 0)}))
    # the turrets sit on the hazard pads painted on the hulls (pattern 4: they move with the scenery)
    add(act("Turret 1", B["Turret"], 10, 1, 17, 60, bob=True, pattern=4, hits=2, anims={0: ([B["Turret"], B["Turret blink"]], 12, 0)}))
    add(act("Turret 2", B["Turret R"], 10, 1, 272, 180, bob=True, pattern=4, hits=2, anims={0: ([B["Turret R"], B["Turret R blink"]], 12, 0)}))
    add(act("Cruiser", B["Cruiser"], 10, 1, 88, 100, bob=True, hits=8, frm=2, anims={0: ([B["Cruiser"], B["Cruiser glow"]], 10, 0)}))
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
    saucers = ["Saucer %d" % (k + 1) for k in range(nsau)]
    darts = ["Dart %d" % (k + 1) for k in range(ndart)]
    enemies = [(nm, 100, True) for nm in saucers] + [(nm, 150, False) for nm in darts] +               [("Turret 1", 200, True), ("Turret 2", 200, True), ("Cruiser", 500, True)]      # a turret comes back on its pad
    rules = common_rules(R, A, enemies, {saucers[-1]: "Capsule P", "Dart 2": "Capsule S", "Cruiser": "Capsule M", "Turret 2": "Capsule P"},
                         [("Turret 1", 2), ("Turret 2", 3), ("Cruiser", 2), ("Boss", 1)])
    rules += boss_arrives(R, A, saucers + [nm for nm in darts if nm != "Dart 2"])
    rules += flow(R, A)

    sky = [0x02041a, 0x0e0a30, 0x240c44, 128]
    p = g.make_project("Starfire", pal, im, [], actors, rules, sky, msg_col=13, lives=3, sfx=g.sfx_list(SFX),
                       over="FIGHTER LOST - GAME OVER", win="THE STATION IS SAFE! - PRESS FIRE")
    p['sprites'] = B.s + [blank(i) for i in range(len(B.s), 128)]
    p.update(scroll_dir=1, scroll_speed=4)
    p.update(levels_on=True, levels=[dict(seed=3000 + i * 37, hilly=0, base=230, heights=[240] * 320) for i in range(3)],
             hills_on=False, terrain_cols=[4, 5, 4, 6])
    finish(p, songs(), "STARFIRE", "PRESS FIRE TO LAUNCH", "Neon", 4)
    p['steady25'] = not aga
    # the second and third stations: other metal, another nebula (a named palette for each level)
    level_looks(p, [("Bronze dock", {2: 0x140c08, 4: 0x2a1c14, 5: 0x5a4028, 6: 0xa07848, 7: 0xe8c890, 14: 0x184888, 15: 0x40b8d8}),
                    ("Violet reach", {2: 0x100814, 4: 0x2a1424, 5: 0x583050, 6: 0x906090, 7: 0xd8a8d0, 14: 0x0c5a40, 15: 0x40d890})])
    p['_gk'] = group_key(actors)
    return p
