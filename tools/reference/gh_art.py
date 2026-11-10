# Gem Hunter's cast, drawn round and shaded (3-colour hardware sprites, 16 x 24):
# 1 = body, 2 = outline / shadow / features, 3 = highlight. Light comes from the
# upper left; the lower right of each body is dithered into shadow.
import math

def blob(x, y, cx, cy, rx, ry):
    """0 outside, 1 body, 2 rim or shadow dither, 3 highlight"""
    dx = (x - cx) / rx
    dy = (y - cy) / ry
    r = math.hypot(dx, dy)
    if r > 1.0:
        return 0
    if r > 1.0 - 1.15 / min(rx, ry):          # a one-pixel outline all round
        return 2
    nz = math.sqrt(max(0.0, 1.0 - r * r))
    lit = -dx * 0.55 - dy * 0.65 + nz * 0.5   # facing the light (upper left, a little towards us)
    if lit < -0.12 and (x + y) % 2 == 0:
        return 2                              # the shadow side, dithered
    if lit < -0.42:
        return 2
    if lit > 0.93:
        return 3                              # the shine: a small spot
    if lit > 0.80 and (x + y) % 2 == 0:
        return 3                              # ... softened round its edge
    return 1

def rows(fn):
    return ["".join(".123"[fn(x, y)] for x in range(16)) for y in range(24)]

def _leg(x, y, x0, top, foot):
    """a leg: two pixels wide from top down, then a rounded shoe on rows foot-1 .. foot"""
    if x0 <= x <= x0 + 1 and top <= y < foot - 1:
        return True
    if y == foot - 1 and x0 <= x <= x0 + 2:
        return True
    if y == foot and x0 - 1 <= x <= x0 + 2:
        return True
    return False

def hero(legs=((5, 22), (9, 22)), bob=0, blink=False, mouth='smile', top=17):
    """legs: ((x, foot row) left, (x, foot row) right); bob moves the head down"""
    def f(x, y):
        by = y - bob
        v = blob(x, by, 7.5, 9.0, 7.3, 7.3)
        if v:
            if x in (5, 6, 9, 10) and by in (6, 7, 8):          # eyes, a glint top left
                if blink:
                    return 2 if by == 8 else 1
                if by == 6:
                    return v
                if x in (5, 9) and by == 7:
                    return 3
                return 2
            if mouth == 'smile':
                if by == 12 and 6 <= x <= 9:
                    return 2
                if by == 11 and x in (5, 10):
                    return 2
            elif mouth == 'ooh':
                if by in (11, 12) and x in (7, 8):
                    return 2
            return v
        for lx, foot in legs:
            if _leg(x, y, lx, top + bob, foot):
                return 2
        return 0
    return rows(f)

def hero_frames():
    stand = hero()
    walk = [hero(legs=((4, 22), (10, 21))),                 # left foot forward... (the picture faces right)
            hero(legs=((5, 22), (9, 22)), bob=1),
            hero(legs=((6, 21), (8, 22))),
            hero(legs=((5, 22), (9, 22)), bob=1)]
    idle = [stand, hero(bob=1), stand, hero(blink=True)]
    jump = [hero(legs=((4, 20), (10, 20)), top=17, mouth='smile'),
            hero(legs=((5, 19), (9, 19)), top=17)]
    fall = [hero(legs=((3, 22), (11, 22)), mouth='ooh'),
            hero(legs=((4, 22), (10, 22)), mouth='ooh')]
    return stand, walk, idle, jump, fall

def hopper(squat=0, look=0, blink=False):
    """a red blob that crouches (squat 0..2) before it springs; look moves its eyes"""
    ry = 6.6 - squat * 1.2
    rx = 6.8 + squat * 0.6
    cy = 9.5 + squat * 2.6
    def f(x, y):
        v = blob(x, y, 7.5, cy, rx, ry)
        if v:
            ey = int(round(cy - 1.5))
            for ex in (5 + look, 9 + look):
                if ex <= x <= ex + 1 and ey - 1 <= y <= ey:
                    if blink:
                        return 2 if y == ey else 1
                    if x == ex + 1 and y == ey:
                        return 2                      # the pupil
                    return 3                          # the white of the eye
            if y == int(round(cy + 2)) and 6 <= x <= 9 and squat < 2:
                return 2                              # mouth
            return v
        foot = int(cy + ry) + 2
        if y in (foot - 1, foot) and x in (4, 5, 10, 11):
            return 2                                  # little feet
        if y == foot - 2 and x in (5, 10) and squat == 0:
            return 2
        return 0
    return rows(f)

def gem(phase=0):
    """a cut gem: a light crown, a darker pavilion; phase moves the glint"""
    def f(x, y):
        cy = 9
        if y < 5 or y > 15:
            return 0
        if y <= 7:                                    # the crown
            hw = 4 + (y - 5)
            if abs(x - 7.5) > hw:
                return 0
            if y == 5 or abs(x - 7.5) > hw - 1:
                return 2
            if y == 6 and (x == 4 + phase * 4 or x == 5 + phase * 4):
                return 3                              # the glint, moving across
            return 1
        hw = 6 - (y - 8) * 6 / 7                      # the pavilion
        if abs(x - 7.5) > hw + 0.5:
            return 0
        if abs(x - 7.5) > hw - 0.5 or y == 15:
            return 2
        if x > 7 and (x + y) % 2 == 0:
            return 2                                  # the shadowed facet
        return 1
    return rows(f)
