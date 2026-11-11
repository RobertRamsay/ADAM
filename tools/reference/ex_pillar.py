# Pillar Run - a template (ADAM Pro) for the 'set the pillars, then cross' game: ten full-height
# columns, 32 pixels each, fill the screen edge to edge. One at a time each rises and sinks,
# easing at the ends (actor setting 'Eases in and out'); fire stops it (DO 41) and starts the
# next (IF the counter is n). When all ten stand, the hero drops onto the first and the door and
# the pick-up onto theirs; take the pick-up, then the door (IF the counter is 11). A column's
# side is a wall; down + fire (WHEN 23) costs a retry and starts the level again (DO 43).
# 8 levels, the columns faster every second one.
#
# All the pictures are placeholders at the sizes the game needs, to be replaced with your own
# (Backdrop page: Import picture, 320 x 256; Sprites page: Import PNG):
#   'Column'  32 x 256  - the whole pillar, its top edge in the first rows (the screen cuts it off)
#   'Hero' + 'Hero walk' ...  16 x 24 frames (Animate page)
#   'Door' 16 x 24, 'Pick-up' 16 x 24
# Made by gen_examples.py: python gen_examples.py pillar_run
import math
import art

N_COL = 10
COL_W = 32
COL_H = 256
TOP_LOW = 224               # a column's top at its lowest (24 lines above the HUD); it rises 112 pixels
COL_RANGE = 14              # (patrol 14 x 8)
HERO = 0
COLS = tuple(range(1, 1 + N_COL))
DOOR, PICKUP = 1 + N_COL, 2 + N_COL
PICK_COL = 4                # the pick-up comes down onto the 5th column


# rows of '.123' letters from fn(x, y) -> 0..3, w x h
def grid(fn, w=16, h=24):
    return ["".join(".123"[fn(x, y)] for x in range(w)) for y in range(h)]


# the placeholder column (32 x 256): a light top edge (pen 1), then plain blocks (pens 2 / 3)
def column(x, y):
    if y < 3: return 1
    if y == 3 or x == 0 or x == COL_W - 1: return 3
    if (y - 4) % 16 == 15: return 3                             # block joints
    if x == (8 if ((y - 4) // 16) % 2 else 24): return 3
    return 2


# the placeholder pick-up (16 x 24): a plain diamond
def pickup(x, y):
    d = abs(x - 7.5) + abs(y - 13.5)
    if d <= 5: return 3 if x < 7 and y < 13 else 1
    if d <= 6.5: return 2
    return 0


# the Pillar Run project (.adam dict), made by gen_examples.py
def pillar_run():
    import gen_examples as g
    import ex_torch, gh_art
    ex_torch.make_art()                                         # the door picture (tl_door)
    A = art.A
    stand, walk, idle, jump, fall = gh_art.hero_frames()
    A['pr_hero'] = stand
    A['pr_hero2'] = walk[0]
    A['pr_pick'] = grid(pickup)
    # placeholder colours: 0 copper sky, 1 white, 2 HUD, 3 grey, 4-6 the column's three (BOB:
    # the nearest backdrop colours), 7-8 the backdrop's
    pal = [0x000000, 0xffffff, 0x101018, 0x8890a8, 0x70b050, 0x8a6a50, 0x4a382a, 0x283048,
           0x181c2c, 0x3a4460, 0x505a78, 0x606060, 0x909090, 0xc04040, 0xffe070, 0x000000]
    im = g.canvas(); P = im.load()
    W, H = 320, 256
    for y in range(8, H):                                       # a plain placeholder backdrop
        for x in range(W):
            P[x, y] = g.dmix(7, 8, min(1, (y - 8) / 200), x, y)
            if (x % 32 == 0 or y % 32 == 8) and y < 248: P[x, y] = 9   # a 32-pixel grid: the columns
    for y in range(0, 8):
        for x in range(W): P[x, y] = 2
    for y in range(H - 8, H):
        for x in range(W): P[x, y] = 2                          # the HUD strip at the bottom
    px = list(im.getdata())
    g.text(px, "BACKDROP 320 X 256", 88, 40, 10)
    g.text(px, "IMPORT YOUR OWN ON THE BACKDROP PAGE", 16, 52, 10)
    im.putdata(px)

    col_c = [0x70b050, 0x8a6a50, 0x4a382a]
    hero_c = [0xffd23a, 0x3a2410, 0xffffff]
    door_c = [0xb07838, 0x5a3412, 0xe0c080]
    pick_c = [0xffe070, 0x806010, 0xffffff]
    sprites = [("Hero", "pr_hero", hero_c), ("Door", "tl_door", door_c), ("Pick-up", "pr_pick", pick_c),
               ("Hero walk", "pr_hero2", hero_c)]
    actors = [g.actor("Hero", 0, 6, 2, 8, 8, 3, 6, True, vis=False)]
    for k in range(N_COL):
        a = g.actor("Column %d" % (k + 1), 4, 3, 3, k * COL_W, TOP_LOW, vis=(k == 0), up=True)
        a['stand_on'] = True
        a['column'] = True                                      # full height to the floor, sides are walls
        a['ease'] = True                                        # slow at the ends, fast in the middle
        a['patrol'] = COL_RANGE
        a['faster_every'] = 2
        actors.append(a)
    # the door and the pick-up fall onto their columns when the level is set (fallers, hidden)
    actors += [g.actor("Door", 1, 8, 1, (N_COL - 1) * COL_W + 8, 8, vis=False),
               g.actor("Pick-up", 2, 8, 1, PICK_COL * COL_W + 8, 8, vis=False)]

    # rule r with an IF line: the counter is n (version 19)
    def if_count(r, n):
        r['ifs'] = [dict(kind=2, cond=0, n=n, item=0, a=0, b=1)]
        return r
    R = g.R
    rules = [R(when=7, act=41, target=HERO), R(when=7, act=2, value=5)]
    for k in range(N_COL):
        c = COLS[k]
        rules.append(if_count(R(when=1, act=41, target=c), k))
        if k + 1 < N_COL:
            rules += [if_count(R(when=1, act=7, target=COLS[k + 1]), k),
                      if_count(R(when=1, act=32), k),
                      if_count(R(when=1, act=2, value=1), k)]
        else:
            # the last column: the hero, the door and the pick-up come out (two cards)
            rules += [if_count(R(when=1, act=7, target=HERO), k),
                      if_count(R(when=1, act=42, target=HERO), k),
                      if_count(R(when=1, act=32), k),
                      if_count(R(when=1, act=2, value=2), k),
                      if_count(R(when=1, act=7, target=DOOR), k),
                      if_count(R(when=1, act=4, target=DOOR), k),
                      if_count(R(when=1, act=7, target=PICKUP), k),
                      if_count(R(when=1, act=4, target=PICKUP), k)]
    # the pick-up (the counter goes to 11), then the door
    rules += [R(a=HERO, b=PICKUP, act=6, target=PICKUP), R(a=HERO, b=PICKUP, act=32),
              R(a=HERO, b=PICKUP, act=0, value=50), R(a=HERO, b=PICKUP, act=2, value=0)]
    rules += [if_count(R(a=HERO, b=DOOR, act=0, value=100), N_COL + 1), if_count(R(a=HERO, b=DOOR, act=2, value=3), N_COL + 1),
              if_count(R(a=HERO, b=DOOR, act=17), N_COL + 1)]
    # down + fire: a retry goes and the level starts again (DO 43 last on the card)
    rules += [R(when=23, n=1, act=1), R(when=23, n=1, act=2, value=4), R(when=23, n=1, act=43)]
    rules += [R(when=6, a=HERO, act=2, value=6), R(when=4, act=9), R(when=5, act=18, value=0)]
    sfx = g.sfx_list({0: dict(name="Pick-up", wave=2, pitch=80, sweep=10, len=6, atk=0, dec=5, sus=0, rel=4),
                      1: dict(name="Stop", wave=3, pitch=40, sweep=-6, len=5, atk=0, dec=4, sus=0, rel=3),
                      2: dict(name="Go", wave=2, pitch=48, sweep=8, len=14, atk=0, dec=6, sus=4, rel=5),
                      3: dict(name="Exit", wave=2, pitch=60, sweep=12, len=24, atk=1, dec=8, sus=6, rel=8),
                      4: dict(name="Retry", wave=0, pitch=60, sweep=-6, len=24, atk=0, dec=8, sus=6, rel=8),
                      5: dict(name="Ready", wave=2, pitch=40, sweep=3, len=20, atk=2, dec=6, sus=8, rel=6),
                      6: dict(name="Jump", wave=2, pitch=24, sweep=6, len=10, atk=0, dec=6, sus=2, rel=4)})
    tune = g.song("Placeholder", 120, [
        g.bars("Rock beat", 7, "Tom fill", 1),
        g.bars("Root pulse", 4, "Walking bass", 4),
        g.bars("Long minor", 4, "Minor to major", 4),
        g.bars("", 4, "Hook one", 2, "Hook two", 2)], loop_bar=0)
    p = g.make_project("Pillar Run", pal, im, sprites, actors, rules, [0x0a0c18, 0x1a2038, 0x0a0c18, 128], hud_col=1, msg_col=14,
                       sfx=sfx, songs=[tune], win="ALL 8 LEVELS DONE! - PRESS FIRE", over="NO RETRIES LEFT - PRESS FIRE")
    p['sprites'][4] = dict(name="Column", px=[int(c) if c in '123' else 0 for r in grid(column, COL_W, COL_H) for c in r],
                           cols=col_c, w=COL_W, h=COL_H)
    p['level_song'] = [0] * 10
    levels = [dict(seed=1000 + i * 37, hilly=60, base=200, heights=[256] * 320) for i in range(8)]
    p.update(levels_on=True, levels=levels, hills_on=False, goal_on=True, goal=1, goal_label="EXIT",
             title_on=True, title1="PILLAR RUN", title2="PRESS FIRE TO START", lev_text="LEVEL")
    # ADAM Pro custom HUD: one row at the bottom - how to retry, and the retries left
    g.dress_ui(p, "Metal", 0, 1, [(0, "DOWN+FIRE TO RETRY", 1, 0, 0xffffff, None, 0),
                                  (2, "RETRIES LEFT ", 24, 0, 0xffe070, None, 2)], bottom=True)
    hero = dict(flip=True, anims={0: ([0, ("Hero breathe", idle[1]), 0, ("Hero blink", idle[3])], 14, 0),
                                  1: ([3, ("Hero walk 2", walk[1]), ("Hero walk 3", walk[2]), ("Hero walk 4", walk[3])], 5, 0),
                                  2: ([("Hero jump", jump[0]), ("Hero tuck", jump[1])], 6, 1),
                                  3: ([("Hero fall", fall[0]), ("Hero fall 2", fall[1])], 8, 2)})
    g.animate(p, "pr", {HERO: hero})

    # the Logic page group of rule r
    def gk(r):
        if r['when'] == 1: return "Setting the columns"
        if r['when'] == 7: return "Each level"
        if r['when'] == 23: return "Retry"
        if r['when'] == 0: return "Pick-up and door"
        return "Game flow"
    p['_gk'] = gk
    return p
