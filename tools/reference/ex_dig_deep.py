# Dig Deep - the tile world example (scrolling both ways, dig and place, 20 tile types).
# Made by gen_examples.py: python gen_examples.py
import random, math
from PIL import Image
import art

W, H = 128, 64          # map size in tiles

# ---- palette (16 colours, A500): colour 0 is the copper sky
# colour 0 shows the copper sky, so only air (and the gaps in leaves) use it
PAL = [0x000000, 0xffffff, 0x4a2a14, 0x7a4a24, 0xa86c3c, 0x34343e, 0x5e5e6a, 0x8a8a96,
       0x2a6a1a, 0x48a02a, 0x8ad04a, 0xffcc22, 0x40e8ff, 0xd83020, 0xff8820, 0x161626]
AIR, GRASS, DIRT, STONE, SLATE, SAND, CLAY, COAL, IRON, GOLD, GEM, WOOD, LEAVES, BRICK, BEDROCK, MOSS, WATER, DWALL, SWALL, TORCH, LADDER = range(21)
WATER2, WATER3, WATER4, TORCH2, TORCH3 = range(21, 26)    # animated tiles' frames (ADAM Pro, data version 15)

def noise(x, y, s):
    v = (x * 374761393 + y * 668265263 + s * 2147483647) & 0xffffffff
    v = (v ^ (v >> 13)) * 1274126177 & 0xffffffff
    return (v ^ (v >> 16)) & 0xffff

def tex(base, dark, light, seed, dens=5):
    import gen_examples as g
    aga = g.AGA['on']
    px = []
    for y in range(16):
        for x in range(16):
            n = noise(x, y, seed) % 16
            v = base
            if n < dens: v = dark
            elif n > 15 - dens // 2: v = light
            if aga:
                # A1200: soft in-between shades round the dark and light specks
                if n == dens or n == dens + 1: v = g.dmix(dark, base, 0.5, x, y)
                elif n == 15 - dens // 2 or n == 14 - dens // 2: v = g.dmix(base, light, 0.5, x, y)
                elif n < dens and noise(x, y, seed + 99) % 3 == 0: v = g.dmix(dark, base, 0.25, x, y)
            px.append(v)
    return px

def blobs(px, col, hi, seed, n=3, r=2.2):
    import gen_examples as g
    aga = g.AGA['on']
    rnd = random.Random(seed)
    for _ in range(n):
        cx, cy = rnd.randint(3, 12), rnd.randint(3, 12)
        for y in range(16):
            for x in range(16):
                d = (x - cx) ** 2 + (y - cy) ** 2
                if aga and r * r <= d < (r + 0.9) ** 2 and px[y * 16 + x] != col:
                    px[y * 16 + x] = g.dmix(px[y * 16 + x], col, 0.5, x, y)    # A1200: a soft rim round the ore
                if d < r * r: px[y * 16 + x] = col
                if aga and 1.2 <= d < 2.6: px[y * 16 + x] = g.dmix(col, hi, 0.5, x, y)
                if d < 1.2: px[y * 16 + x] = hi
    return px

def tiles():
    import gen_examples as ge
    t = []
    def add(name, px, solid=True, dig=True, hard=12, points=0, goal=False, sound=-1, becomes=0, ladder=False):
        t.append(dict(name=name, px=px, solid=solid, dig=dig, hard=hard, points=points, goal=goal, sound=sound, becomes=becomes, ladder=ladder))
    add("AIR", [0] * 256, False, False)
    g = tex(3, 2, 4, 1)
    for y in range(5):
        for x in range(16):
            edge = 3 + (noise(x, 0, 9) % 3)
            if y < edge: g[y * 16 + x] = 9 if (x + y) % 3 else 10
            elif y == edge: g[y * 16 + x] = 8
    add("GRAS", g, hard=10, sound=3, becomes=AIR)
    add("DIRT", tex(3, 2, 4, 2), hard=10, sound=3, becomes=DWALL)
    st = tex(6, 5, 7, 3, 4)
    for y in range(16):
        for x in range(16):
            if (y % 8 == 0) or (x == (0 if y < 8 else 8)): st[y * 16 + x] = 5
    add("STON", st, hard=22, sound=3, becomes=SWALL)
    sl = tex(5, 15, 6, 4, 6)
    for i in range(256):
        if noise(i % 16, i // 16, 44) % 23 == 0: sl[i] = 12 if i % 2 else 7
    add("SLAT", sl, hard=32, sound=3, becomes=SWALL)
    add("SAND", tex(4, 3, 11, 5, 3), hard=6, sound=3, becomes=AIR)
    add("CLAY", tex(13, 2, 4, 6, 6), hard=14, sound=3, becomes=DWALL)
    add("COAL", blobs(tex(6, 5, 7, 7, 3), 15, 5, 70, 4, 2.0), hard=26, points=2, sound=4, becomes=SWALL)
    add("IRON", blobs(tex(6, 5, 7, 8, 3), 4, 14, 80, 4, 1.8), hard=30, points=5, sound=4, becomes=SWALL)
    add("GOLD", blobs(tex(6, 5, 7, 9, 3), 11, 1, 90, 4, 1.9), hard=34, points=20, goal=True, sound=0, becomes=SWALL)
    gm = tex(5, 15, 6, 10, 4)
    for (cx, cy) in ((5, 5), (11, 9), (6, 12)):
        for y in range(16):
            for x in range(16):
                if abs(x - cx) + abs(y - cy) <= 2: gm[y * 16 + x] = 12
        gm[cy * 16 + cx] = 1
    add("GEM", gm, hard=40, points=50, goal=True, sound=0, becomes=SWALL)
    wd = []
    for y in range(16):
        for x in range(16):
            v = 0
            if 3 <= x <= 12:
                v = 3
                if x in (3, 12): v = 2
                if x in (6, 9) and (y + x) % 5: v = 2
                if x == 7 and y % 6 == 2: v = 4
            wd.append(v)
    add("WOOD", wd, False, True, hard=12, sound=3, becomes=AIR)
    lv = []
    for y in range(16):
        for x in range(16):
            n = noise(x, y, 12) % 16
            lv.append(0 if n < 2 else (8 if n < 7 else (9 if n < 13 else 10)))
    add("LEAF", lv, False, True, hard=3, sound=3, becomes=AIR)
    br = []
    for y in range(16):
        for x in range(16):
            row = y // 4
            off = 0 if row % 2 == 0 else 4
            mortar = (y % 4 == 3) or ((x + off) % 8 == 7)
            br.append(5 if mortar else (13 if noise(x, y, 13) % 5 else 14))
    add("BRIK", br, hard=60, sound=3, becomes=SWALL)
    add("BEDR", tex(15, 5, 2, 14, 7), dig=False)
    ms = tex(6, 5, 7, 15, 4)
    for y in range(16):
        for x in range(16):
            if noise(x, y, 151) % 9 == 0 or (y < 3 and noise(x, y, 152) % 3 == 0): ms[y * 16 + x] = 9 if x % 2 else 8
    add("MOSS", ms, hard=22, sound=3, becomes=SWALL)
    def water(ph):
        # ph = 0..3: the surface ripple moves a pixel a frame and the sparkles move about
        wt = []
        for y in range(16):
            for x in range(16):
                v = 15 if (x + y) % 3 else 5
                if ge.AGA['on']: v = ge.dmix(15, 5, 0.25 if (x + 2 * y) % 7 else 0.5, x, y)   # A1200: one shade, a ripple
                if y == 0: v = 12 if ((x + ph) // 2) % 2 else 7
                elif (x + y * 3 + ph * 5) % 11 == 0: v = 12
                wt.append(v)
        return wt
    add("WATR", water(0), False, False)
    add("DWAL", tex(2, 15, 3, 17, 5), False, False)
    add("SWAL", tex(15, 5, 5, 18, 6), False, False)
    def torch(dx, dt):
        # the flame leans dx pixels and stands dt pixels taller
        tc = tex(15, 5, 5, 18, 6)
        for y in range(16):
            for x in range(16):
                if 7 <= x <= 8 and 7 <= y <= 14: tc[y * 16 + x] = 3
                if (x - 7.5 - dx) ** 2 / 3 + (y - 4.5 + dt) ** 2 / (6 + dt) < 1.5: tc[y * 16 + x] = 14
                if (x - 7.5 - dx / 2) ** 2 + (y - 5) ** 2 < 1.5: tc[y * 16 + x] = 11
        return tc
    add("TRCH", torch(0, 0), False, True, hard=2, sound=4, becomes=SWALL)
    # a ladder part: two rails and rungs, see-through between them (the player climbs it)
    ld = []
    for y in range(16):
        for x in range(16):
            v = 0
            if x in (3, 12): v = 3
            if x in (4, 13): v = 2
            if 4 <= x <= 11 and y % 5 == 2: v = 4
            if 4 <= x <= 11 and y % 5 == 3: v = 2
            ld.append(v)
    add("LADR", ld, False, True, hard=4, sound=4, becomes=AIR, ladder=True)
    # animated tiles (ADAM Pro): the frames go after the others, so the tile numbers stay put
    for ph in (1, 2, 3): add("WAT" + str(ph + 1), water(ph), False, False)
    add("TRC2", torch(-0.8, 0.6), False, False)
    add("TRC3", torch(0.8, 0.0), False, False)
    t[WATER].update(anim=[WATER, WATER2, WATER3, WATER4], anim_rate=9, anim_mode=0)
    t[TORCH].update(anim=[TORCH, TORCH2, TORCH, TORCH3], anim_rate=6, anim_mode=0)
    return t

def world(seed=1985):
    rnd = random.Random(seed)
    m = [AIR] * (W * H)
    def at(x, y): return m[y * W + x]
    def put(x, y, v):
        if 0 <= x < W and 0 <= y < H: m[y * W + x] = v
    # surface: a smoothed random walk
    h = []
    v = 16.0
    for x in range(W):
        v += rnd.uniform(-1.1, 1.1)
        v = max(11, min(22, v))
        h.append(v)
    hs = [round(sum(h[max(0, x - 2):x + 3]) / len(h[max(0, x - 2):x + 3])) for x in range(W)]
    for x in range(4, 14): hs[x] = hs[8]                   # a flat start
    for x in range(W):
        top = hs[x]
        dirt = top + 4 + (noise(x, 0, 21) % 3)
        for y in range(top, H):
            if y == top: v = GRASS
            elif y <= dirt: v = DIRT
            elif y < 40 + (noise(x, 1, 22) % 4): v = STONE
            else: v = SLATE
            m[y * W + x] = v
        for y in range(H - 2, H):
            if y == H - 1 or noise(x, y, 23) % 3: m[y * W + x] = BEDROCK
    # sand and clay pockets
    for _ in range(9):
        cx, cy = rnd.randint(16, W - 4), 0
        cy = hs[cx] + rnd.randint(1, 3)
        for y in range(cy, cy + 3):
            for x in range(cx - 3, cx + 4):
                if 0 <= x < W and at(x, y) in (DIRT, GRASS) and (x - cx) ** 2 / 9 + (y - cy) ** 2 / 4 < 1.4: put(x, y, SAND)
    for _ in range(14):
        cx = rnd.randint(4, W - 4)
        cy = hs[cx] + rnd.randint(2, 6)
        for y in range(cy - 1, cy + 2):
            for x in range(cx - 2, cx + 3):
                if 0 <= x < W and at(x, y) == DIRT: put(x, y, CLAY)
    # caves: worms
    for _ in range(9):
        x, y = rnd.uniform(6, W - 6), rnd.uniform(28, H - 6)
        ang = rnd.uniform(0, math.tau)
        for _ in range(rnd.randint(30, 70)):
            ang += rnd.uniform(-0.6, 0.6)
            x += math.cos(ang); y += math.sin(ang) * 0.5
            if not (2 < x < W - 3 and 26 < y < H - 4): ang += math.pi; continue
            for (dx, dy) in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
                xx, yy = int(x) + dx, int(y) + dy
                if 0 <= xx < W and 0 <= yy < H - 2 and at(xx, yy) not in (BEDROCK,):
                    put(xx, yy, SWALL if yy > hs[xx] + 7 else DWALL)
    # one cave mouth down from the surface, near the start
    x = 30
    for y in range(hs[x] + 1, 32):
        for xx in (x, x + 1):
            put(xx, y, DWALL if y < hs[xx] + 7 else SWALL)
        if y % 3 == 0: x += 1
    # ores, by depth
    def ore(kind, n, y0, y1, size):
        for _ in range(n):
            cx, cy = rnd.randint(2, W - 3), rnd.randint(y0, y1)
            for _ in range(size):
                xx, yy = cx + rnd.randint(-1, 1), cy + rnd.randint(-1, 1)
                if 0 <= xx < W and 0 <= yy < H and at(xx, yy) in (STONE, SLATE): put(xx, yy, kind)
    ore(COAL, 46, 22, 46, 6)
    ore(IRON, 30, 30, 56, 5)
    ore(GOLD, 18, 38, 60, 4)
    ore(GEM, 12, 46, 60, 2)
    # moss on cave floors
    for y in range(24, H - 2):
        for x in range(W):
            if at(x, y) in (STONE, SLATE) and at(x, y - 1) == SWALL and rnd.random() < 0.5: put(x, y, MOSS)
    # water in some cave hollows
    for y in range(H - 3, 26, -1):
        for x in range(W):
            if at(x, y) == SWALL and at(x, y + 1) in (STONE, SLATE, MOSS, BEDROCK) and noise(x // 6, y // 4, 31) % 5 == 0:
                put(x, y, WATER)
    # an old brick vault with gems, deep on the right
    vx, vy = 96, 50
    for y in range(vy, vy + 8):
        for x in range(vx, vx + 18):
            edge = y in (vy, vy + 7) or x in (vx, vx + 17)
            put(x, y, BRICK if edge else SWALL)
    for x in (vx + 4, vx + 8, vx + 12): put(x, vy + 6, GEM)
    put(vx + 3, vy + 3, TORCH); put(vx + 14, vy + 3, TORCH)
    for y in range(36, vy + 1):                            # a shaft down to its roof
        put(vx + 9, y, SWALL); put(vx + 10, y, SWALL)
    put(vx + 9, vy, SWALL); put(vx + 10, vy, SWALL)
    # torches on cave walls
    for y in range(26, H - 3):
        for x in range(W):
            if at(x, y) == SWALL and at(x, y + 1) == SWALL and noise(x, y, 41) % 61 == 0: put(x, y, TORCH)
    # trees on the grass
    x = 18
    while x < W - 4:
        top = hs[x]
        if at(x, top) == GRASS and abs(hs[x - 1] - top) + abs(hs[x + 1] - top) <= 1:
            th = rnd.randint(3, 5)
            for y in range(top - th, top): put(x, y, WOOD)
            cy = top - th
            for yy in range(cy - 3, cy + 1):
                for xx in range(x - 2, x + 3):
                    if (xx - x) ** 2 + (yy - cy + 1) ** 2 <= 5 and at(xx, yy) == AIR: put(xx, yy, LEAVES)
        x += rnd.randint(7, 14)
    return m, hs

# ---- sprites: the miner (with a pickaxe), slimes, bats and a mole
def miner_rows(legs=0, arm=None, bob=0):
    body = [
        "................",
        "......3333......",
        ".....333333.....",
        "....33333333....",
        ".....111111.....",
        ".....1.11.1.....",
        ".....111111.....",
        "......1111......",
        ".....222222.....",
        "....22222222....",
        "...1222222221...",
        "...1.222222.1...",
        "...1.222222.1...",
        ".....222222.....",
        ".....222222.....",
    ]
    legsets = [
        [".....22..22.....", ".....22..22.....", ".....22..22.....", ".....11..11.....", "....111..111...."],
        ["....22....22....", "....22....22....", "...22......22...", "...11......11...", "..111......111.."],
        [".....22.22......", ".....22.22......", "......2222......", "......1111......", ".....111111....."],
        ["......22..22....", ".....22...22....", ".....22....22...", ".....11....11...", "....111....111.."],
    ]
    rows = body + legsets[legs] + ["................"] * 4
    rows = [list(r) for r in rows]
    def dot(x, y, c):
        if 0 <= x < 16 and 0 <= y < 24: rows[y][x] = c
    if arm == "up":          # pick raised over the head
        for y in range(1, 10): dot(12, y, '1')
        for x in range(10, 16): dot(x, 1, '3')
        dot(15, 2, '3'); dot(10, 2, '3')
    if arm == "fwd":         # pick swung out in front
        for x in range(12, 16): dot(x, 10, '1')
        for y in range(8, 14): dot(15, y, '3')
        dot(14, 8, '3'); dot(14, 13, '3')
    if arm == "down":        # pick swung down at the feet
        for y in range(10, 20): dot(13, y, '1')
        for x in range(11, 16): dot(x, 20, '3')
        dot(11, 19, '3'); dot(15, 19, '3')
    if arm == "high":        # pick hitting the roof
        for y in range(0, 6): dot(11, y, '1')
        for x in range(8, 14): dot(x, 0, '3')
    if arm == "sword up":    # sword raised behind the head
        for y in range(1, 8): dot(13, y, '3')
        dot(12, 8, '1'); dot(13, 8, '1'); dot(14, 8, '1'); dot(13, 9, '1')
    if arm == "sword fwd":   # sword thrust out in front
        for x in range(13, 16): dot(x, 10, '3')
        dot(12, 9, '1'); dot(12, 10, '1'); dot(12, 11, '1')
    if arm == "sword low":   # the slash follows through, low
        dot(12, 11, '1'); dot(13, 11, '1')
        for k in range(3): dot(13 + k, 12 + k, '3')
    rows = ["".join(r) for r in rows]
    if bob:
        rows = rows[bob:] + ["................"] * bob
    return rows

ROCK = ["................"] * 14 + [
    "......2222......",
    "....22333322....",
    "...2333333332...",
    "..233133333332..",
    "..233333333332..",
    "..233333333322..",
    "..223333333222..",
    "...2223332222...",
    "....22222222....",
    "................"]

def bell_rows(sw=0):
    # a little bell hung from a wooden post; sw = -1 / 0 / 1 swings it
    rows = [['.'] * 16 for _ in range(24)]
    def dot(x, y, c):
        if 0 <= x < 16 and 0 <= y < 24: rows[y][x] = c
    for y in range(2, 24): dot(2, y, '1'); dot(3, y, '1')          # the post
    for x in range(1, 14): dot(x, 2, '1')                          # the beam
    dot(4, 3, '1'); dot(5, 3, '1'); dot(4, 4, '1')                 # its brace
    for x in range(0, 6): dot(x, 23, '1')                          # its foot
    cx = 10
    dot(cx, 3, '2'); dot(cx, 4, '2')                               # its hook
    for y, w in ((5, 1), (6, 2), (7, 2), (8, 2), (9, 3), (10, 3)):  # the bell, leaning with the swing
        c = cx + int(round(sw * (y - 4) / 3))
        for x in range(c - w, c + w + 1): dot(x, y, '3')
    c = cx + sw * 2
    dot(c - 1, 6, '1')                                             # a glint
    dot(c + sw, 11, '2')                                           # the clapper
    return ["".join(r) for r in rows]

SLIME = ["................"] * 12 + [
    ".....222222.....",
    "...2211111122...",
    "..211311113112..",
    ".21133111133112.",
    ".21111111111112.",
    "2111111111111112",
    "2111112222111112",
    "2111111111111112",
    ".21111111111112.",
    "..222222222222..",
    "................",
    "................"]
SLIME_SQ = ["................"] * 14 + [
    "...2222222222...",
    ".22111111111122.",
    "2113311111133112",
    "2111111111111112",
    "2111112222111112",
    "2111111111111112",
    ".22222222222222.",
    "................",
    "................",
    "................"]
BAT = ["................"] * 6 + [
    "3..............3",
    "33............33",
    "333...1..1...333",
    "3333..1111..3333",
    "33333111111333.3",
    ".333311211113333",
    "..33.111111..33.",
    "......1..1......",
    "................"] + ["................"] * 9
BAT2 = ["................"] * 6 + [
    "................",
    "......1..1......",
    "......1111......",
    ".....111111.....",
    "...33112111133..",
    "..3333111111333.",
    ".333.3.1..1.3333",
    "33...3......3..3",
    "3..............."] + ["................"] * 9
MOLE = ["................"] * 12 + [
    "......1111......",
    "....11111111....",
    "...1111111111...",
    "..111131111111..",
    ".1111111111111.2",
    "21111111111111.2",
    "21111111111111..",
    ".111111111111...",
    "..33.33..33.33..",
    "................",
    "................",
    "................"]

def dig_deep():
    import gen_examples as g
    random.seed(7)
    tl = tiles()
    m, hs = world()
    # the backdrop: the title / level card picture and the HUD strip (its top 8 lines)
    img = Image.new('P', (320, 256), 0)
    px = [0] * (320 * 256)
    for y in range(8):
        for x in range(320): px[y * 320 + x] = 5
    sx0 = 0
    for ty in range(9, 16):
        for tx in range(20):
            t = m[(ty + 6) * W + tx + sx0]
            for yy in range(16):
                for xx in range(16):
                    v = tl[t]['px'][yy * 16 + xx]
                    py = ty * 16 + yy
                    if py < 256 and v: px[py * 320 + tx * 16 + xx] = v
    img.putdata(px)
    sprites = [("Miner", "dd_miner", [0xf0c090, 0x3050c0, 0xffd030]),
               ("Slime", "dd_slime", [0x40d040, 0x1a5a1a, 0xd0ffd0]),
               ("Bat", "dd_bat", [0xd04040, 0x2a1030, 0x8a5aa0]),
               ("Mole", "dd_mole", [0x6a4a3a, 0xffffff, 0xff9080]),
               ("Bell", "dd_bell", [0xf0c090, 0x3050c0, 0xffd030]),     # the miner's colours: it shares his sprite pair
               ("Rock", "dd_rock", [0xd04040, 0x2a1030, 0x8a5aa0])]     # the bat's colours: it shares its pair
    art.A['dd_miner'] = miner_rows()
    art.A['dd_slime'] = SLIME
    art.A['dd_bat'] = BAT
    art.A['dd_mole'] = MOLE
    art.A['dd_bell'] = bell_rows()
    art.A['dd_rock'] = ROCK
    start_y = hs[8] * 16 - 20
    actors = [g.actor("Miner", 0, 6, 2, 8 * 16, start_y),
              g.actor("Slime 1", 1, 7, 1, 52 * 16, hs[52] * 16 - 24),
              g.actor("Slime 2", 1, 7, 1, 84 * 16, hs[84] * 16 - 24, left=True),
              g.actor("Bat 1", 2, 1, 1, 40 * 16, 30 * 16),
              g.actor("Mole", 3, 2, 1, 60 * 16, 38 * 16),
              g.actor("Bell", 4, 5, 1, 30 * 16, hs[30] * 16 - 24),
              g.actor("Rock", 5, 5, 1, 12 * 16, hs[12] * 16 - 24)]
    # a tile world has 7 hardware sprites (the scroll takes sprite 8's time): miner, 2 slimes,
    # a bat, the mole, the bell and the rock
    actors[6]['carry'] = True             # pick it up with fire, fire again to throw it
    for a in actors[1:3]:
        a['anim_sprite'] = -1
    R = g.R
    # the sword (Auto): striking a baddie scores, thwacks and sends it back where it came from.
    # These come first, so a baddie struck as it touches the miner is gone before the touch counts.
    # A slime is squashed first: it is safe (can't hurt or be struck) while it plays its Die
    # animation, and goes home when that ends
    strike = []
    for b in range(1, 5):
        if b < 3:
            strike += [R(when=10, b=b, act=0, value=25), R(when=10, b=b, act=2, value=5), R(when=10, b=b, act=16, target=b),
                       R(when=10, b=b, act=26, target=b, value=1)]
        else:
            strike += [R(when=10, b=b, act=0, value=25), R(when=10, b=b, act=2, value=5), R(when=10, b=b, act=4, target=b)]
    for b in range(1, 3):
        strike += [R(when=16, a=b, n=1, act=4, target=b)]
    # the rock: thrown at a baddie it scores, thwacks and sends it home; picking it up clinks
    for b in range(1, 5):
        strike += [R(when=11, a=6, b=b, act=0, value=50), R(when=11, a=6, b=b, act=2, value=5), R(when=11, a=6, b=b, act=4, target=b)]
    strike += [R(when=12, a=6, act=2, value=4)]
    rules = strike + [R(when=0, a=0, b=1, act=1), R(when=0, a=0, b=1, act=4, target=0), R(when=0, a=0, b=1, act=16, target=0), R(when=0, a=0, b=1, act=2, value=6),
             R(when=0, a=0, b=2, act=1), R(when=0, a=0, b=2, act=4, target=0), R(when=0, a=0, b=2, act=16, target=0), R(when=0, a=0, b=2, act=2, value=6),
             R(when=0, a=0, b=3, act=1), R(when=0, a=0, b=3, act=4, target=0), R(when=0, a=0, b=3, act=16, target=0), R(when=0, a=0, b=3, act=2, value=6),
             R(when=0, a=0, b=4, act=1), R(when=0, a=0, b=4, act=4, target=0), R(when=0, a=0, b=4, act=16, target=0), R(when=0, a=0, b=4, act=2, value=6),
             R(when=6, a=0, act=2, value=3),
             R(when=4, act=9),
             # the wind gusts through the caves now and again
             R(when=2, n=11, act=2, value=1),
             R(when=2, n=26, act=2, value=1),
             # the bell on its post chimes - only while it is on the screen
             R(when=9, a=5, n=3, act=2, value=2),
             R(when=9, a=5, n=5, act=2, value=7)]
    sfx = g.sfx_list({0: dict(name="Treasure", wave=2, pitch=84, sweep=12, len=8, atk=0, dec=5, sus=0, rel=5),
                      3: dict(name="Dig", wave=3, pitch=26, sweep=-2, len=3, atk=0, dec=3, sus=0, rel=2),
                      4: dict(name="Clink", wave=2, pitch=70, sweep=-6, len=3, atk=0, dec=3, sus=0, rel=3),
                      6: dict(name="Ouch", wave=0, pitch=46, sweep=-1, len=26, atk=1, dec=8, sus=9, rel=7),
                      # sound 1 / 5 share Paula channel 2, 2 / 6 channel 3, 3 / 7 channel 4 (no music here):
                      # the wind has channel 2 to itself, the chimes ring on 3 and 4
                      1: dict(name="Wind", wave=3, pitch=230, sweep=0, len=70, atk=11, dec=12, sus=10, rel=10, filt=4, fspeed=2, fdepth=11),
                      2: dict(name="Chime", wave=0, pitch=100, sweep=0, len=2, atk=0, dec=10, sus=0, rel=10),
                      7: dict(name="Chime 2", wave=0, pitch=133, sweep=0, len=2, atk=0, dec=10, sus=0, rel=10),
                      5: dict(name="Thwack", wave=3, pitch=40, sweep=-3, len=3, atk=0, dec=4, sus=0, rel=3)})
    p = g.make_project("Dig Deep", PAL, img, sprites, actors, rules, [0x1850b0, 0x60a8ff, 0xc8e8ff, 120],
                       hud_col=1, msg_col=11, sfx=sfx, win="ALL THE TREASURE! - PRESS FIRE", over="BURIED! - PRESS FIRE", songs=[])
    p.update(goal_on=True, goal=12, goal_label="GOLD", title_on=True, title1="DIG DEEP", title2="PRESS FIRE TO START")
    p.update(tiles_on=True, tile_size=16, tiles=tl, map_w=W, map_h=H, map=m, tile_dig=True)
    # space opens the tool menu: the pickaxe digs, the hammer builds with the tile carried,
    # ladder parts to climb out of holes and torches to light the way
    p['tools'] = [dict(name="PICK", act=0, tile=0), dict(name="SWORD", act=3, tile=0, reach=20, auto=True), dict(name="HAMMER", act=1, tile=0),
                  dict(name="LADDER", act=2, tile=LADDER), dict(name="TORCH", act=2, tile=TORCH)]
    # ADAM Pro: a stone HUD panel, bold lettering with shadows: score, gold, the tile carried, lives
    g.dress_ui(p, "Stone", 1, 2, [(1, "SCORE ", 1, 0, 0xffffff, 0x161626, 5), (3, "", 17, 0, 0xffcc22, 0x161626, 0),
                                  (4, "", 29, 0, 0x40e8ff, 0x161626, 0), (2, "LIVES ", 1, 1, 0xff8820, 0x161626, 1),
                                  (6, "", 17, 1, 0xd8d8e0, 0x161626, 0), (0, "SPACE:TOOLS", 27, 1, 0x9090a0, 0x161626, 0)])
    # animations: walk, jump and fall, and the pickaxe on the With Fire joystick
    T = g.tf_shift
    walk = [("Miner step", miner_rows(1)), ("Miner pass", miner_rows(2)), ("Miner step 2", miner_rows(3)), ("Miner pass 2", miner_rows(2, bob=1))]
    spec = {0: dict(flip=True, anims={
        0: ([0, ("Miner breathe", miner_rows(0, bob=1))], 20, 2),
        1: (walk, 5, 0),
        2: ([("Miner leap", miner_rows(1)), ("Miner leap 2", miner_rows(3))], 6, 1),
        3: ([("Miner drop", miner_rows(2)), ("Miner drop 2", miner_rows(2, bob=1))], 6, 0),
        15: ([("Miner pick up", miner_rows(0, "up")), ("Miner pick fwd", miner_rows(0, "fwd")), ("Miner pick fwd 2", miner_rows(0, "fwd", 1))], 5, 0),
        17: ([("Miner pick up", None), ("Miner pick down", miner_rows(0, "down")), ("Miner pick down 2", miner_rows(0, "down", 1))], 5, 0),
        13: ([("Miner pick up", None), ("Miner pick high", miner_rows(0, "high")), ("Miner pick high 2", miner_rows(0, "high", 1))], 5, 0),
        # Fire on its own: the sword's swing (the pickaxe uses Fire + the way he faces)
        12: ([("Miner sword up", miner_rows(0, "sword up")), ("Miner sword fwd", miner_rows(0, "sword fwd")), ("Miner sword low", miner_rows(0, "sword low"))], 5, 1)}),
        1: dict(anims={0: ([1, ("Slime wobble", T(SLIME, dy=1)), ("Slime squash", SLIME_SQ)], 10, 2),
                       2: ([1, ("Slime stretch", T(SLIME, dy=-1)), ("Slime stretch 2", T(SLIME, dy=-2))], 4, 1),
                       # Die (the sword): squashed flat into a puddle
                       22: ([("Slime squash", None), ("Slime splat", T(SLIME_SQ, dy=2)), ("Slime puddle", T(SLIME_SQ, dy=4))], 6, 1)}),
        2: dict(anims={0: ([1, ("Slime wobble", None), ("Slime squash", None)], 10, 2),
                       2: ([1, ("Slime stretch", None), ("Slime stretch 2", None)], 4, 1),
                       22: ([("Slime squash", None), ("Slime splat", None), ("Slime puddle", None)], 6, 1)}),
        3: dict(anims={0: ([2, ("Bat flap", BAT2), ("Bat glide", T(BAT, dy=1)), ("Bat flap 2", T(BAT2, dy=1))], 5, 0)}),
        4: dict(flip=True, anims={0: ([3, ("Mole dig", T(MOLE, dx=1)), ("Mole dig 2", T(MOLE, dy=1))], 8, 0)}),
        5: dict(anims={0: ([("Bell swing", bell_rows(-1)), 4, ("Bell swing 2", bell_rows(1))], 10, 2)})}
    for a in actors[1:3]:
        a['anim_sprite'] = 4
    g.animate(p, "dd", spec)
    # the slimes' crouch frame (hoppers): the squashed slime
    sq = [i for i, s in enumerate(p['sprites']) if s['name'] == "Slime squash"][0]
    for a in p['actors'][1:3]:
        a['anim_sprite'] = sq
    # ADAM Pro loading screen: the backdrop with a stone bar along the bottom
    from adf_reference import ls_new
    # and the cast turns up in the sky as it loads (pictures at a percentage)
    p['loadscr'] = ls_new(style="Stone", bar_x=48, bar_y=224, bar_w=224, bar_h=16,
                          pics=[dict(spr=0, x=64, y=96, pct=20), dict(spr=2, x=140, y=48, pct=45),
                                dict(spr=1, x=216, y=100, pct=70), dict(spr=3, x=272, y=96, pct=90)])
    return p

def map_png(p, fn):
    pal = p['pal']
    im = Image.new('RGB', (W * 16, H * 16))
    pxs = im.load()
    sky = (0x60, 0xa8, 0xff)
    for ty in range(H):
        for tx in range(W):
            t = p['map'][ty * W + tx]
            tp = p['tiles'][t]['px']
            for yy in range(16):
                for xx in range(16):
                    v = tp[yy * 16 + xx]
                    if v == 0: c = sky
                    else:
                        cc = pal[v]; c = ((cc >> 16) & 255, (cc >> 8) & 255, cc & 255)
                    pxs[tx * 16 + xx, ty * 16 + yy] = c
    im.save(fn)
