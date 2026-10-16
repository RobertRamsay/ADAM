# Jade Serpent - the vertical shoot 'em up on a scrolling map (ADAM Pro example, data version 10).
# The level is a map of 16 x 16 tiles, 12 across (the play area in the middle of the screen,
# so the A500 has less to draw) and ROWS down, that scrolls past once from
# the bottom to the top: jungle and a river, overgrown ruins, a step pyramid, a plaza of carved
# glyphs, a cenote, and the serpent temple where the boss waits. Spawners along the map send
# the waves in; enemies fire by themselves (Actors page), copies make the pools.
# The map is painted as one tall picture, then cut into tiles (the same tile is only stored
# once). Everything is drawn on the 16-pixel grid and every texture repeats every 32 or 64
# pixels, so the picture needs few tiles; stamps (metatiles) of its buildings go in the
# project too, for building more of it on the Tiles page.
# Made by gen_examples.py: python gen_examples.py jade_serpent
import math, random
from PIL import Image
import gen_examples as g
import ex_shmup as sh

TAU = 2 * math.pi
ROWS = 200
COLS = 12             # the play area: 12 tiles (192 pixels) in the middle of the screen
MW = COLS * 16
CX = MW // 2
MH = ROWS * 16
TILE_LIMIT = 500

# 0 deepest shade, 1 cream, 2-5 jungle greens, 6-9 stone, 10-11 water / jade, 12 terracotta,
# 13-14 gold, 15 crimson
PAL = [0x0a0c08, 0xf6f0d6, 0x16261a, 0x2a4e26, 0x4c8434, 0x9cc84e, 0x3a3428, 0x6a6250,
       0xa69a76, 0xdcd0a0, 0x15485a, 0x2aa294, 0xa8421e, 0xdc9e28, 0xffec7c, 0xb02838]
LEAF = [2, 3, 4, 5]


def hsh(x, y, s=0):
    n = (x * 374761393 + y * 668265263 + s * 982451653 + 1013904223) & 0xffffffff
    n = ((n ^ (n >> 13)) * 1274126177) & 0xffffffff
    return ((n ^ (n >> 16)) & 0xffff) / 65536.0


def vnoise(x, y, px, py, cell, s):
    """smooth value noise, periodic px x py (multiples of cell), 0..1"""
    gx, gy = px // cell, py // cell
    fx, fy = x / cell, y / cell
    x0, y0 = int(math.floor(fx)), int(math.floor(fy))
    tx, ty = fx - x0, fy - y0
    tx = tx * tx * (3 - 2 * tx); ty = ty * ty * (3 - 2 * ty)
    def v(i, j): return hsh(i % gx, j % gy, s)
    a = v(x0, y0) + (v(x0 + 1, y0) - v(x0, y0)) * tx
    b = v(x0, y0 + 1) + (v(x0 + 1, y0 + 1) - v(x0, y0 + 1)) * tx
    return a + (b - a) * ty


class Map:
    def __init__(self):
        self.p = bytearray(MW * MH)
    def get(self, x, y):
        if 0 <= x < MW and 0 <= y < MH: return self.p[y * MW + x]
        return 0
    def set(self, x, y, c):
        if 0 <= x < MW and 0 <= y < MH: self.p[y * MW + x] = c


# ------------------------------------------------------------------ the jungle canopy
CW = 64           # one canopy block; two kinds of block (A, B) that join up any way round


def canopy_blobs(seed):
    """leaf clumps for blocks A and B: the ones that cross a block's edge are the same in both,
    so blocks can be mixed freely; the ones inside differ"""
    rnd = random.Random(seed)
    edge, inner = [], [[], []]
    # Poisson-ish: try spots, keep those not too close to the others
    def place(lst, n, x0, x1, y0, y1, others):
        tries = 0
        while len(lst) < n and tries < 4000:
            tries += 1
            x, y = rnd.uniform(x0, x1), rnd.uniform(y0, y1)
            r = rnd.uniform(6.5, 11.0)
            ok = True
            for (bx, by, br, *_) in others + lst:
                dx = (x - bx + CW / 2) % CW - CW / 2
                dy = (y - by + CW / 2) % CW - CW / 2
                if dx * dx + dy * dy < (0.62 * (r + br)) ** 2: ok = False; break
            if ok: lst.append((x, y, r, rnd.uniform(0.75, 1.0), rnd.uniform(0, TAU), rnd.random()))
    for _ in range(3):                                    # along the left and the top edge
        place(edge, len(edge) + 3, -8, 8, 0, CW, edge)
        place(edge, len(edge) + 3, 0, CW, -8, 8, edge)
    for k in range(2):
        place(inner[k], 22, 9, CW - 9, 9, CW - 9, edge)
    return [edge + inner[0], edge + inner[1]]


def canopy_block(blobs, seed):
    """64 x 64 shades: each pixel lit by the top clump over it (a dome with lobed leaves),
    clumps cast a soft shadow down and right; -1 = a gap, -2 / -3 = a blossom"""
    L = (-0.55, -0.62, 0.56)
    top = [None] * (CW * CW)
    hgt = [0.0] * (CW * CW)
    for y in range(CW):
        for x in range(CW):
            best = 0.0; who = None
            for b in blobs:
                bx, by, r, k, ph, kind = b
                dx = (x - bx + CW / 2) % CW - CW / 2
                dy = (y - by + CW / 2) % CW - CW / 2
                d2 = (dx * dx + dy * dy) / (r * r)
                if d2 >= 1.35: continue
                lob = 1 + 0.13 * math.sin(math.atan2(dy, dx) * 7 + ph)
                d2 /= lob * lob
                if d2 >= 1: continue
                h = k * (1 - d2) ** 0.5 + 0.12 * k
                if h > best: best, who = h, (b, dx, dy, d2)
            top[y * CW + x] = who
            hgt[y * CW + x] = best
    out = [0.0] * (CW * CW)
    for y in range(CW):
        for x in range(CW):
            w = top[y * CW + x]
            if w is None:
                out[y * CW + x] = -1
                continue
            (bx, by, r, k, ph, kind), dx, dy, d2 = w
            nz = math.sqrt(max(0.0, 1 - d2))
            nx, ny = dx / r, dy / r
            lam = max(0.0, nx * L[0] + ny * L[1] + nz * L[2])
            # leaves: small lobes across the clump
            leaf = math.sin((dx * 0.9 + dy * 0.45) * 1.7 + ph) * math.sin((dy * 0.9 - dx * 0.4) * 1.6 + ph * 2)
            v = 0.08 + 0.95 * lam + 0.13 * leaf - 0.25 * max(0.0, d2 - 0.75) * 4
            # shadow from a higher clump up and to the left
            hs = hgt[((y - 3) % CW) * CW + (x - 3) % CW]
            if hs > hgt[y * CW + x] + 0.25: v -= 0.32
            out[y * CW + x] = max(0.0, min(1.0, v))
    rnd = random.Random(seed)
    for _ in range(2):                                     # blossoms
        fx, fy = rnd.randrange(8, CW - 8), rnd.randrange(8, CW - 8)
        if out[fy * CW + fx] > 0.5:
            for dx, dy in ((0, 0), (1, 0), (0, 1), (1, 1), (-1, 0), (0, -1)):
                out[(fy + dy) * CW + fx + dx] = -2
            out[fy * CW + fx] = -3
    return out


CAN = None


def canopy_kind(x, y):
    """which block (A 0 / B 1) the canopy uses at (x, y): mixed by a hash of the block"""
    return 1 if hsh(x // CW, y // CW, 501) < 0.5 else 0


def canopy(x, y):
    v = CAN[canopy_kind(x, y)][(y % CW) * CW + (x % CW)]
    if v == -1: return g.dmix(0, 2, 0.4, x, y)
    if v == -2: return 15
    if v == -3: return 14
    return g.ramp(LEAF, v, x, y)


# ------------------------------------------------------------------ other textures
def water(x, y, light=0.0):
    """deep jade water, periodic 32: slow ripples and a few glints"""
    r = 0.5 + 0.5 * math.sin(TAU * (x / 32 + 2 * y / 32)) * math.sin(TAU * (2 * x / 32 - y / 32))
    t = 0.16 + 0.3 * r + light
    if hsh(x % 32, y % 32, 9) < 0.014 and r > 0.55: return 1
    return g.ramp([10, 11, 9], min(1.0, t * 0.9), x, y)


def stone_block(x, y, bw=16, bh=16, base=0.5, moss=0.0, seed=3, vx=2, vy=2):
    """bevelled stone blocks lit from the top left; repeats every (bw x vx, bh x vy) pixels,
    moss every 64"""
    lx, ly = x % bw, y % bh
    bxi, byi = (x // bw) % vx, (y // bh) % vy
    if lx == bw - 1 or ly == bh - 1: return 6                         # mortar
    v = base + 0.14 * (hsh(bxi, byi, seed) - 0.5) + 0.07 * (hsh(x % (bw * vx), y % (bh * vy), seed + 1) - 0.5)
    if lx == 0 or ly == 0: v += 0.3                                   # lit edges
    elif lx == bw - 2 or ly == bh - 2: v -= 0.26                      # shaded edges
    c = g.ramp([6, 7, 8, 9], v, x, y)
    if moss > 0:
        m = vnoise(x % 64, y % 64, 64, 64, 32, seed + 7) * 0.62 + 0.38 * vnoise(x % 64, y % 64, 64, 64, 8, seed + 8)
        if m < moss:
            k = (moss - m) / max(0.01, moss)
            return g.ramp([3, 4, 5], min(1.0, 0.25 + k * 1.1) * (0.8 + 0.2 * hsh(x % 64, y % 64, 2)), x, y)
        if m < moss + 0.03: return g.dmix(c, 3, 0.5, x, y)
    return c


def flag(x, y, moss=0.16):
    return stone_block(x, y, 16, 16, 0.55, moss, 5)


# ------------------------------------------------------------------ painting helpers
def fill(M, x0, y0, x1, y1, fn):
    for y in range(max(0, y0), min(MH, y1)):
        for x in range(max(0, x0), min(MW, x1)):
            M.p[y * MW + x] = fn(x, y)


def leaf_edge(M, x0, y0, x1, y1, sides):
    """the canopy round a clearing x0..x1, y0..y1 (sides: which of 'nsew' border jungle):
    a leafy edge that grows over it a little and a shadow on it (left and top: the light
    comes from there, so the shadow falls inside the top and left edges)"""
    for y in range(max(0, y0), min(MH, y1)):
        for x in range(max(0, x0), min(MW, x1)):
            d = 99; dirn = ''
            if 'w' in sides and x - x0 < d: d, dirn = x - x0, 'w'
            if 'e' in sides and x1 - 1 - x < d: d, dirn = x1 - 1 - x, 'e'
            if 'n' in sides and y - y0 < d: d, dirn = y - y0, 'n'
            if 's' in sides and y1 - 1 - y < d: d, dirn = y1 - 1 - y, 's'
            if d > 8: continue
            if dirn in 'ew': n = vnoise(x % 64, y % 64, 64, 64, 8, 31)
            else: n = vnoise(x % 64, y % 64, 64, 64, 8, 37)
            reach = 1 + 4 * n
            if d < reach: M.p[y * MW + x] = canopy(x, y)
            elif dirn in 'nw' and d < reach + 4:
                c = M.p[y * MW + x]
                M.p[y * MW + x] = g.dmix(c, 0, 0.5, x, y) if c > 1 else c


def vine(M, x, y0, length, seed, sway=1.5):
    """a hanging vine: a dark stem with leaves, swaying a little"""
    for k in range(length):
        y = y0 + k
        xx = int(round(x + sway * math.sin(k / 6.0 + seed)))
        M.set(xx, y, 3)
        if k % 4 == 1:
            side = 1 if (k // 4) % 2 else -1
            M.set(xx + side, y, 4); M.set(xx + 2 * side, y, 5 if (k + seed) % 3 else 4)
            M.set(xx + side, y + 1, 3)
    M.set(int(round(x + sway * math.sin((length - 1) / 6.0 + seed))), y0 + length, 5)


def shade_below(M, x0, x1, y, depth=4, k=0.6):
    """a soft shadow under something that stands up from the ground (down and right)"""
    for d in range(depth):
        for x in range(x0 + d + 1, x1 + d + 1):
            c = M.get(x, y + d)
            M.set(x, y + d, g.dmix(c, 0, k * (1 - d / depth), x, y + d) if c > 1 else c)


def shade_right(M, x, y0, y1, depth=4, k=0.6):
    for d in range(depth):
        for y in range(y0 + d + 1, y1 + d + 1):
            c = M.get(x + d, y)
            M.set(x + d, y, g.dmix(c, 0, k * (1 - d / depth), x + d, y) if c > 1 else c)


# ------------------------------------------------------------------ the regions (map y from the top)
Y_RIVER = 2656        # .. MH: jungle river (the start)
Y_RUINS = 2144        # .. Y_RIVER: overgrown ruins, the causeway
Y_PYR = 1504          # .. Y_RUINS: the step pyramid
Y_PLAZA = 1120        # .. Y_PYR: the glyph plaza
Y_CEN = 576           # .. Y_PLAZA: the cenote
# 0 .. Y_CEN: the serpent temple courtyard (the last screen: the boss)

PYR_CX, PYR_CY, PYR_R = CX, 1792, 80         # the pyramid: a square 160 across
CEN_CX, CEN_CY, CEN_R = CX, 848, 64         # the cenote
SUN_CX, SUN_CY, SUN_R = CX, 144, 48         # the sun stone under the boss


def paint_map():
    global CAN
    bl = canopy_blobs(11)
    CAN = [canopy_block(bl[0], 12), canopy_block(bl[1], 13)]
    M = Map()
    fill(M, 0, 0, MW, MH, canopy)
    paint_river(M)
    paint_ruins(M)
    paint_pyramid(M)
    paint_plaza(M)
    paint_cenote(M)
    paint_courtyard(M)
    return M


def river_cx(y): return CX + 26 * math.sin((y - Y_RIVER) / 140.0 + 0.6) + 6 * math.sin((y - Y_RIVER) / 57.0)


def paint_river(M):
    def half(y): return 20 + 3 * math.sin(y / 47.0)
    top = Y_RIVER + 48
    for y in range(top - 40, MH):
        cx = river_cx(y); hw = half(y)
        if y < top:                                          # it ends in a pool at the causeway's foot
            k = (top - y) / 40.0
            hw = hw * math.sqrt(max(0.0, 1 - k * k)) + 0.01
            cx = cx + (CX - cx) * k
        for x in range(MW):
            d = abs(x - cx)
            n = vnoise(x % 64, y % 64, 64, 64, 8, 41)
            if d > hw + 4 + 3 * n: continue
            if d <= hw - 2:
                M.set(x, y, water(x, y, 0.12 * (1 - d / hw)))
            elif d <= hw:
                M.set(x, y, 9 if (x + y) % 3 == 0 else 11)                          # foam at the bank
            else:
                b = (d - hw) / (4 + 3 * n)                                          # muddy, mossy bank
                c = g.ramp([7, 6, 3], b, x, y)
                if n > 0.6 and b > 0.4: c = 4
                M.set(x, y, c)
    # the canopy reaches over the banks
    for y in range(top - 40, MH):
        cx = river_cx(y); hw = half(y)
        if y < top: continue
        for x in range(MW):
            d = abs(x - cx)
            n = vnoise(x % 64, y % 64, 64, 64, 8, 41)
            edge = hw + 4 + 3 * n
            if edge - 2 < d <= edge + 3 and vnoise(x % 64, y % 64, 64, 64, 4, 43) < 0.45:
                M.set(x, y, canopy(x, y))
    # stepping stones across the river
    for k, yy in enumerate(range(top + 140, MH - 40, 240)):
        cx = river_cx(yy)
        for j in range(-2, 3):
            sx, sy = int(cx + j * 9), yy + 4 * ((j + k) % 2)
            for dy in range(-4, 5):
                for dx in range(-5, 6):
                    if dx * dx / 28 + dy * dy / 18 <= 1:
                        M.set(sx + dx, sy + dy, g.ramp([6, 7, 8, 9], 0.45 - 0.07 * (dx + dy), sx + dx, sy + dy))
                if 0 < dy < 4: M.set(sx + 5, sy + dy, 10)


def causeway(M, y0, y1, x0=CX - 32, x1=CX + 32):
    fill(M, x0, y0, x1, y1, lambda x, y: flag(x, y, 0.2))
    for y in range(y0, y1):                                    # kerb stones
        M.set(x0, y, 9); M.set(x0 + 1, y, 8)
        M.set(x1 - 2, y, 7); M.set(x1 - 1, y, 6)
    leaf_edge(M, x0 - 16, y0, x0, y1, 'w')
    leaf_edge(M, x1, y0, x1 + 16, y1, 'e')
    shade_right(M, x1, y0, y1, 3, 0.7)


def serpent_head(M, x0, y0, facing=1):
    """a feathered-serpent head carved in stone, 32 x 32, its jaws towards the road"""
    for y in range(32):
        for x in range(32):
            lx = x if facing > 0 else 31 - x
            cx, cy = lx - 12, y - 16
            body = (cx / 13.0) ** 2 + (cy / 11.0) ** 2 <= 1
            snout = 10 <= lx <= 29 and abs(cy) <= 7 - max(0, lx - 22)
            plume = lx < 9 and abs(cy) <= 14 and ((y + lx) % 5) < 3
            if not (body or snout or plume): continue
            X, Y = x0 + x, y0 + y
            if plume: c = g.ramp([3, 4, 11], 0.3 + 0.6 * hsh(lx, y, 12), X, Y)
            else:
                v = 0.55 - 0.035 * cy - 0.02 * (lx - 14) * (1 if facing > 0 else -1)
                c = g.ramp([6, 7, 8, 9], v, X, Y)
                if snout and abs(cy) <= 1 and lx > 18: c = 0                           # the mouth
                if snout and lx in (26, 27) and cy in (-6, 6, -5, 5): c = 9              # fangs
                if lx in (15, 16) and cy in (-5, -4): c = 14                             # the eye
                if (lx + y) % 7 == 0 and body and not snout: c = 6                       # scales
            M.set(X, Y, c)


PLATFORMS = [(0, 2208, 32, 48), (MW - 32, 2400, 32, 64)]


def paint_ruins(M):
    causeway(M, Y_RUINS, Y_RIVER + 64)
    for y in range(Y_RUINS + 64, Y_RIVER - 32, 128):                               # serpent heads by the road
        serpent_head(M, CX - 64, y, 1)
        serpent_head(M, CX + 32, y, -1)
    for (x0, y0, w, h) in PLATFORMS:                                                 # broken platforms, overgrown
        fill(M, x0, y0, x0 + w, y0 + h, lambda x, y: stone_block(x, y, 16, 16, 0.5, 0.36, 21))
        for x in range(x0, x0 + w):
            M.set(x, y0, 9)
        leaf_edge(M, x0, y0, x0 + w, y0 + h, 'nsew')
        shade_below(M, x0, x0 + w, y0 + h, 4, 0.6)
        for vx in range(x0 + 6, x0 + w - 4, 16):
            vine(M, vx, y0 + 1, 14 + int(hsh(vx, y0, 3) * 12), vx // 16)


def paint_pyramid(M):
    cx, cy, R = PYR_CX, PYR_CY, PYR_R
    top, bot = cy - R, cy + R
    fill(M, 0, Y_PYR, MW, Y_RUINS, lambda x, y: flag(x, y, 0.24))                 # the plaza round it
    # the steps: rings 16 wide, each one higher than the one round it. A step's front (riser)
    # faces out: lit on the north and west, in shade on the south and east
    for y in range(top, bot):
        for x in range(cx - R, cx + R):
            dx, dy = x - cx, y - cy
            ax = dx if dx >= 0 else -dx - 1                                          # 0 .. R-1 from the middle
            ay = dy if dy >= 0 else -dy - 1
            d = max(ax, ay)
            if d < 32: continue                                                      # the shrine
            c = stone_block(x, y, 16, 8, 0.56, 0, 40, 2, 2)
            e = (R - 1 - d) % 16                                                     # 0 = this ring's outer edge
            if e < 4:
                if ay >= ax:
                    c = (9 if e < 2 else 8) if dy < 0 else (6 if e < 2 else 7)
                else:
                    c = (8 if e < 2 else 9) if dx < 0 else (6 if e < 2 else 7)
                if ax == ay: c = 6 if (dx > 0 or dy > 0) else 9                       # the corner's edge
            M.set(x, y, c)
    # moss and vines down the north steps, the same on every step (so the same tiles)
    for k in range(6):
        ry = top + 16 * k
        for vx in (cx - 72 + 8 * ((k * 3) % 4), cx + 48 + 8 * (k % 3)):
            vine(M, vx + 5, ry + 4, 18, k)
    # its shadow on the plaza
    shade_below(M, cx - R, cx + R, bot, 6, 0.7)
    shade_right(M, cx + R, top, bot, 6, 0.7)
    # the stairs up the south face, between feathered-serpent balustrades
    for y in range(cy + 32, bot):
        for x in range(cx - 32, cx + 32):
            lx = x - (cx - 32)
            if lx < 12 or lx >= 52:
                side = lx < 12
                u = lx if side else 63 - lx
                t = 0.45 + (0.2 if side else -0.15) + 0.25 * math.sin(TAU * (y + 2 * u) / 16)
                c = g.ramp([3, 4, 11, 5], t, x, y)
                if (y // 4 + u // 3) % 3 == 0: c = 3
                if u == 0: c = 6 if not side else 9
            else:
                s = y % 8
                c = 9 if s == 0 else (8 if s < 5 else (7 if s < 7 else 6))
            M.set(x, y, c)
    serpent_head(M, cx - 64, bot - 32, 1)
    serpent_head(M, cx + 32, bot - 32, -1)
    # the shrine on top: red walls, a gold frieze, a dark doorway onto the stairs
    s0x, s0y = cx - 32, cy - 32
    for y in range(64):
        for x in range(64):
            X, Y = s0x + x, s0y + y
            edge = min(x, y, 63 - x, 63 - y)
            if edge < 3: c = 9 if (x < 3 or y < 3) else 6
            elif edge < 8: c = 13 if ((x + y) // 3) % 2 else 12
            elif edge < 10: c = 14 if (x < 10 or y < 10) else 13
            else:
                t = 0.35 + 0.3 * (1 - (x + y) / 128.0)
                c = g.ramp([15, 12, 13], t, X, Y)
                dd = (x - 31.5) ** 2 + (y - 31.5) ** 2
                if dd < 64: c = 14 if dd < 20 else 13                                 # the gold idol
            if 24 <= x < 40 and y >= 52: c = 0 if y > 54 else 6                        # the doorway
            M.set(X, Y, c)


GLYPHS = [
    ["..1111..", ".1....1.", "1.1..1.1", "1......1", "1.1111.1", ".1....1.", "..1111..", "........"],   # a face
    ["11111111", "1......1", "1.1111.1", "1.1..1.1", "1.1.11.1", "1.1....1", "1.111111", "........"],   # a fret
    ["...11...", "..1..1..", ".1.11.1.", "1.1..1.1", ".1.11.1.", "..1..1..", "...11...", "........"],   # a jewel
    ["1.1.1.1.", ".1.1.1.1", "11111111", "1......1", "1.1111.1", "1......1", "11111111", "........"],   # a temple
]


def glyph_stone(M, x0, y0, gi):
    """a 32 x 32 carved stone with a glyph inlaid in gold"""
    G = GLYPHS[gi]
    for y in range(32):
        for x in range(32):
            X, Y = x0 + x, y0 + y
            if x in (0, 31) or y in (0, 31): c = 6
            elif x == 1 or y == 1: c = 9
            elif x == 30 or y == 30: c = 7
            else:
                c = g.ramp([7, 8], 0.45 + 0.1 * hsh(x, y, gi), X, Y)
                gx, gy = (x - 4) // 3, (y - 4) // 3
                if 0 <= gx < 8 and 0 <= gy < 8 and G[gy][gx] == '1':
                    c = 13 if (x - 4) % 3 != 2 and (y - 4) % 3 != 2 else 6
            M.set(X, Y, c)


def brazier(M, x0, y0):
    """a stone fire bowl, 32 x 32, seen from above"""
    for y in range(32):
        for x in range(32):
            d = math.hypot(x - 15.5, y - 15.5)
            if d > 14.5: continue
            X, Y = x0 + x, y0 + y
            if d > 11.5: c = g.ramp([6, 7, 9], 0.55 - (x + y - 31) / 46.0, X, Y)
            elif d > 10: c = 6
            else:
                t = 1 - d / 10 + 0.18 * (hsh(x, y, 77) - 0.5)
                c = g.ramp([12, 15, 13, 14, 1], t, X, Y)
            M.set(X, Y, c)
    shade_below(M, x0 + 6, x0 + 26, y0 + 30, 3, 0.6)


def frieze(x, y, left):
    """the walls: a step-fret frieze (xicalcoliuhqui) in red and stone, repeating every 32"""
    lx = x % 32 if left else 31 - x % 32
    ly = y % 32
    if lx >= 28: return 6 if lx < 30 else g.dmix(0, 6, 0.5, x, y)
    if lx < 2: return 9
    if lx >= 25: return 7
    u, v = (lx - 2) // 3, ly // 4
    pattern = ["11111111", "1......1", "1.1111.1", "1.1..1.1", "1.1..111", "1.1.....", "1.111111", "1......."]
    return 15 if pattern[v % 8][u % 8] == '1' else g.ramp([7, 8], 0.5, x, y)


def paint_plaza(M):
    fill(M, 0, Y_PLAZA, MW, Y_PYR, lambda x, y: flag(x, y, 0.12))
    for y in range(Y_PLAZA, Y_PYR):
        for x in list(range(0, 16)) + list(range(MW - 16, MW)):
            M.set(x, y, frieze(x + 16 if x < CX else x - 16, y, x < CX))
        for x in range(CX - 8, CX + 8):                                               # the gold-inlaid way
            if x in (CX - 8, CX + 7): M.set(x, y, 13)
            elif (y // 8) % 2 == 0 and x in (CX - 4, CX + 3): M.set(x, y, 14)
    k = 0
    for y in range(Y_PLAZA + 32, Y_PYR - 64, 128):
        glyph_stone(M, 32, y, k % 4); glyph_stone(M, MW - 64, y, (k + 2) % 4)
        brazier(M, 32, y + 64); brazier(M, MW - 64, y + 64)
        k += 1
    for vx in range(24, MW - 24, 48):
        vine(M, vx + 5, Y_PLAZA, 20, vx // 48)


def paint_cenote(M):
    cx, cy, R = CEN_CX, CEN_CY, CEN_R
    W0 = 16                                                                            # the cliff wall
    for y in range(cy - R - 8, cy + R + 8):
        for x in range(MW):
            dx, dy = x + 0.5 - cx, y + 0.5 - cy
            d = math.hypot(dx, dy)
            if d > R + 7: continue
            if d > R:                                                                  # the rim stones
                c = stone_block(x, y, 8, 8, 0.62 - 0.22 * (dx + dy) / (d + 1), 0, 60)
            elif d > R - W0:
                # the wall: the far (north) side faces south, into shade; the near side is lit
                t = 0.42 + 0.4 * (dy / d) + 0.12 * (dx / d)
                v = (d - (R - W0)) / W0
                c = g.ramp([0, 6, 7, 8], max(0.0, min(1.0, t + 0.15 * (1 - v))), x, y)
                if int(d) % 5 == 0: c = 6 if c != 0 else 0                             # rock strata
            else:
                sun = 0.3 - 0.25 * (dy / R) * -1
                c = water(x, y, max(-0.1, min(0.4, 0.15 + 0.2 * dy / R)))
            M.set(x, y, c)
    for k in range(14):                                                                # vines over the rim
        a = math.pi + TAU * (k + 0.5) / 28
        vx = int(cx + math.cos(a) * (R - 1)); vy = int(cy + math.sin(a) * (R - 1))
        vine(M, vx, vy, 10 + (k * 5) % 12, k, 0.8)
    # a stone bridge across, two tiles high
    by0, by1 = cy - 16, cy + 16
    for y in range(by0, by1):
        for x in range(cx - R - 16, cx + R + 16):
            ly = y - by0
            if ly == 0: c = 9
            elif ly < 3: c = 13 if (x % 8) < 4 else 7                                   # gold-capped rails
            elif ly >= 29: c = 6 if ly > 29 else (13 if (x % 8) < 4 else 7)
            else: c = stone_block(x, y, 16, 8, 0.55, 0, 70)
            M.set(x, y, c)
    shade_below(M, cx - R - 16, cx + R + 16, by1, 5, 0.7)


def column(M, x0, y0):
    """a feathered-serpent column seen from above, 32 x 32: a round capital with plumes"""
    for y in range(32):
        for x in range(32):
            d = math.hypot(x - 15.5, y - 15.5)
            if d > 15.5: continue
            X, Y = x0 + x, y0 + y
            a = math.atan2(y - 15.5, x - 15.5)
            if d > 11: c = g.ramp([3, 4, 11, 5], 0.5 + 0.4 * math.sin(a * 8) - 0.2 * (x + y - 31) / 31, X, Y)
            elif d > 9: c = 13
            else:
                c = g.ramp([6, 7, 8, 9], 0.55 - (x + y - 31) / 40.0, X, Y)
                if abs(d - 5) < 0.8: c = 6
            M.set(X, Y, c)


def paint_courtyard(M):
    fill(M, 0, 0, MW, Y_CEN, lambda x, y: flag(x, y, 0.12))
    for y in range(0, Y_CEN):
        for x in list(range(0, 16)) + list(range(MW - 16, MW)):
            M.set(x, y, frieze(x + 16 if x < CX else x - 16, y, x < CX))
    leaf_edge(M, 16, Y_CEN - 64, MW - 16, Y_CEN, 's')
    for y in range(64, Y_CEN - 96, 128):
        column(M, 16, y); column(M, MW - 48, y)
    # the sun stone: rings of day signs round the face of the sun, gold and jade
    cx, cy, R = SUN_CX, SUN_CY, SUN_R
    for y in range(cy - R, cy + R):
        for x in range(cx - R, cx + R):
            dx, dy = x + 0.5 - cx, y + 0.5 - cy
            d = math.hypot(dx, dy)
            if d > R - 0.5: continue
            a = math.atan2(dy, dx)
            lit = 0.5 - 0.25 * (dx + dy) / R
            if d > R - 3: c = g.ramp([6, 9], lit + 0.2, x, y)
            elif d > R - 10: c = 13 if (int((a + TAU) * 16 / TAU) % 2) else g.ramp([7, 8], lit, x, y)
            elif d > R - 13: c = 6
            elif d > R - 22:
                seg = int((a + TAU) * 20 / TAU)
                c = 11 if (seg % 2 == 0 and abs(d - (R - 17.5)) < 3) else g.ramp([7, 8], lit, x, y)
                if seg % 2 == 1 and abs(d - (R - 17.5)) < 1.2: c = 13
            elif d > R - 25: c = 13
            elif d > 12: c = g.ramp([7, 8, 9], lit + 0.1 * math.sin(a * 4), x, y)
            else:
                c = 14 if d < 10 else 13
                if abs(dy + 3) < 1.5 and abs(abs(dx) - 4) < 1.5: c = 0
                if abs(dy - 4) < 1 and abs(dx) < 4: c = 15
            M.set(x, y, c)
    # the temple front across the top: a carved wall, gold doors
    for y in range(0, 32):
        for x in range(MW):
            if y < 24:
                c = frieze(x, y + 8, x < CX) if y > 2 else 9
                if CX - 32 <= x < CX + 32: c = 13 if (x + y) % 4 else 14
            else:
                c = g.dmix(6, 0, (y - 24) / 8.0, x, y)
            M.set(x, y, c)


# ------------------------------------------------------------------ tiles
def full_pal():
    """the 16 colours, then the A1200's in-between ones (in the order dmix made them)"""
    pal = list(PAL) + [0] * 112
    for i, (a, b, k) in enumerate(g.AGA['order']):
        t = k / g.AGA['steps']; ca = pal[a]; cb = pal[b]
        pal[16 + i] = sum(int(round(((ca >> s) & 255) * (1 - t) + ((cb >> s) & 255) * t)) << s for s in (16, 8, 0))
    return pal


def cut(M, pal):
    """the picture -> tiles (each stored once) and the map; when there are more than
    TILE_LIMIT, the least used tiles that look most like another are merged into it"""
    keys = {}
    tiles, uses, cells = [], [], []
    blank = tuple([0] * 256)
    keys[blank] = 0; tiles.append(blank); uses.append(0)
    for r in range(ROWS):
        for c in range(COLS):
            t = tuple(M.p[(r * 16 + y) * MW + c * 16 + x] for y in range(16) for x in range(16))
            if t not in keys:
                keys[t] = len(tiles); tiles.append(t); uses.append(0)
            cells.append(keys[t]); uses[keys[t]] += 1
    unique = len(tiles)
    cols = [((pal[i] >> 16) & 255, (pal[i] >> 8) & 255, pal[i] & 255) for i in range(len(pal))]
    def sig(t):
        out = []
        for by in range(4):
            for bx in range(4):
                r = gg = b = 0
                for y in range(4):
                    for x in range(4):
                        cr = cols[t[(by * 4 + y) * 16 + bx * 4 + x]]
                        r += cr[0]; gg += cr[1]; b += cr[2]
                out += [r / 16, gg / 16, b / 16]
        return out
    alive = list(range(1, len(tiles)))
    remap = list(range(len(tiles)))
    if len(tiles) > TILE_LIMIT:
        sigs = [sig(t) for t in tiles]
        def dist(a, b): return sum((p - q) ** 2 for p, q in zip(sigs[a], sigs[b]))
        def nearest(a):
            best, bd = -1, 1e30
            for b in alive:
                if b != a:
                    d = dist(a, b)
                    if d < bd: bd, best = d, b
            return best, bd
        near = {a: nearest(a) for a in alive}
        while len(alive) + 1 > TILE_LIMIT:
            a = min(alive, key=lambda t: near[t][1] * uses[t])
            b = near[a][0]
            remap[a] = b; uses[b] += uses[a]; alive.remove(a)
            for t in alive:
                if near[t][0] == a: near[t] = nearest(t)
        for i in range(len(remap)):
            j = i
            while remap[j] != j: j = remap[j]
            remap[i] = j
    order = [0] + alive
    newi = {t: k for k, t in enumerate(order)}
    return [list(tiles[t]) for t in order], [newi[remap[c]] for c in cells], unique


def stamps_of(cells, rects):
    """named blocks of map cells: the metatiles the map was built from (Tiles page, Stamp)"""
    out = []
    for name, x, y, w, h in rects:
        c0, r0, cw, ch = x // 16, y // 16, w // 16, h // 16
        out.append(dict(name=name, w=cw, h=ch, cells=[cells[(r0 + r) * COLS + c0 + c] for r in range(ch) for c in range(cw)]))
    return out


def map_png(M, fn, pal, scale=1):
    im = Image.new('RGB', (MW, MH))
    px = im.load()
    for y in range(MH):
        for x in range(MW):
            c = pal[M.p[y * MW + x]]
            px[x, y] = ((c >> 16) & 255, (c >> 8) & 255, c & 255)
    if scale != 1: im = im.resize((MW * scale, MH * scale), Image.NEAREST)
    im.save(fn)


# ================================================================== the game
# Sprites are drawn as 'L' images, 0 clear and 1..3 the sprite's colours (1 main, 2 dark, 3 light)
from ex_shmup import new, rim, put, Bank, act, boom, blank, SFX, LASER, BOOM, BIGBOOM, POWER, WARNING, READY, LOSE

LETTER = {'P': ["1111.", "1...1", "1111.", "1....", "1...."],
          'S': [".1111", "1....", ".111.", "....1", "1111."],
          'O': [".111.", "1...1", "1...1", "1...1", ".111."],
          'M': ["1...1", "11.11", "1.1.1", "1...1", "1...1"]}
DIRS = "N NE E SE S SW W NW".split()


def rot_poly(pts, ang, cx, cy):
    ca, sa = math.cos(ang), math.sin(ang)
    return [(cx + (px - cx) * ca - (py - cy) * sa, cy + (px - cx) * sa + (py - cy) * ca) for px, py in pts]


def ship_img(flame, bank=0):
    """the Quetzal: a jade glider with feathered wings, nose up (16 x 24 hardware sprite);
    bank -1 / 1 = rolling left / right (that wing shortens)"""
    im, d = new(16, 24)
    wl = 7 - (2 if bank < 0 else 0)
    wr = 7 - (2 if bank > 0 else 0)
    d.polygon([(7.5, 1), (10, 7), (10, 16), (7.5, 19), (5, 16), (5, 7)], fill=1)                 # body
    d.polygon([(5, 9), (7.5 - wl - 1, 14), (7.5 - wl, 17), (5, 15)], fill=1)                    # wings
    d.polygon([(10, 9), (7.5 + wr + 1, 14), (7.5 + wr, 17), (10, 15)], fill=1)
    rim(im, -1, -1)
    for k in range(3):                                                                           # wing feathers
        put(im, int(7.5 - wl + k), 16 - k % 2, 3)
        put(im, int(7.5 + wr - k), 16 - k % 2, 3)
    d.ellipse([6, 5, 9, 9], fill=3)                                                              # canopy
    put(im, 7, 6, 2)
    put(im, 7, 12, 3); put(im, 8, 12, 3)                                                         # jade gem
    for k in range(flame):                                                                       # engine glow
        put(im, 7, 19 + k, 3 if k < flame - 1 else 1)
        put(im, 8, 19 + k, 3 if k < flame - 2 else 1)
    return im


def sun_orb(f):
    """an option: a little gold sun with turning rays (16 x 24 hardware sprite)"""
    im, _ = new(16, 24)
    cx, cy = 7.5, 11.5
    for py in range(24):
        for px in range(16):
            dd = math.hypot(px - cx, py - cy)
            a = math.atan2(py - cy, px - cx)
            if dd <= 2.4: put(im, px, py, 3)
            elif dd <= 4.2: put(im, px, py, 1)
            elif 4.8 < dd <= 6.5 and int((a + TAU) * 8 / TAU + f * 0.5) % 2 == 0: put(im, px, py, 2 if dd > 5.8 else 1)
    return im


def jade_bolt(f):
    """the ship's shot: twin jade darts (BOB 16 x 16)"""
    im, d = new(16, 16)
    for x0 in (4, 10):
        d.line([(x0, 2), (x0, 13)], fill=1)
        d.line([(x0 + 1, 3), (x0 + 1, 12)], fill=2)
        put(im, x0, 1 + f, 3); put(im, x0, 2 + f, 3); put(im, x0 + 1, 2, 3)
    return im


def missile_img(ang):
    """a homing missile pointing at angle ang (0 = up, clockwise), with its flame (BOB 16 x 16)"""
    im, d = new(16, 16)
    body = [(7.5, 1), (9.5, 5), (9.5, 11), (5.5, 11), (5.5, 5)]
    d.polygon(rot_poly(body, ang, 7.5, 7.5), fill=1)
    for fin in ([(5.5, 9), (3, 13), (5.5, 12)], [(9.5, 9), (12, 13), (9.5, 12)]):
        d.polygon(rot_poly(fin, ang, 7.5, 7.5), fill=2)
    for k, c in ((2, 3), (12.5, 3), (14, 3), (15, 2)):                                           # nose, flame
        fx, fy = rot_poly([(7.5, k)], ang, 7.5, 7.5)[0]
        put(im, int(round(fx)), int(round(fy)), c)
    return im


def plasma_img(f):
    """an enemy shot: a small crimson fireball (16 x 24 hardware sprite)"""
    im, _ = new(16, 24)
    r = 3.2 + 0.6 * f
    for py in range(24):
        for px in range(16):
            dd = math.hypot(px - 7.5, py - 11.5)
            if dd <= r * 0.45: put(im, px, py, 3)
            elif dd <= r * 0.8: put(im, px, py, 1)
            elif dd <= r: put(im, px, py, 2)
    return im


def glider_img(f):
    """a stone-winged serpent bat, wings beating (BOB 16 x 16)"""
    im, d = new(16, 16)
    up = (0, -3, 0, 3)[f]
    d.ellipse([6, 3, 9, 13], fill=1)
    d.polygon([(6, 6), (0, 6 + up), (1, 9 + up // 2), (6, 10)], fill=1)
    d.polygon([(9, 6), (15, 6 + up), (14, 9 + up // 2), (9, 10)], fill=1)
    rim(im, -1, -1)
    put(im, 7, 5, 3); put(im, 8, 5, 3)                                                           # eyes
    for k in range(3):
        put(im, 2 + 2 * k, 8 + up // 2, 2)
        put(im, 13 - 2 * k, 8 + up // 2, 2)
    put(im, 7, 13, 2); put(im, 8, 14, 2)                                                         # tail
    return im


def scarab_img(f):
    """a jade scarab drone with buzzing gold wings (BOB 16 x 16)"""
    im, d = new(16, 16)
    d.ellipse([4, 4, 11, 14], fill=1)
    rim(im, -1, -1)
    d.line([(7.5, 5), (7.5, 13)], fill=2)
    if f == 0:
        d.ellipse([0, 2, 6, 8], fill=3); d.ellipse([9, 2, 15, 8], fill=3)
    else:
        d.ellipse([1, 5, 6, 9], fill=3); d.ellipse([9, 5, 14, 9], fill=3)
    put(im, 6, 3, 2); put(im, 9, 3, 2); put(im, 5, 2, 2); put(im, 10, 2, 2)                      # feelers
    put(im, 7, 11, 3); put(im, 8, 11, 3)
    return im


def idol_img(f):
    """a stone idol head set in the ground, its eyes glowing (BOB 16 x 16)"""
    im, d = new(16, 16)
    d.rounded_rectangle([1, 1, 14, 14], radius=3, fill=1)
    rim(im, -1, -1)
    d.rectangle([3, 3, 12, 4], fill=2)                                                           # brow
    e = 3 if f else 2
    d.rectangle([4, 6, 6, 7], fill=e); d.rectangle([9, 6, 11, 7], fill=e)                         # eyes
    d.rectangle([5, 10, 10, 12], fill=2)
    put(im, 7, 11, e); put(im, 8, 11, e)
    return im


def totem_img(f):
    """a flying stone mask, 32 x 32: carved brow, glowing eyes and mouth, gold ear spools"""
    im, d = new(32, 32)
    d.rounded_rectangle([4, 2, 27, 29], radius=6, fill=1)
    d.ellipse([0, 10, 6, 18], fill=1); d.ellipse([25, 10, 31, 18], fill=1)
    rim(im, -1, -1)
    d.ellipse([1, 12, 4, 16], fill=3); d.ellipse([27, 12, 30, 16], fill=3)                        # ear spools
    d.rectangle([7, 7, 24, 9], fill=2)                                                           # brow
    glow = 3 if f % 2 == 0 else 2
    d.rectangle([9, 11, 13, 14], fill=glow); d.rectangle([18, 11, 22, 14], fill=glow)
    d.line([(15, 12), (16, 20)], fill=2)                                                          # nose
    d.rectangle([10, 22, 21, 25], fill=2); d.rectangle([12, 23, 19, 24], fill=glow)                 # mouth
    for k in range(4):
        put(im, 7 + k * 6, 4, 2); put(im, 8 + k * 6, 27, 2)
    return im


def shard_img(f):
    """a broken piece of a totem with a glowing core, spinning (BOB 16 x 16)"""
    im, d = new(16, 16)
    pts = [(7.5, 1), (13, 6), (11, 14), (4, 13), (2, 5)]
    d.polygon(rot_poly(pts, f * TAU / 8, 7.5, 7.5), fill=1)
    rim(im, -1, -1)
    d.ellipse([6, 6, 9, 9], fill=3)
    return im


def serpent_img(f):
    """Quetzalcoatl coming down out of the temple, 64 x 48: a crest of jade plumes,
    a stone face, gold eyes, jaws that open on the fire inside"""
    im, d = new(64, 48)
    for k in range(9):                                                                           # the plumes, fanned out
        a = math.pi * (0.1 + 0.8 * k / 8)
        d.line([(32, 22), (32 + math.cos(a) * 31, 22 - math.sin(a) * 22)], fill=1, width=4)
    rim(im, 0, -1)
    for k in range(9):
        a = math.pi * (0.1 + 0.8 * k / 8)
        put(im, int(32 + math.cos(a) * 29), int(22 - math.sin(a) * 20), 3)
    jaw = (0, 3, 6)[f]
    d.polygon([(14, 14), (50, 14), (54, 26), (46, 34 + jaw // 2), (32, 37 + jaw), (18, 34 + jaw // 2), (10, 26)], fill=2)
    d.polygon([(17, 16), (47, 16), (50, 25), (44, 31), (20, 31), (14, 25)], fill=1)
    rim(im, -1, -1)
    d.ellipse([20, 19, 27, 24], fill=3); d.ellipse([37, 19, 44, 24], fill=3)                     # eyes
    put(im, 23, 21, 2); put(im, 40, 21, 2)
    d.polygon([(20, 32), (44, 32), (40, 37 + jaw), (32, 40 + jaw), (24, 37 + jaw)], fill=2)        # jaws
    if jaw:
        d.polygon([(24, 33), (40, 33), (36, 35 + jaw), (28, 35 + jaw)], fill=3)
    for k in range(4):                                                                           # fangs
        put(im, 23 + k * 6, 33, 1); put(im, 24 + k * 6, 34, 1)
    for k in range(5): put(im, 18 + k * 7, 15, 3)                                                 # gold studs
    return im


def gem_img(letter, shine):
    """a power-up: a round gem with its letter (BOB 16 x 16)"""
    im, d = new(16, 16)
    d.ellipse([1, 1, 14, 14], fill=2)
    d.ellipse([2, 2, 13, 13], fill=1)
    for k in range(4, 12):
        if (k - shine) % 8 in (0, 1): put(im, k, 2, 3)
    for r, row in enumerate(LETTER[letter]):
        for c, ch in enumerate(row):
            if ch == '1': put(im, 5 + c, 5 + r, 3)
    return im


def jungle_songs():
    run = g.song("Serpent run", 132, [
        g.bars("Half time", 3, "Tom fill", 1, "Breakbeat", 3, "Tom fill", 1, "Breakbeat", 7, "Tom fill", 1),
        g.bars("Walking bass", 8, "Offbeat bass", 4, "Walking bass", 4),
        g.bars("Long minor", 4, "Minor to major", 4, "Offbeat skank", 4, "Minor to major", 4),
        g.bars("", 4, "Hook one", 2, "Hook two", 2, "Arp up", 2, "Arp down", 2, "Hook one", 2, "Hook two", 2)], loop_bar=4)
    return [run, sh.songs()[1]]


def group_key(names):
    def key(r):
        w = r['when']
        nb = names[r['b']]['name'] if 0 <= r['b'] < len(names) else ""
        if w == 14: return "Fire (hold for auto-fire)"
        if w == 11 and names[r['b']]['role'] == 0: return "Quetzal hit by fire"
        if w == 11 and nb == "Serpent": return "The serpent"
        if w == 11 and nb == "Totem": return "Totems break apart"
        if w == 11: return "Shots hit enemies"
        if w == 0 and nb.startswith("Gem"): return "Power-up gems"
        if w == 0: return "Quetzal hit by enemies"
        if w in (9, 15): return "The serpent"
        return "Game flow"
    return key


def jade_serpent():
    sh.aga_cap()
    M = paint_map()
    pal = full_pal()
    tiles, cells, unique = cut(M, pal)
    # the backdrop (title, level cards, the HUD strip): the temple courtyard, the map's last screen
    im = g.canvas(); P = im.load()
    x0 = (320 - MW) // 2                       # the map's top screen in the middle, jungle either side
    for py in range(256):
        for px in range(320):
            if x0 <= px < x0 + MW: P[px, py] = M.p[py * MW + px - x0]
            else: P[px, py] = canopy(px, py)

    # ---------------- sprites (BOBs take the nearest map colours; hardware sprites have their own)
    B = Bank()
    shipc = [0x38c8a0, 0x104838, 0xffd860]
    B.add("Quetzal", ship_img(3), shipc)
    B.add("Quetzal glow", ship_img(4), shipc)
    B.add("Quetzal glow 2", ship_img(2), shipc)
    B.add("Quetzal left", ship_img(3, -1), shipc)
    B.add("Quetzal right", ship_img(3, 1), shipc)
    B.add("Quetzal boost", ship_img(5), shipc)
    sunc = [0xffc030, 0x904010, 0xfff8d0]
    for k in range(4): B.add("Sun %d" % (k + 1), sun_orb(k), sunc)
    boltc = [PAL[11], PAL[10], PAL[1]]
    B.add("Jade bolt", jade_bolt(0), boltc); B.add("Jade bolt 2", jade_bolt(1), boltc)
    misc = [PAL[8], PAL[6], PAL[14]]
    for k in range(8): B.add("Missile " + DIRS[k], missile_img(k * TAU / 8), misc)
    plc = [0xff4060, 0x801020, 0xfff0c0]
    B.add("Fireball", plasma_img(0), plc); B.add("Fireball 2", plasma_img(1), plc)
    glc = [PAL[11], PAL[6], PAL[13]]
    for k in range(4): B.add("Glider %d" % (k + 1), glider_img(k), glc)
    scc = [PAL[4], PAL[2], PAL[13]]
    B.add("Scarab", scarab_img(0), scc); B.add("Scarab buzz", scarab_img(1), scc)
    idc = [PAL[8], PAL[6], PAL[15]]
    B.add("Idol", idol_img(0), idc); B.add("Idol glow", idol_img(1), idc)
    toc = [PAL[7], PAL[6], PAL[14]]
    B.add("Totem", totem_img(0), toc); B.add("Totem glow", totem_img(1), toc)
    shc = [PAL[7], PAL[6], PAL[11]]
    for k in range(4): B.add("Shard %d" % (k + 1), shard_img(k), shc)
    svc = [PAL[4], PAL[7], PAL[13]]
    for k in range(3): B.add("Serpent %d" % (k + 1), serpent_img(k), svc)
    bmc = [PAL[13], PAL[12], PAL[14]]
    for k in range(6): B.add("Boom %d" % (k + 1), boom(16, 16, k, 6, 5), bmc)
    for L, cc in (("P", [PAL[15], PAL[6], PAL[1]]), ("S", [PAL[11], PAL[10], PAL[1]]),
                  ("O", [PAL[13], PAL[12], PAL[1]]), ("M", [PAL[4], PAL[2], PAL[1]])):
        for k in range(2): B.add("Gem %s %d" % (L, k + 1), gem_img(L, k * 4), cc)

    # ---------------- actors: one of each kind; copies make the pools (shots, waves, explosions)
    actors = []
    A = {}
    def add(a, copies=1):
        a['copies'] = copies
        A[a['name']] = len(actors); actors.append(a)
        return a
    turn = {4: ([B["Quetzal boost"], B["Quetzal glow"]], 3, 0), 8: ([B["Quetzal glow 2"], B["Quetzal"]], 3, 0)}
    for k in (5, 6, 7): turn[k] = ([B["Quetzal right"]], 4, 0)
    for k in (9, 10, 11): turn[k] = ([B["Quetzal left"]], 4, 0)
    turn[0] = ([B["Quetzal"], B["Quetzal glow"], B["Quetzal glow 2"]], 3, 0)
    ship = add(act("Quetzal", B["Quetzal"], 0, 2, CX - 8, 196, anims=turn))
    ship['anim_dirs'] = True
    add(act("Sun option", B["Sun 1"], 11, 1, CX - 8, 196, vis=False,
            anims={0: ([B["Sun %d" % (k + 1)] for k in range(4)], 4, 0)}), 2)
    add(act("Jade bolt", B["Jade bolt"], 9, 8, 0, 0, vis=False, bob=True, aim=1,
            anims={0: ([B["Jade bolt"], B["Jade bolt 2"]], 3, 0)}), 3)
    ma = {0: ([B["Missile N"]], 8, 0)}
    for k in range(8): ma[4 + k] = ([B["Missile " + DIRS[k]]], 8, 0)
    mis = add(act("Missile", B["Missile N"], 9, 3, 0, 0, vis=False, bob=True, aim=6, anims=ma), 2)
    mis['anim_dirs'] = True
    add(act("Fireball", B["Fireball"], 9, 2, 0, 0, vis=False, aim=5, anims={0: ([B["Fireball"], B["Fireball 2"]], 3, 0)}), 4)
    def foe(name, frames, rate, speed, pattern, hits=1, fire=None, frate=90, fpat=1, copies=1, px=0, py=0, fast=1):
        a = act(name, B[frames[0]], 10, speed, px, py, vis=False, bob=True, pattern=pattern, enter=0, comeback=False, hits=hits,
                anims={0: ([B[f] for f in frames], rate, 0)}, fast=fast)
        if fire:
            a.update(fire=A[fire], fire_rate=frate, fire_pat=fpat)
        return add(a, copies)
    foe("Glider", ["Glider %d" % (k + 1) for k in range(4)], 4, 2, 1, fire="Fireball", frate=150, copies=3)
    foe("Scarab", ["Scarab", "Scarab buzz"], 2, 2, 2, fire="Fireball", frate=110, copies=3)
    foe("Idol", ["Idol", "Idol glow"], 12, 1, 4, hits=3, fire="Fireball", frate=80, fpat=2, copies=2, fast=0)
    foe("Totem", ["Totem", "Totem glow"], 10, 1, 0, hits=8, fire="Fireball", frate=110, fpat=3)
    foe("Shard", ["Shard %d" % (k + 1) for k in range(4)], 3, 3, 2, copies=2)
    foe("Serpent", ["Serpent 1", "Serpent 2", "Serpent 3", "Serpent 2"], 10, 1, 5, hits=60,
        fire="Fireball", frate=70, fpat=3, px=CX - 32, py=26, fast=0)
    add(act("Boom", B["Boom 1"], 12, 1, 0, 0, vis=False, bob=True, anims={0: ([B["Boom %d" % (j + 1)] for j in range(6)], 4, 1)}), 3)
    for L in "PSOM":                                        # power-up gems drift down the screen
        add(act("Gem " + L, B["Gem %s 1" % L], 10, 1, 0, 0, vis=False, bob=True, enter=0, comeback=False,
                anims={0: ([B["Gem %s 1" % L], B["Gem %s 2" % L]], 6, 0)}))

    # ---------------- spawners: map y, the actor, how many, frames apart, flight pattern (-1 the actor's own),
    # edge (0 top, 1 right, 3 left), x (or the height for a side edge), spacing across
    S = []
    def sp(my, name, n=1, gap=20, pat=-1, edge=0, sx=152, dx=0, at=40):
        k = MW / 320.0                                     # (laid out for 320: scaled to the play area)
        S.append(dict(y=my, act=A[name], n=n, gap=gap, pattern=pat, edge=edge, x=int(round(sx * k)), dx=int(round(dx * k)), at=at))
    # the river
    sp(3000, "Glider", 3, 22, sx=64); sp(2900, "Glider", 3, 22, sx=224)
    sp(2800, "Scarab", 3, 26, sx=150); sp(2720, "Glider", 3, 14, sx=72, dx=64)
    # the ruins and the causeway
    sp(2620, "Idol", sx=152, pat=4); sp(2560, "Glider", 3, 18, edge=3, pat=0, at=48)
    sp(2470, "Totem", sx=144); sp(2380, "Scarab", 3, 24, edge=1, pat=2, at=30)
    sp(2300, "Idol", sx=40, pat=4); sp(2250, "Glider", 3, 14, sx=56, dx=80)
    sp(2190, "Idol", sx=264, pat=4)
    # the step pyramid
    sp(2060, "Scarab", 3, 22, sx=60); sp(2000, "Scarab", 3, 22, sx=240)
    sp(1940, "Idol", sx=56, pat=4); sp(1940, "Idol", sx=248, pat=4)
    sp(1840, "Glider", 3, 14, sx=40, dx=96); sp(1760, "Totem", sx=144)
    sp(1700, "Idol", sx=72, pat=4); sp(1700, "Idol", sx=232, pat=4)
    sp(1600, "Glider", 3, 20, edge=1, pat=1, at=70); sp(1560, "Scarab", 3, 20, edge=3, pat=2, at=40)
    # the glyph plaza
    sp(1460, "Idol", sx=72, pat=4); sp(1430, "Glider", 3, 18, sx=150)
    sp(1340, "Totem", sx=64); sp(1330, "Idol", sx=232, pat=4)
    sp(1250, "Scarab", 3, 16, sx=230); sp(1200, "Glider", 3, 14, sx=48, dx=88)
    # the cenote
    sp(1060, "Glider", 3, 18, edge=3, pat=1, at=50); sp(980, "Glider", 3, 18, edge=1, pat=1, at=90)
    sp(900, "Totem", sx=144); sp(820, "Scarab", 3, 20, sx=80); sp(760, "Scarab", 3, 20, sx=220)
    sp(680, "Glider", 3, 14, sx=40, dx=96)
    # the courtyard, then the serpent
    sp(540, "Idol", sx=48, pat=4); sp(540, "Idol", sx=256, pat=4)
    sp(460, "Totem", sx=144); sp(380, "Scarab", 3, 18, edge=3, pat=2, at=36)
    sp(300, "Glider", 3, 14, sx=56, dx=80)
    sp(60, "Serpent", sx=(CX - 32) * 320.0 / MW)

    # ---------------- rules
    R = g.R
    Q, bolt, mis_, fire_, boom_ = A["Quetzal"], A["Jade bolt"], A["Missile"], A["Fireball"], A["Boom"]
    rules = [R(when=14, n=10, act=22, target=bolt, value=Q), R(when=14, n=10, act=2, value=LASER),
             R(when=14, n=40, act=22, target=mis_, value=Q)]
    drops = {"Scarab": "Gem P", "Idol": "Gem S", "Shard": "Gem O"}
    for nm, pts in (("Glider", 100), ("Scarab", 150), ("Idol", 300), ("Shard", 80)):
        e = A[nm]
        for s in (bolt, mis_):                              # a shot hits an enemy: score, explosion, maybe a gem
            rules += [R(when=11, a=s, b=e, act=0, value=pts), R(when=11, a=s, b=e, act=24, target=boom_, value=e),
                      R(when=11, a=s, b=e, act=2, value=BOOM)]
            if nm in drops:
                c = A[drops[nm]]
                rules += [R(when=11, a=s, b=e, act=14, target=c, value=e), R(when=11, a=s, b=e, act=7, target=c)]
            rules += [R(when=11, a=s, b=e, act=6, target=e)]
    t = A["Totem"]
    for s in (bolt, mis_):                                  # a totem breaks into two shards and leaves an M gem
        rules += [R(when=11, a=s, b=t, act=0, value=500), R(when=11, a=s, b=t, act=24, target=boom_, value=t),
                  R(when=11, a=s, b=t, act=2, value=BIGBOOM), R(when=11, a=s, b=t, act=25, target=A["Shard"], value=t),
                  R(when=11, a=s, b=t, act=25, target=A["Shard"], value=t),
                  R(when=11, a=s, b=t, act=14, target=A["Gem M"], value=t), R(when=11, a=s, b=t, act=7, target=A["Gem M"]),
                  R(when=11, a=s, b=t, act=6, target=t)]
    for L, kind in (("P", 0), ("S", 1), ("O", 2), ("M", 4)):  # pick up a gem: P firepower, S speed, O a sun option, M missiles
        c = A["Gem " + L]
        rules += [R(a=Q, b=c, act=23, value=kind), R(a=Q, b=c, act=6, target=c), R(a=Q, b=c, act=2, value=POWER), R(a=Q, b=c, act=0, value=250)]
    def hit(when, a, b):                                    # the Quetzal is hit: explodes, back to the start, loses its power-ups
        return [R(when=when, a=a, b=b, act=1), R(when=when, a=a, b=b, act=24, target=boom_, value=Q),
                R(when=when, a=a, b=b, act=2, value=LOSE),
                R(when=when, a=a, b=b, act=23, value=3), R(when=when, a=a, b=b, act=4, target=Q),
                R(when=when, a=a, b=b, act=16, target=Q)]
    for nm in ("Glider", "Scarab", "Totem", "Shard", "Serpent"):
        e = A[nm]
        rules += hit(0, Q, e)
        if nm != "Serpent":
            rules += [R(a=Q, b=e, act=24, target=boom_, value=e), R(a=Q, b=e, act=6, target=e)]
    rules += hit(11, fire_, Q)
    sv = A["Serpent"]
    for s in (bolt, mis_):                                  # the serpent falls: the temple is free
        rules += [R(when=11, a=s, b=sv, act=0, value=5000), R(when=11, a=s, b=sv, act=24, target=boom_, value=sv),
                  R(when=11, a=s, b=sv, act=24, target=boom_, value=sv), R(when=11, a=s, b=sv, act=2, value=BIGBOOM),
                  R(when=11, a=s, b=sv, act=6, target=sv), R(when=11, a=s, b=sv, act=17),
                  R(when=11, a=s, b=sv, act=18, value=0)]
    rules += [R(when=9, a=sv, n=2, act=22, target=fire_, value=sv)]          # and spits fire at you
    rules += [R(when=15, act=18, value=1), R(when=15, act=2, value=WARNING),
              R(when=15, act=27, target=50, value=2)]               # the alarm: a red alert, fading in over 1 s
    rules += [R(when=4, act=9), R(when=5, act=18, value=0), R(when=7, act=16, target=Q), R(when=7, act=2, value=READY),
              R(when=7, act=18, value=0)]

    p = g.make_project("Jade Serpent", PAL, im, [], actors, rules, [0, 0, 0, 128], msg_col=14, lives=3, sfx=g.sfx_list(SFX),
                       over="THE JUNGLE TAKES YOU - GAME OVER", win="THE SERPENT IS BROKEN! - PRESS FIRE")
    p['sky_on'] = False
    p['sprites'] = B.s + [blank(i) for i in range(len(B.s), 128)]
    p['tiles'] = [dict(name="AIR" if i == 0 else "T%03d" % i, px=tp, solid=False, dig=False, hard=12, points=0, goal=False,
                       ladder=False, sound=-1, becomes=0) for i, tp in enumerate(tiles)]
    p.update(tiles_on=False, shmup_map=True, tile_size=16, map_w=COLS, map_h=ROWS, map=cells, tile_dig=False, tools=[],
             scroll_dir=1, scroll_speed=3, hills_on=False, spawners=S)
    p['stamps'] = stamps_of(cells, [("Serpent head", CX - 64, Y_RUINS + 64, 32, 32), ("Platform", 0, 2208, 32, 48),
                                    ("Pyramid shrine", CX - 32, PYR_CY - 32, 64, 64), ("Stairs", CX - 32, PYR_CY + 32, 64, 48),
                                    ("Glyph stone", 32, Y_PLAZA + 32, 32, 32), ("Brazier", 32, Y_PLAZA + 96, 32, 32),
                                    ("Serpent column", 16, 64, 32, 32), ("Sun stone", CX - 48, 96, 96, 96),
                                    ("Causeway", CX - 32, 2400, 64, 64), ("Wall frieze", 0, 1152, 16, 64)])
    p.update(levels_on=True, levels=[dict(seed=3000 + i * 37, hilly=0, base=240, heights=[240] * 320) for i in range(2)])
    p['songs'] = jungle_songs()
    p['level_song'] = [0] * 10
    p.update(title_on=True, title1="JADE SERPENT", title2="PRESS FIRE TO FLY", lev_text="TEMPLE", goal_on=True, goal=1, goal_label="SERPENT")
    g.dress_ui(p, "Stone", 1, 1, [(1, "SCORE ", 1, 0, 0xffffff, 0x101010, 6), (5, "TEMPLE ", 16, 0, 0xffe070, 0x101010, 1),
                                  (2, "SHIPS ", 31, 0, 0x60f0c0, 0x101010, 1)])
    p['_gk'] = group_key(actors)
    print('jade serpent: %d tiles, %d kept' % (unique, len(tiles)))
    sh.set_depth(p)
    # named palettes: the second temple by moonlight, and a red alert when the serpent comes
    # (palette_look in scr_project.gml: Night and Red alert, snapped to Amiga 12-bit colours)
    def look(kind):
        n = 1 << p['depth']
        q = lambda v: int(max(0, min(255, v)) / 17 + 0.5) * 17
        out = []
        for i in range(128):
            if i >= n:
                out.append(-1)
                continue
            c = p['pal'][i]
            r, gg, b = c >> 16 & 255, c >> 8 & 255, c & 255
            l = 0.3 * r + 0.59 * gg + 0.11 * b
            if kind == 'night': r, gg, b = r * 0.25 + l * 0.1, gg * 0.3 + l * 0.12, b * 0.55 + l * 0.2 + 24
            else: r, gg, b = l * 0.6 + 70, l * 0.25, l * 0.25
            out.append(q(r) << 16 | q(gg) << 8 | q(b))
        return out
    p['palettes'] = [dict(name="Moonlight", cols=look('night')), dict(name="Red alert", cols=look('red'))]
    p['level_pal'] = [0, 1] + [0] * 8
    return p
