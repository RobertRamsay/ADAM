# Torchlight - the items example: a key for the cave door, a stick and a cloth that make a
# torch (a recipe), and the torch used on the wall bracket to light the dark cave.
# Made by gen_examples.py: python gen_examples.py torchlight
import math, random
import art

# actors
HERO, HOPPER, BAT, STICK, DOOR, KEY, CROWN, SCONCE, CLOTH, FLAME = range(10)
# items
I_KEY, I_STICK, I_CLOTH, I_TORCH = range(4)
CAVE = (7, 15)          # the cave's colours: the Dark palette blacks them out until the torch is lit
GROUND = 210            # the ground line (painted ground colours 11 and 12)


def grid(fn, w=16, h=24):
    return ["".join(".123"[fn(x, y)] for x in range(w)) for y in range(h)]


def hero(x, y, step=False):
    rows = ["................",
            "................",
            ".....222222.....",
            "....22222222....",
            "..222222222222..",
            ".....111111.....",
            ".....121121.....",
            ".....111111.....",
            ".....112211.....",
            "......1111......",
            "....33333333....",
            "...3333333333...",
            "...1.333333.1...",
            "...1.333333.1...",
            "...1.333333.1...",
            ".....222222.....",
            ".....333333.....",
            ".....33..33.....",
            ".....22..22.....",
            ".....22..22.....",
            ".....22..22.....",
            ".....22..22.....",
            "....222..222....",
            "....222..222...."]
    if step:
        rows[18:] = ["....22....22....",
                     "....22....22....",
                     "...22......22...",
                     "...22......22...",
                     "..222......222..",
                     "..222......222.."]
    return rows[y][x]


def make_art():
    A = art.A
    A['tl_hero'] = [''.join(hero(x, y) for x in range(16)) for y in range(24)]
    A['tl_hero2'] = [''.join(hero(x, y, True) for x in range(16)) for y in range(24)]

    def stick(x, y):
        # a stick lying on the ground, a knot near one end
        k = 15 - x
        if 16 <= y <= 22 and abs((y - 16) * 2 - k) <= 1 and 1 <= x <= 14: return 1 if (x + y) % 3 else 2
        if 16 <= y <= 22 and abs((y - 16) * 2 - k) == 2 and 1 <= x <= 14: return 2
        if (x, y) == (11, 17): return 3
        return 0
    A['tl_stick'] = grid(stick)

    def key(x, y):
        # a gold key lying on its side: the ring, then the blade with two teeth
        if math.hypot(x - 4, y - 19.5) <= 3.2 and math.hypot(x - 4, y - 19.5) >= 1.5: return 1
        if (x, y) == (3, 18): return 3
        if 7 <= x <= 14 and 19 <= y <= 20: return 1 if y == 19 else 2
        if x in (11, 13) and 21 <= y <= 22: return 2
        return 0
    A['tl_key'] = grid(key)

    def door(x, y):
        # oak planks with two iron bands and a ring handle
        if x in (0, 15) or y == 0: return 2
        if y in (5, 18): return 2
        if x in (5, 10): return 2
        if (x, y) in ((11, 12), (12, 12), (11, 13), (12, 13)): return 3
        if (x * 7 + y * 3) % 11 == 0: return 3
        return 1
    A['tl_door'] = grid(door)

    def crown(x, y):
        # a gold crown on the ground: three points and a ruby
        if 19 <= y <= 22 and 2 <= x <= 13: return 2 if y == 22 or x in (2, 13) else 1
        for px in (3, 7, 8, 12):
            top = 13 if px in (7, 8) else 15
            if top <= y <= 18 and abs(x - px) <= (y - top) // 2: return 1
        if (x, y) in ((7, 20), (8, 20)): return 3
        if (x, y) in ((3, 15), (12, 15)): return 3
        return 0
    A['tl_crown'] = grid(crown)

    def sconce(x, y):
        # an iron bracket on the cave wall with an empty cup
        if 10 <= y <= 12 and 4 <= x <= 11: return 2
        if y == 13 and 5 <= x <= 10: return 2
        if 14 <= y <= 20 and 7 <= x <= 8: return 2
        if 20 <= y <= 23 and 5 <= x <= 10: return 1 if 6 <= x <= 9 and y in (21, 22) else 2
        return 0
    A['tl_sconce'] = grid(sconce)

    def bat(x, y, up=False):
        if math.hypot(x - 7.5, y - 12) <= 2.6: return 1
        if (x, y) in ((6, 11), (9, 11)): return 3
        if y in (8, 9) and x in (6, 9): return 1        # ears
        d = abs(x - 7.5)
        if 3 <= d <= 8:
            if not up and 10 + (d - 3) * 0.3 <= y <= 13 - (d - 3) * 0.4: return 2
            if up and 6 + (8 - d) * 0.5 <= y <= 9 + (8 - d) * 0.5: return 2
        return 0
    A['tl_bat'] = grid(lambda x, y: bat(x, y))
    A['tl_bat2'] = grid(lambda x, y: bat(x, y, True))

    def cloth(x, y):
        # a folded rag with a red stripe
        if 17 <= y <= 22 and 2 <= x <= 13:
            if y == 17 or y == 22 or x in (2, 13): return 2
            if y == 19: return 3
            return 1
        if y == 16 and 4 <= x <= 9: return 2
        return 0
    A['tl_cloth'] = grid(cloth)

    def flame(x, y, k=0):
        cx = 7.5 + (0.6 if k else -0.6) * max(0, (16 - y)) / 8
        r = max(0, (y - 6) * 0.45) if y < 16 else max(0, 4.5 - (y - 16) * 0.9)
        d = abs(x - cx)
        if y < 6 or y > 21 or d > r: return 0
        if d <= r * 0.35 and y > 11: return 3
        if d <= r * 0.7: return 1
        return 2
    A['tl_flame'] = grid(lambda x, y: flame(x, y))
    A['tl_flame2'] = grid(lambda x, y: flame(x, y, 1))

    def torch(x, y):
        # the torch item's picture: a stick with a burning rag
        if 11 <= y <= 23 and 7 <= x <= 8: return 1 if x == 7 else 2
        if 9 <= y <= 11 and 6 <= x <= 9: return 3
        f = flame(x, y + 4)
        if y < 9 and f: return 3
        return 0
    A['tl_torch'] = grid(torch)


def torchlight():
    import gen_examples as g
    make_art()
    pal = [0x000000, 0xffffff, 0x1c3050, 0xff9030, 0x3a3040, 0x6a5a6a, 0x9a8a90, 0x44302a,
           0x1e4a22, 0x3a8030, 0x7ac040, 0x5a3a20, 0x9a6a38, 0xc03030, 0xffe070, 0x9a7458]
    im = g.canvas(); P = im.load()
    W, H = 320, 256
    aga = g.AGA['on']
    sky = [0x181040, 0x7a3a8a, 0xffa050, 160]
    # A1200: colours that are not a blend of two backdrop colours (the sun's glow fading into
    # the copper sky) - placeholders 200.. now, given real numbers after the blends
    cust = []

    def custom(rgb):
        if rgb not in cust: cust.append(rgb)
        return 200 + cust.index(rgb)

    def sky_at(y):
        a, b, t = sky[0], sky[1], y / sky[3]
        if y > sky[3]: a, b, t = sky[1], sky[2], (y - sky[3]) / (255 - sky[3])
        return mix(a, b, t)

    def mix(a, b, t):
        return sum(int(round(((a >> s) & 255) * (1 - t) + ((b >> s) & 255) * t)) << s for s in (16, 8, 0))
    # a low sun behind the far hills, glowing into the copper dusk sky (colour 0)
    sx, sy = 70, 168
    for y in range(110, 206):
        for x in range(0, 150):
            r = math.hypot(x - sx, y - sy)
            if r <= 14: P[x, y] = 14
            elif r <= 20: P[x, y] = g.dmix(14, 3, (r - 14) / 6, x, y)
            elif r <= 40:
                t = (r - 20) / 20
                if aga:
                    # the orange rim melting into the sky colour of its band of lines (5 steps,
                    # bands of 16 lines), no dither
                    k = min(5, int(t * 6))
                    if k == 0: P[x, y] = 3
                    else: P[x, y] = custom(mix(pal[3], sky_at((y // 16) * 16 + 8), k / 6))
                else: P[x, y] = g.dmix(3, 0, t, x, y)

    def far(x): return int(176 + math.sin(x / 31) * 9 + math.sin(x / 13 + 1) * 4)
    for x in range(W):                                      # far hills, darker further down
        y0 = far(x)
        for y in range(y0, GROUND):
            P[x, y] = g.dmix(9, 8, min(1, (y - y0) / 18), x, y) if y - y0 > 1 else 9

    def cliff(x):                                           # the cliff's top: a steep face, then a ragged top
        if x < 196: return 999
        if x < 226: return int(GROUND - (x - 196) * 4.6)
        return int(64 + math.sin(x / 7) * 4 + math.sin(x / 17) * 6)
    cx0, cx1, cyt = 234, 316, 112                           # the cave: an arch from x 234 to 316, up to line 112

    def in_cave(x, y):
        u = (x - (cx0 + cx1) / 2) / ((cx1 - cx0) / 2)
        if abs(u) > 1: return False
        return y >= GROUND - (GROUND - cyt) * math.sqrt(1 - u * u) and y < GROUND
    rnd = random.Random(5)
    for x in range(W):
        top = cliff(x)
        for y in range(max(12, min(top, GROUND)), GROUND):
            if in_cave(x, y):
                # the back wall: stone blocks, lit in the middle (A1200: in-between colours of the
                # two cave colours, which the Dark palette blacks out too)
                u = abs(x - (cx0 + cx1) / 2) / ((cx1 - cx0) / 2)
                t = 0.75 - u * 0.6 - (GROUND - y) / 400
                mortar = (y % 12 == 0) or ((x + (6 if (y // 12) % 2 else 0)) % 14 == 0)
                P[x, y] = 7 if mortar else g.dmix(7, 15, max(0, min(1, t)), x, y)
            else:
                dep = (y - top) / 60
                strata = 0.12 * math.sin(y / 5 + x / 40)
                P[x, y] = g.ramp([6, 5, 4], max(0, min(1, dep * 0.6 + strata + 0.25)), x, y)
    for x in range(W):                                      # grass outside, earth everywhere below
        outside = not in_cave(x, GROUND - 1)
        if outside:
            for y in range(GROUND - 4, GROUND): P[x, y] = 10 if y < GROUND - 2 else 9
            if rnd.random() < 0.3: P[x, GROUND - 5] = 10
        for y in range(GROUND, H):
            if y < GROUND + 3: P[x, y] = 12
            elif aga:
                # A1200: the top soil darkening smoothly with depth, with soft lumps (no dots)
                lump = 0.12 * math.sin(x / 9 + y / 5) * math.sin(y / 3 - x / 13)
                P[x, y] = g.dmix(12, 11, max(0, min(1, (y - GROUND - 3) / 14 + lump)), x, y)
            else: P[x, y] = 11 if (g.bayer(x, y) + 0.5) / 64 > 0.12 else 12
    for k in range(9):                                      # tufts and stones outside
        x = rnd.randint(10, 190)
        P[x, GROUND - 6] = 10; P[x + 1, GROUND - 7] = 10
    px = list(im.getdata())
    g.text(px, "STICK + CLOTH = TORCH", 76, 228, 14)
    g.text(px, "SPACE BAR: USE AND MAKE", 68, 240, 1)
    im.putdata(px)
    solid = [0] * 128
    solid[11] = 1; solid[12] = 1

    hero_c = [0xe8b878, 0x4a2a10, 0x3c9a3c]                 # the bracket shares the hero's colour pair
    red_c = [0xc04060, 0x401020, 0xffffff]                  # hopper and bat
    wood_c = [0xb07838, 0x5a3412, 0xe0c080]                 # stick and door
    gold_c = [0xffcc30, 0x806010, 0xffffff]                 # key and crown
    cloth_c = [0xe0e0f0, 0x8080a0, 0xc03030]                # a BOB (the 9th actor): nearest backdrop colours
    flame_c = [0xffa020, 0xff4010, 0xffff80]                # a BOB too
    sprites = [("Hero", "tl_hero", hero_c), ("Hopper", "hop2", red_c), ("Bat", "tl_bat", red_c), ("Stick", "tl_stick", wood_c),
               ("Door", "tl_door", wood_c), ("Key", "tl_key", gold_c), ("Crown", "tl_crown", gold_c), ("Bracket", "tl_sconce", hero_c),
               ("Cloth", "tl_cloth", cloth_c), ("Flame", "tl_flame", flame_c),
               ("Hero walk", "tl_hero2", hero_c), ("Hopper squat", "hop", red_c), ("Bat flap", "tl_bat2", red_c), ("Flame 2", "tl_flame2", flame_c),
               ("Torch", "tl_torch", [0xb07838, 0x5a3412, 0xffa020])]
    gy = GROUND - 24
    actors = [g.actor("Hero", 0, 6, 2, 16, gy, 10, 6, True),
              g.actor("Hopper", 1, 7, 1, 140, 120, 11, 10),
              g.actor("Bat", 2, 3, 1, 282, 130, 12, 6, vis=False),
              g.actor("Stick", 3, 5, 1, 66, gy),
              g.actor("Door", 4, 5, 1, 226, gy),
              g.actor("Key", 5, 5, 1, 182, gy),
              g.actor("Crown", 6, 5, 1, 298, gy, vis=False),
              g.actor("Bracket", 7, 5, 1, 256, gy - 18),
              g.actor("Cloth", 8, 5, 1, 108, gy),
              g.actor("Flame", 9, 5, 1, 256, gy - 36, 13, 5, vis=False)]
    actors[HOPPER]['faster_every'] = 0

    def ifs(r, *lines):
        r['ifs'] = [dict(cond=c, item=i, n=n) for c, i, n in lines]
        return r
    R = g.R
    rules = []
    # getting things: a sound for each (the torch also flashes the screen)
    for it in (I_KEY, I_STICK, I_CLOTH):
        rules.append(R(when=17, n=it, act=2, value=0))
    rules += [R(when=17, n=I_TORCH, act=2, value=1), R(when=17, n=I_TORCH, act=3)]
    # the door: the key opens it (and is used up); without one the hero is sent back
    for act, tgt, val in ((6, DOOR, 0), (2, 0, 2), (0, 0, 100)):
        rules.append(ifs(R(a=HERO, b=DOOR, act=act, target=tgt, value=val), (1, I_KEY, 1)))
    for act, tgt, val in ((4, HERO, 0), (2, 0, 3)):
        rules.append(ifs(R(a=HERO, b=DOOR, act=act, target=tgt, value=val), (2, I_KEY, 1)))
    # the torch, used on the bracket, lights the cave: the main palette fades in over 1 s
    rules += [R(when=18, a=HERO, b=SCONCE, n=I_TORCH, act=27, target=50, value=0),
              R(when=18, a=HERO, b=SCONCE, n=I_TORCH, act=7, target=FLAME),
              R(when=18, a=HERO, b=SCONCE, n=I_TORCH, act=7, target=CROWN),
              R(when=18, a=HERO, b=SCONCE, n=I_TORCH, act=7, target=BAT),
              R(when=18, a=HERO, b=SCONCE, n=I_TORCH, act=0, value=200)]
    for b in (HOPPER, BAT):
        rules += [R(a=HERO, b=b, act=1), R(a=HERO, b=b, act=4, target=HERO), R(a=HERO, b=b, act=16, target=HERO), R(a=HERO, b=b, act=2, value=4)]
    rules += [R(a=HERO, b=CROWN, act=0, value=1000), R(a=HERO, b=CROWN, act=2, value=5), R(a=HERO, b=CROWN, act=10),
              R(when=6, a=HERO, act=2, value=6),
              R(when=4, act=9),
              R(when=5, act=18, value=0)]
    sfx = g.sfx_list({0: dict(name="Pick up", wave=2, pitch=72, sweep=8, len=6, atk=0, dec=5, sus=0, rel=4),
                      1: dict(name="Whoosh", wave=3, pitch=30, sweep=6, len=22, atk=2, dec=8, sus=4, rel=8, filt=9, fspeed=3, fdepth=6),
                      2: dict(name="Unlock", wave=1, pitch=50, sweep=-4, len=8, atk=0, dec=4, sus=2, rel=3),
                      3: dict(name="Locked", wave=0, pitch=20, sweep=-2, len=8, atk=0, dec=5, sus=0, rel=4),
                      4: dict(name="Ouch", wave=0, pitch=46, sweep=-1, len=26, atk=1, dec=8, sus=9, rel=7),
                      5: dict(name="Treasure", wave=2, pitch=60, sweep=12, len=30, atk=1, dec=8, sus=8, rel=8),
                      6: dict(name="Jump", wave=2, pitch=24, sweep=6, len=10, atk=0, dec=6, sus=2, rel=4)})
    tune = g.song("Cave Air", 92, [
        g.bars("Half time", 16),
        g.bars("Root pulse", 8, "Walking bass", 8),
        g.bars("Long minor", 4, "Minor to major", 4, "Long minor", 4, "Minor to major", 4),
        g.bars("", 4, "Long notes", 4, "Hook one", 2, "Long notes", 2, "Hook two", 2, "Long notes", 2)], loop_bar=4)
    p = g.make_project("Torchlight", pal, im, sprites, actors, rules, [0x181040, 0x7a3a8a, 0xffa050, 160], hud_col=1, msg_col=14,
                       sfx=sfx, songs=[tune], win="THE CROWN IS YOURS! - PRESS FIRE", over="THE CAVE WINS - PRESS FIRE")
    p['solid'] = solid
    if cust:
        # A1200: the custom colours go after the blends (16 + blends ..), placeholders replaced
        base = 16 + len(g.AGA['order'])
        assert base + len(cust) <= 128, "torchlight: too many A1200 colours (%d)" % (base + len(cust))
        for k, c in enumerate(cust): p['pal'][base + k] = c
        p['pixels'] = [base + v - 200 if v >= 200 else v for v in p['pixels']]
        print('torchlight a1200: %d blends + %d glow colours' % (len(g.AGA['order']), len(cust)))
    p.update(title_on=True, title1="TORCHLIGHT", title2="PRESS FIRE TO START")
    torch_spr = 14
    p['items'] = [dict(name="KEY", actor=KEY, spr=-1, use=0, uses=3, max=1, start=0, keep_level=True, lose_life=False),
                  dict(name="STICK", actor=STICK, spr=-1, use=0, uses=3, max=1, start=0, keep_level=True, lose_life=False),
                  dict(name="CLOTH", actor=CLOTH, spr=-1, use=0, uses=3, max=1, start=0, keep_level=True, lose_life=False),
                  dict(name="TORCH", actor=-1, spr=torch_spr, use=0, uses=3, max=1, start=0, keep_level=True, lose_life=False)]
    p['recipes'] = [dict(a=I_STICK, b=I_CLOTH, out=I_TORCH, keep_a=False, keep_b=False, n=1)]
    # the HUD: score and lives, then what the player carries (the item counts)
    g.dress_ui(p, "Wood", 0, 2, [(1, "SCORE ", 1, 0, 0xffffff, 0x101010, 5), (2, "LIVES ", 31, 0, 0xffe070, 0x101010, 1),
                                 (7, "", 1, 1, 0xffcc30, 0x101010, 1, I_KEY), (7, "", 9, 1, 0xe0c080, 0x101010, 1, I_STICK),
                                 (7, "", 19, 1, 0xe0e0f0, 0x101010, 1, I_CLOTH), (7, "", 29, 1, 0xffa020, 0x101010, 1, I_TORCH)])
    # the cave starts dark: the Dark palette blacks out the cave's colours (and on the A1200 the
    # in-between colours made from them); the torch fades the main palette back in
    dark = [-1] * 128
    for c in CAVE: dark[c] = 0x000000 if c == 7 else 0x100c0c
    if g.AGA['on']:
        for i, (a, b, k) in enumerate(g.AGA['order']):
            if a in CAVE or b in CAVE: dark[16 + i] = 0x080606
    p['palettes'] = [dict(name="Dark", cols=dark)]
    p['level_pal'] = [1] + [0] * 9
    hero_a = dict(flip=True, anims={0: ([0], 12, 0), 1: ([0, 10], 6, 0)})
    g.animate(p, "tl", {HERO: hero_a})

    def gk(r):
        if r['when'] == 17: return "Getting items"
        if r['when'] == 18: return "Lighting the cave"
        if r['when'] == 0 and r['b'] == DOOR: return "The locked door"
        if r['when'] == 0 and r['b'] in (HOPPER, BAT): return "Danger"
        if r['when'] == 0 and r['b'] == CROWN: return "Treasure"
        return "Game flow"
    p['_gk'] = gk
    return p
