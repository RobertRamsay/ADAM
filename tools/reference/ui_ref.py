# Custom HUD (ADAM Pro UI editor) - the same rules as scr_ws_ui.gml:
# font styles, panel frame presets (9-slice, 24 x 24 = 3 x 3 cells of 8 x 8),
# the panel picture (backdrop strip with the frame baked in) and the field records.
import re, os, struct
HERE = os.path.dirname(os.path.abspath(__file__))
FONT = [int(v, 16) for v in re.findall(r'\$([0-9a-f]{2})', open(os.path.join(HERE, '..', '..', 'datafiles', 'engine', 'font.inc')).read())]
FONT_STYLES = ["ADAM", "Bold", "Thin", "Italic", "Bold italic", "Custom"]
FRAME_STYLES = ["Metal", "Wood", "Stone", "Neon", "Parchment", "Window"]
FIELD_TYPES = ["Text", "Score", "Lives", "Goal", "Tile carried", "Level"]

def font_bytes(ui):
    st = ui.get('font_style', 0)
    if st == 5 and len(ui.get('font', [])) == 512: return list(ui['font'])
    out = []
    for c in range(64):
        for i in range(8):
            r = FONT[c * 8 + i]
            if st in (1, 4): r = (r | (r >> 1)) & 255
            if st == 2: r = r & ~(r >> 1) & 255
            if st in (3, 4):
                if i < 3: r = r >> 1
                elif i >= 5: r = (r << 1) & 255
            out.append(r)
    return out

def frame_rgb(style, x, y):
    """colour of frame pixel (x, y) of the 24 x 24 template, or None = see-through"""
    d = min(x, y, 23 - x, 23 - y)
    lt = min(x, y) <= min(23 - x, 23 - y)          # top / left side: the lit bevel
    mx, my = x % 8, y % 8
    if style == "Metal":
        if d == 0: return 0x202430
        if d == 1: return 0xd0d8e8 if lt else 0x404858
        if x in (4, 19) and y in (4, 19): return 0xe8f0ff
        if x in (5, 20) and y in (5, 20): return 0x303440
        return 0x687080 if (mx + my) % 4 else 0x5c6474
    if style == "Wood":
        if d == 0: return 0x301808
        if d == 1: return 0xb07840 if lt else 0x583018
        return 0x6a3c1c if (my * 3 + mx // 3) % 7 == 0 else 0x8a5228
    if style == "Stone":
        if d == 0: return 0x282830
        if d == 1: return 0x9c9ca8 if lt else 0x48484f
        off = 4 if (y // 4) % 2 else 0
        if y % 4 == 3 or (mx + off) % 8 == 7: return 0x4a4a52
        return 0x7a7a84
    if style == "Neon":
        if d == 0: return 0xc020d0
        if d == 2: return 0x40f0ff
        return 0x100820
    if style == "Parchment":
        if d <= 1: return 0x704018
        if d == 2: return 0xa07040
        return 0xd4c08c if (x * 7 + y * 13) % 11 == 0 else 0xecdcaa
    if style == "Window":
        if d == 0: return 0xffffff
        if d == 1: return 0x6080b0
        return None
    return None

def pal_nearest(pal, rgb, ncol):
    best, bd = 1, -1
    r, g, b = (rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255
    for c in range(1, ncol):
        q = pal[c]
        dd = (((q >> 16) & 255) - r) ** 2 * 3 + (((q >> 8) & 255) - g) ** 2 * 4 + ((q & 255) - b) ** 2 * 2
        if bd < 0 or dd < bd: bd, best = dd, c
    return best

def frame_preset(style, pal, ncol):
    out = []
    for y in range(24):
        for x in range(24):
            c = frame_rgb(style, x, y)
            out.append(0 if c is None else pal_nearest(pal, c, ncol))
    return out

def panel_pixels(ui, pixels):
    """the HUD strip: the backdrop's rows with the 9-slice frame on top (0 in the frame = backdrop)"""
    rows = ui['rows']; h = rows * 8
    row0 = (32 - rows) if ui.get('bottom') else 0
    out = list(pixels[row0 * 8 * 320:(row0 * 8 + h) * 320])
    if not ui.get('frame_on', True): return out
    fr = ui['frame']
    for y in range(h):
        if h >= 16:
            fy = y if y < 8 else (16 + y - (h - 8) if y >= h - 8 else 8 + (y - 8) % 8)
        else:
            fy = 8 + y
        for x in range(320):
            fx = x if x < 8 else (16 + x - 312 if x >= 312 else 8 + (x - 8) % 8)
            v = fr[fy * 24 + fx]
            if v: out[y * 320 + x] = v
    return out

def field_bytes(f):
    lab = f.get('label', '').upper().encode('ascii', 'replace')[:19]
    sh = f.get('shadow', -1)
    return struct.pack('>hhhhhh', f['type'], f['col'], f['row'], f['colour'], sh if sh >= 0 else -1, f.get('digits', 5)) + lab + b'\0' * (20 - len(lab))
