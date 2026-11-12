# Piston Pass - the 'set the heights, then cross' template: seven pistons - columns that reach
# the floor (actor setting 'Reaches the floor') - rise and sink in a factory pit, one at a time;
# fire stops each where it is (DO 41) and starts the next (IF the counter is n, DO 32), then the
# worker takes the joystick (DO 42) and crosses to the exit, jumping up steps (a column's side is
# a wall). Stuck? Holding fire costs a life and starts the floor again (DO 43), as does the bat.
# 8 floors, faster pistons.
# Made by gen_examples.py: python gen_examples.py piston_pass
import math, random
import art

# actors
HERO, P1, P2, P3, P4, P5, P6, P7, EXIT, COG, BAT = range(11)
PISTONS = (P1, P2, P3, P4, P5, P6, P7)
N_PISTON = len(PISTONS)
PIT_X0 = 48                 # the pit: seven shafts of 32 pixels from x 48 to 271
SHAFT = 32
LEFT_TOP = 168              # the left ledge's top (where the worker starts)
RIGHT_TOP = 148             # the right ledge's top (the exit door stands on it)
P_LOW = 216                 # a piston's top at its lowest, and how far it rises (patrol x 8 px)
P_RANGE = 12                # 96 pixels: tops from 120 to 216
SOLID = (11, 12)            # the ledges' colours: painted ground


# rows of '.123' letters from fn(x, y) -> 0..3, w x h
def grid(fn, w=16, h=24):
    return ["".join(".123"[fn(x, y)] for x in range(w)) for y in range(h)]


# the piston (32 x 32): a hazard-striped plate, a riveted block, then the column; its last row
# goes on down to the floor in the game (1 light steel, 2 dark steel, 3 yellow)
def piston(x, y):
    if y <= 1: return 1
    if y <= 5: return 3 if ((x + y) // 4) % 2 == 0 else 2
    if y <= 6: return 1
    if y <= 15:
        if x < 2 or x > 29: return 0
        if y == 15 or x == 29: return 2
        if (x, y) in ((5, 10), (26, 10)): return 3              # rivets
        if x < 11: return 1
        if x > 20: return 2
        return 1 if (x + y) % 2 == 0 else 2                     # a dithered middle
    if 4 <= x <= 27:                                            # the column, lit from the left
        if x <= 5 or x == 12: return 1
        if x >= 24 or x == 19: return 2
        if x < 12: return 1 if (x + y) % 2 == 0 or x < 9 else 2
        return 2 if (x + y) % 2 == 0 or x > 21 else 1
    return 0


# a brass cog for bonus points (16 x 24, standing on its edge in the middle)
def cog(x, y):
    cx, cy = 7.5, 12.5
    r = math.hypot(x - cx, y - cy)
    a = math.atan2(y - cy, x - cx)
    rim = 6.2 + (1.3 if math.cos(a * 8) > 0.2 else 0)          # eight teeth
    if r > rim: return 0
    if r < 2.0: return 0                                        # the hole
    if r < 3.2: return 2
    if (x - cx) + (y - cy) < -2: return 3                       # lit from the upper left
    if r > rim - 1.2: return 2
    return 1


# the Piston Pass project (.adam dict), made by gen_examples.py
def piston_pass():
    import gen_examples as g
    import ex_torch, gh_art
    ex_torch.make_art()                                         # the door and bat pictures (tl_*)
    A = art.A
    A['pp_cog'] = grid(cog)
    stand, walk, idle, jump, fall = gh_art.hero_frames()
    A['pp_hero'] = stand
    A['pp_hero2'] = walk[0]
    # 0 copper sky (dark), 1 white, 2-4 bricks, 5-7 steel, 8-10 copper, 11-12 ledges (solid), 13 red,
    # 14 yellow text, 15 the pit
    pal = [0x000000, 0xffffff, 0x3a2420, 0x6a3a2a, 0x22161a, 0x2a3038, 0x5a6670, 0xa8b4bc,
           0x6a3410, 0xb8682a, 0xf0b060, 0x404850, 0xd0a020, 0xc03020, 0xffe070, 0x080808]
    im = g.canvas(); P = im.load()
    W, H = 320, 256
    rnd = random.Random(19)
    # the brick wall: rows of bricks, each a little lighter or darker, lit from the lamp at the top
    for y in range(12, H):
        row = (y - 12) // 8
        for x in range(W):
            bx = (x + (8 if row % 2 else 0)) // 16
            if (y - 12) % 8 == 7 or (x + (8 if row % 2 else 0)) % 16 == 15:
                P[x, y] = 4
            else:
                shade = 0.35 + 0.25 * math.sin(bx * 2.3 + row * 1.7) + (y - 12) / 500
                P[x, y] = g.dmix(3, 2, max(0, min(1, shade)), x, y)
    # copper pipes: one along the wall, one down each side, with joints
    def pipe_h(y0, x0, x1):
        for x in range(x0, x1):
            for k in range(6):
                P[x, y0 + k] = [10, 9, 9, 8, 8, 4][k]
            if (x - x0) % 40 < 3:
                for k in range(-1, 7): P[x, y0 + k] = 10 if k < 2 else 8
    def pipe_v(x0, y0, y1):
        for y in range(y0, y1):
            for k in range(6):
                P[x0 + k, y] = [10, 9, 9, 8, 8, 4][k]
            if (y - y0) % 40 < 3:
                for k in range(-1, 7): P[x0 + k, y] = 10 if k < 2 else 8
    pipe_h(30, 0, W)
    pipe_v(20, 36, LEFT_TOP)
    pipe_v(290, 36, RIGHT_TOP)
    # a steam gauge on the wall
    gx, gy = 244, 92
    for y in range(gy - 18, gy + 19):
        for x in range(gx - 18, gx + 19):
            r = math.hypot(x - gx, y - gy)
            if r <= 15: P[x, y] = g.dmix(1, 7, min(1, r / 18), x, y)
            elif r <= 18: P[x, y] = 9 if (x - gx) + (y - gy) < 0 else 8
    for k in range(9):                                          # the marks, then the needle
        a = math.pi * (0.75 + k * 1.5 / 8)
        for t in (11, 12, 13): P[int(round(gx + math.cos(a) * t)), int(round(gy + math.sin(a) * t))] = 5
    for t in range(12):
        a = math.pi * 1.9
        P[int(round(gx + math.cos(a) * t)), int(round(gy + math.sin(a) * t))] = 13
    # the pit: a shaft for each piston, steel rails at its sides, dark below the floor line
    for k in range(N_PISTON):
        x0 = PIT_X0 + k * SHAFT
        for y in range(150, H):
            for x in range(x0, x0 + SHAFT):
                dep = (y - 150) / 60
                c = g.dmix(5, 15, min(1, dep), x, y)
                if x in (x0, x0 + SHAFT - 1): c = 6 if y % 12 else 7
                elif x == x0 + 1 or x == x0 + SHAFT - 2: c = 5
                P[x, y] = c
    # the ledges: a hazard-striped edge on top of riveted steel (colours 11 and 12 are ground)
    def ledge(x0, x1, top):
        for y in range(top, H):
            for x in range(x0, x1):
                if y == top: c = 12
                elif y <= top + 4: c = 12 if ((x + y) // 4) % 2 == 0 else 11
                else: c = 11
                P[x, y] = c
            if (y - top) % 16 == 10:
                for x in range(x0 + 4, x1 - 2, 10): P[x, y] = 6       # rivets (not ground: under the top)
    ledge(0, PIT_X0, LEFT_TOP)
    ledge(PIT_X0 + N_PISTON * SHAFT, W, RIGHT_TOP)
    for y in range(0, 12):
        for x in range(W): P[x, y] = 5                          # the HUD strip
    for y in range(38, 62):                                     # a dark band for the help (the
        for x in range(16, 304): P[x, y] = 4                    # columns cover the bottom)
    px = list(im.getdata())
    g.text(px, "FIRE STOPS EACH PISTON - THEN CROSS", 20, 40, 14)
    g.text(px, "STUCK? HOLD FIRE TO TRY AGAIN", 44, 52, 1)
    im.putdata(px)
    solid = [0] * 128
    for c in SOLID: solid[c] = 1

    hero_c = [0xff9a30, 0x3a2410, 0xffffff]
    piston_c = [0xa8b4bc, 0x2a3038, 0xd0a020]                  # BOBs: the nearest backdrop colours
    door_c = [0xb07838, 0x5a3412, 0xe0c080]
    cog_c = [0xd0a020, 0x6a3410, 0xffe070]
    bat_c = [0xc04060, 0x401020, 0xffffff]
    pist_px = [int(c) if c in '123' else 0 for r in grid(piston, 32, 32) for c in r]
    sprites = [("Worker", "pp_hero", hero_c), ("Exit door", "tl_door", door_c), ("Cog", "pp_cog", cog_c),
               ("Bat", "tl_bat", bat_c), ("Worker walk", "pp_hero2", hero_c), ("Bat flap", "tl_bat2", bat_c)]
    actors = [g.actor("Worker", 0, 6, 2, 14, LEFT_TOP - 24, 4, 6, True)]
    for k in range(N_PISTON):
        a = g.actor("Piston %d" % (k + 1), 6, 3, 1, PIT_X0 + k * SHAFT, P_LOW, vis=(k == 0), up=True)
        a['stand_on'] = True                                    # the worker can stand on it
        a['patrol'] = P_RANGE                                   # up 96 pixels from its lowest, and back
        a['faster_every'] = 2                                   # floors 3, 5, 7: faster
        a['column'] = True                                      # reaches the floor: its sides are walls
        actors.append(a)
    actors += [g.actor("Exit door", 1, 5, 1, 294, RIGHT_TOP - 24),
               g.actor("Cog", 2, 5, 1, PIT_X0 + 3 * SHAFT + 8, 84),
               g.actor("Bat", 3, 2, 1, 120, 92, 5, 6)]
    actors[BAT]['from_level'] = 4                               # from floor 4 a bat flits over the pit

    # rule r with an IF line: the counter is n (version 19, kind 2)
    def if_count(r, n):
        r['ifs'] = [dict(kind=2, cond=0, n=n, item=0, a=0, b=1)]
        return r
    R = g.R
    rules = []
    # the floor starts: the worker waits (stopped) while the pistons are set
    rules += [R(when=7, act=41, target=HERO), R(when=7, act=2, value=5)]
    # each fire press stops the piston that is moving (the counter says which) and starts the next
    for k in range(N_PISTON):
        rules.append(if_count(R(when=1, act=41, target=PISTONS[k]), k))
        if k + 1 < N_PISTON:
            rules.append(if_count(R(when=1, act=7, target=PISTONS[k + 1]), k))
        else:
            rules.append(if_count(R(when=1, act=42, target=HERO), k))     # the last one: off you go
        rules.append(if_count(R(when=1, act=32), k))
        rules.append(if_count(R(when=1, act=2, value=1 if k + 1 < N_PISTON else 2), k))
    # stuck (fire held 1.5 s with the stick still), a fall, or the bat: a life goes and the floor
    # starts again (DO 43 last on the card)
    rules += [R(when=8, n=15, act=1), R(when=8, n=15, act=2, value=4), R(when=8, n=15, act=43)]
    rules += [R(when=19, a=HERO, n=3, act=1), R(when=19, a=HERO, n=3, act=2, value=4), R(when=19, a=HERO, n=3, act=43)]
    rules += [R(a=HERO, b=BAT, act=1), R(a=HERO, b=BAT, act=2, value=4), R(a=HERO, b=BAT, act=43)]
    # the cog, the exit
    rules += [R(a=HERO, b=COG, act=0, value=50), R(a=HERO, b=COG, act=6, target=COG), R(a=HERO, b=COG, act=2, value=0)]
    rules += [R(a=HERO, b=EXIT, act=0, value=100), R(a=HERO, b=EXIT, act=2, value=3), R(a=HERO, b=EXIT, act=17)]
    rules += [R(when=6, a=HERO, act=2, value=6), R(when=4, act=9), R(when=5, act=18, value=0)]
    sfx = g.sfx_list({0: dict(name="Cog", wave=2, pitch=80, sweep=10, len=6, atk=0, dec=5, sus=0, rel=4),
                      1: dict(name="Clank", wave=3, pitch=40, sweep=-6, len=5, atk=0, dec=4, sus=0, rel=3),
                      2: dict(name="Go", wave=2, pitch=48, sweep=8, len=14, atk=0, dec=6, sus=4, rel=5),
                      3: dict(name="Exit", wave=2, pitch=60, sweep=12, len=24, atk=1, dec=8, sus=6, rel=8),
                      4: dict(name="Fall", wave=0, pitch=60, sweep=-6, len=24, atk=0, dec=8, sus=6, rel=8),
                      5: dict(name="Steam", wave=3, pitch=70, sweep=-2, len=18, atk=2, dec=8, sus=3, rel=7, filt=8, fspeed=4, fdepth=5),
                      6: dict(name="Jump", wave=2, pitch=24, sweep=6, len=10, atk=0, dec=6, sus=2, rel=4)})
    tune = g.song("Shift Work", 118, [
        g.bars("Four on the floor", 7, "Tom fill", 1, "Four on the floor", 7, "Tom fill", 1),
        g.bars("Offbeat bass", 8, "Walking bass", 8),
        g.bars("Long minor", 4, "Minor to major", 4, "Long minor", 4, "Minor to major", 4),
        g.bars("", 4, "Hook one", 2, "Hook two", 2, "Arp up", 2, "Arp down", 2, "Hook one", 2, "Hook two", 2)], loop_bar=0)
    p = g.make_project("Piston Pass", pal, im, sprites, actors, rules, [0x0a0a14, 0x2a1a2a, 0x100a0c, 128], hud_col=1, msg_col=14,
                       sfx=sfx, songs=[tune], win="THE FACTORY IS YOURS! - PRESS FIRE", over="THE PISTONS WIN - PRESS FIRE")
    # the piston: a 32 x 32 picture in its own sprite slot (a BOB)
    p['sprites'][6] = dict(name="Piston", px=pist_px, cols=piston_c, w=32, h=32)
    p['solid'] = solid
    p['level_song'] = [0] * 10
    levels = [dict(seed=1000 + i * 37, hilly=60, base=200, heights=[256] * 320) for i in range(8)]
    p.update(levels_on=True, levels=levels, hills_on=False, goal_on=True, goal=1, goal_label="EXIT",
             title_on=True, title1="PISTON PASS", title2="PRESS FIRE TO START", lev_text="FLOOR")
    hero = dict(flip=True, anims={0: ([0, ("Worker breathe", idle[1]), 0, ("Worker blink", idle[3])], 14, 0),
                                  1: ([4, ("Worker walk 2", walk[1]), ("Worker walk 3", walk[2]), ("Worker walk 4", walk[3])], 5, 0),
                                  2: ([("Worker jump", jump[0]), ("Worker tuck", jump[1])], 6, 1),
                                  3: ([("Worker fall", fall[0]), ("Worker fall 2", fall[1])], 8, 2)})
    g.animate(p, "pp", {HERO: hero, BAT: dict(anims={0: ([3, 5], 6, 0)})})

    # the Logic page group of rule r
    def gk(r):
        if r['when'] == 1: return "Setting the pistons"
        if r['when'] == 7: return "Each floor"
        if r['when'] in (8, 19) or (r['when'] == 0 and r['b'] == BAT): return "Stuck, falls and the bat"
        if r['when'] == 0: return "Cog and exit"
        return "Game flow"
    p['_gk'] = gk
    return p
