# Shading for the examples' flat sprites: the body colour (the commonest) is lit from the
# upper left - a shine in the lightest colour, a dithered shadow in the darkest on the
# lower right. Features (eyes, stripes, outlines) are left as they are.
#   'round': blobs and balls - shaded from an ellipse round the body
#   'edge':  any shape - a lit rim at the top left, a shadow band along the bottom right
import math

def _lum(c):
    return ((c >> 16) & 255) * 0.3 + ((c >> 8) & 255) * 0.59 + (c & 255) * 0.11

def roles(s):
    """(body, dark, light) colour numbers 1..3 of sprite s"""
    cnt = [0, 0, 0, 0]
    for v in s['px']:
        if 1 <= v <= 3:
            cnt[v] += 1
    body = max((1, 2, 3), key=lambda k: cnt[k])
    others = [k for k in (1, 2, 3) if k != body]
    dark = min(others, key=lambda k: _lum(s['cols'][k - 1]))
    light = max(others, key=lambda k: _lum(s['cols'][k - 1]))
    if _lum(s['cols'][light - 1]) <= _lum(s['cols'][body - 1]):
        light = None                    # nothing lighter than the body: no shine
    if _lum(s['cols'][dark - 1]) >= _lum(s['cols'][body - 1]):
        dark = None
    return body, dark, light

def shade_sprite(s, mode='edge', body=None, dark=None, light=None, shine=True):
    w = s.get('w', 16)
    h = s.get('h', 24)
    px = list(s['px'])
    b0, d0, l0 = roles(s)
    if body is None: body = b0
    if dark is None: dark = d0
    if light is None: light = l0
    if not shine: light = None
    def at(x, y):
        if 0 <= x < w and 0 <= y < h:
            return px[y * w + x]
        return 0
    pts = [(x, y) for y in range(h) for x in range(w) if px[y * w + x] == body]
    if not pts:
        return s
    out = list(px)
    if mode == 'round':
        solid = [(x, y) for y in range(h) for x in range(w) if px[y * w + x]]
        x0 = min(p[0] for p in solid); x1 = max(p[0] for p in solid)
        y0 = min(p[1] for p in solid); y1 = max(p[1] for p in solid)
        cx = (x0 + x1) / 2; cy = (y0 + y1) / 2
        rx = max(1.0, (x1 - x0 + 1) / 2); ry = max(1.0, (y1 - y0 + 1) / 2)
        for (x, y) in pts:
            dx = (x - cx) / rx; dy = (y - cy) / ry
            r = min(1.0, math.hypot(dx, dy))
            nz = math.sqrt(max(0.0, 1.0 - r * r))
            lit = -dx * 0.55 - dy * 0.65 + nz * 0.5
            v = body
            if dark and lit < -0.42: v = dark
            elif dark and lit < -0.12 and (x + y) % 2 == 0: v = dark
            elif light and lit > 0.93: v = light
            elif light and lit > 0.80 and (x + y) % 2 == 0: v = light
            out[y * w + x] = v
    else:
        for (x, y) in pts:
            # how far it is from the edge below / to the right (the shadow side)
            dsh = 9
            for k in (1, 2, 3):
                if at(x + k, y) != body and at(x + k, y) != 0 and k == 1:
                    pass
                if at(x, y + k) == 0 or at(x + k, y) == 0 or at(x + k, y + k) == 0:
                    dsh = k
                    break
            lit_edge = at(x - 1, y) == 0 or at(x, y - 1) == 0 or at(x - 1, y - 1) == 0
            v = body
            if dark and dsh == 1:
                v = dark
            elif dark and dsh == 2 and (x + y) % 2 == 0:
                v = dark
            elif light and lit_edge and not (at(x + 1, y) == 0 and at(x, y + 1) == 0):
                v = light if (x + y) % 2 == 0 or at(x, y - 1) == 0 else body
            out[y * w + x] = v
    s2 = dict(s)
    s2['px'] = out
    return s2

def shade_actors(p, specs):
    """specs: {actor name: dict(mode, body, dark, light, shine)} - every sprite the actor
    shows (its own, its animation frames) is shaded once"""
    done = set()
    for a in p['actors']:
        sp = specs.get(a['name'])
        if sp is None:
            continue
        ids = [a['sprite']]
        if a.get('anim_sprite', -1) >= 0:
            ids.append(a['anim_sprite'])
        for an in a.get('anims', []):
            ids += an.get('frames', [])
        for i in ids:
            if i in done or not (0 <= i < len(p['sprites'])):
                continue
            done.add(i)
            p['sprites'][i] = shade_sprite(p['sprites'][i], **sp)
    return p
