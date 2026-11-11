import math
import os
from collections import Counter
from PIL import Image, ImageChops

# Reduces the off-road motorbike parts sheet (tools/art/source/moto_parts.png, an AI illustration
# with ~7 px antialiased blocks, not on a grid) to pixel-art sprites, 1 texel per art pixel:
# body, swingarm and one wheel. Mode per cell over a shared palette, alpha cut at 50%, inner
# outline, D4-symmetric wheel. Also writes 8x previews and an assembled proof to /tmp/moto_preview.
#   python3 -I tools/art/moto_parts.py
HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "source", "moto_parts.png")
OUT_DIR = os.path.join(HERE, "..", "..", "assets", "moto")
PREVIEW_DIR = "/tmp/moto_preview"
WHEEL_DIAMETER = 30
COLORS = 14
OUTLINE = (20, 16, 19)
DARK_MAX = 48
ZOOM = 8

im = Image.open(SRC).convert("RGBA")
W, H = im.size
rgb = im.convert("RGB")
alpha = im.getchannel("A").point(lambda a: 255 if a >= 128 else 0)


# 1. Parts are the alpha connected components; each one is picked by a point inside its bbox.
def components():
    a = alpha.tobytes()
    seen = bytearray(W * H)
    labels = {}
    comps = []
    for i in range(W * H):
        if a[i] and not seen[i]:
            seen[i] = 1
            stack = [i]
            members = []
            while stack:
                j = stack.pop()
                members.append(j)
                x = j % W
                for k in (j - 1 if x > 0 else -1, j + 1 if x < W - 1 else -1, j - W, j + W):
                    if 0 <= k < W * H and a[k] and not seen[k]:
                        seen[k] = 1
                        stack.append(k)
            xs = [m % W for m in members]
            ys = [m // W for m in members]
            comps.append(((min(xs), min(ys), max(xs) + 1, max(ys) + 1), members))
    return comps


COMPS = components()


def part_mask(px, py):
    for bbox, members in COMPS:
        x0, y0, x1, y1 = bbox
        if x0 <= px < x1 and y0 <= py < y1 and len(members) > 20000:
            mask = bytearray(W * H)
            for m in members:
                mask[m] = 255
            return bbox, Image.frombytes("L", (W, H), bytes(mask))
    raise SystemExit("part not found at %d,%d" % (px, py))


BODY_BBOX, BODY_MASK = part_mask(600, 300)
ARM_BBOX, ARM_MASK = part_mask(550, 740)
WHEEL_BBOX, WHEEL_MASK = part_mask(1550, 635)  # right-hand wheel: the cleaner, rounder one
print("body", BODY_BBOX, "swingarm", ARM_BBOX, "wheel", WHEEL_BBOX)

# 2. Scale: the wheel spans exactly WHEEL_DIAMETER art pixels.
wx0, wy0, wx1, wy1 = WHEEL_BBOX
SCALE = max(wx1 - wx0, wy1 - wy0) / WHEEL_DIAMETER
print("scale %.3f source px per art px" % SCALE)

# 3. Palette from the opaque pixels of the three parts, outline colour forced in.
union = Image.new("L", (W, H), 0)
for m in (BODY_MASK, ARM_MASK, WHEEL_MASK):
    union.paste(255, (0, 0), m)
up = union.load()
rp = rgb.load()
opaque = [rp[x, y] for y in range(0, H, 2) for x in range(0, W, 2) if up[x, y]]
opaque = [c for c in opaque if max(c) >= DARK_MAX]


def is_gold(c):
    return c[0] > 140 and c[2] < 100 and 0.6 * c[0] < c[1] < 0.85 * c[0]


def median_cut(pixels, n):
    img = Image.new("RGB", (len(pixels), 1))
    img.putdata(pixels)
    q = img.quantize(colors=n, method=Image.Quantize.MEDIANCUT, kmeans=4, dither=Image.Dither.NONE)
    flat = q.getpalette()[: n * 3]
    return [tuple(flat[i * 3:i * 3 + 3]) for i in range(n)]


# The gold fork is a small area that a global cut would merge into the orange, so it gets its own.
N_GOLD = 2
palette = median_cut([c for c in opaque if is_gold(c)], N_GOLD)
palette += median_cut([c for c in opaque if not is_gold(c)], COLORS - 1 - N_GOLD) + [OUTLINE]
palette.sort(key=lambda c: (c != OUTLINE, sum(c)))
DARK = {i for i, c in enumerate(palette) if max(c) < DARK_MAX}
print("palette", ["#%02x%02x%02x" % c for c in palette])

pal_img = Image.new("P", (1, 1))
pal_img.putpalette([v for c in palette for v in c] + [0] * (768 - 3 * len(palette)))
INDEX = rgb.quantize(palette=pal_img, dither=Image.Dither.NONE)
INDEX_L = Image.frombytes("L", (W, H), INDEX.tobytes())


def coverage(mask, ox, oy, cols, rows):
    """Fraction (0..255) of each art cell covered by mask; cell (0,0) starts at source (ox, oy)."""
    box = (ox, oy, ox + cols * SCALE, oy + rows * SCALE)
    return list(mask.resize((cols, rows), Image.BOX, box=box).getdata())


def class_masks(mask):
    return [ImageChops.multiply(INDEX_L.point([255 if i == k else 0 for i in range(256)]), mask)
            for k in range(len(palette))]


def reduce(mask, bbox, ox=None, oy=None, cols=None, rows=None):
    x0, y0, x1, y1 = bbox
    cols = cols or int(math.ceil((x1 - x0) / SCALE)) + 2
    rows = rows or int(math.ceil((y1 - y0) / SCALE)) + 2
    cms = class_masks(mask)
    if ox is None:
        # Grid phase that maximizes colour uniformity per cell.
        best = None
        steps = 6
        for i in range(steps):
            for j in range(steps):
                px_ = x0 - SCALE + SCALE * i / steps
                py_ = y0 - SCALE + SCALE * j / steps
                covs = [coverage(m, px_, py_, cols, rows) for m in cms]
                score = sum(max(c) for c in zip(*covs) if max(c) > 0)
                tot = sum(sum(c) for c in zip(*covs))
                s = score / max(1, tot)
                if best is None or s > best[0]:
                    best = (s, px_, py_)
        _, ox, oy = best
        print("  phase uniformity %.3f at origin (%.2f, %.2f)" % best)
    covs = [coverage(m, ox, oy, cols, rows) for m in cms]
    acov = coverage(mask, ox, oy, cols, rows)
    grid = [[-1] * cols for _ in range(rows)]
    for n, cell in enumerate(zip(*covs)):
        if acov[n] > 127:
            grid[n // cols][n % cols] = max(range(len(cell)), key=lambda k: cell[k])
    return grid, ox, oy


def clean_orphans(grid):
    rows, cols = len(grid), len(grid[0])
    new = [r[:] for r in grid]
    for y in range(1, rows - 1):
        for x in range(1, cols - 1):
            c = grid[y][x]
            if c < 0:
                continue
            n4 = [grid[y + dy][x + dx] for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))]
            if c in n4:
                continue
            n8 = Counter(grid[y + dy][x + dx] for dx in (-1, 0, 1) for dy in (-1, 0, 1) if dx or dy)
            n8.pop(-1, None)
            if n8:
                maj, cnt = n8.most_common(1)[0]
                if cnt >= 3:
                    new[y][x] = maj
    return new


def outline(grid):
    """Inner 1 px outline: opaque cells touching transparency become the outline colour."""
    rows, cols = len(grid), len(grid[0])
    o = palette.index(OUTLINE)
    new = [r[:] for r in grid]
    for y in range(rows):
        for x in range(cols):
            if grid[y][x] < 0 or grid[y][x] in DARK:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if not (0 <= nx < cols and 0 <= ny < rows) or grid[ny][nx] < 0:
                    new[y][x] = o
                    break
    # Dark source tones collapse into the single outline colour.
    return [[o if c in DARK else c for c in r] for r in new]


def to_image(grid):
    rows, cols = len(grid), len(grid[0])
    img = Image.new("RGBA", (cols, rows), (0, 0, 0, 0))
    p = img.load()
    for y in range(rows):
        for x in range(cols):
            if grid[y][x] >= 0:
                p[x, y] = palette[grid[y][x]] + (255,)
    return img


def crop(img, ox, oy):
    bb = img.getchannel("A").getbbox()
    return img.crop(bb), (ox + bb[0] * SCALE, oy + bb[1] * SCALE)


def art(src_pt, origin):
    """Source px -> art px in a cropped sprite whose top-left texel corner is at origin."""
    return ((src_pt[0] - origin[0]) / SCALE, (src_pt[1] - origin[1]) / SCALE)


# 4. Body and swingarm.
print("body")
g, ox, oy = reduce(BODY_MASK, BODY_BBOX)
body, body_org = crop(to_image(outline(clean_orphans(clean_orphans(g)))), ox, oy)
print("swingarm")
g, ox, oy = reduce(ARM_MASK, ARM_BBOX)
arm_ox, arm_oy = ox, oy
g = outline(clean_orphans(g))
# The eye holes fall below one art pixel; punch them back as single outline texels.
ARM_HOLES = {"pivot_eye": (717, 750), "axle_eye": (394, 788), "shock_eye": (689, 690)}
for hx, hy in ARM_HOLES.values():
    g[int((hy - oy) / SCALE)][int((hx - ox) / SCALE)] = palette.index(OUTLINE)
arm, arm_org = crop(to_image(g), ox, oy)

# 5. Wheel: centre on the hub, 30x30 grid with the axle on the corner shared by the 4 middle
# texels, then D4 symmetrized (mode over each 8-texel orbit) so it spins cleanly.
hub = [(x, y) for y in range(wy0, wy1) for x in range(wx0, wx1)
       if WHEEL_MASK.getpixel((x, y)) and rp[x, y][0] > 180 and rp[x, y][2] < 90]
wcx = sum(p[0] for p in hub) / len(hub)
wcy = sum(p[1] for p in hub) / len(hub)
print("wheel hub centre (%.1f, %.1f)" % (wcx, wcy))
N = WHEEL_DIAMETER
half = N / 2
g, ox, oy = reduce(WHEEL_MASK, WHEEL_BBOX, wcx - half * SCALE, wcy - half * SCALE, N, N)
sym = [[-1] * N for _ in range(N)]
for y in range(N):
    for x in range(N):
        orbit = set()
        for a, b in ((x, y), (y, x)):
            for fa, fb in ((a, b), (N - 1 - a, b), (a, N - 1 - b), (N - 1 - a, N - 1 - b)):
                orbit.add((fa, fb))
        votes = Counter(g[b][a] for a, b in orbit)
        best = max(votes.values())
        # Ties keep the darker/transparent choice for a crisper silhouette.
        sym[y][x] = min((c for c, v in votes.items() if v == best), key=lambda c: (c >= 0, sum(palette[c]) if c >= 0 else 0))
sym = outline(sym)

# The thin source spokes do not survive the reduction, so the rim, spokes and hub inside the tyre
# are redrawn geometrically around the axle (still D4 symmetric).
def pal_index(hex_):
    c = tuple(int(hex_[i:i + 2], 16) for i in (1, 3, 5))
    return min(range(len(palette)), key=lambda k: sum((a - b) ** 2 for a, b in zip(palette[k], c)))


RIM, SPOKE, HUB = pal_index("#aca3b2"), pal_index("#766779"), pal_index("#f95f03")
O = palette.index(OUTLINE)
RIM_R = (9.0, 10.05)
SPOKE_ANGLES = [math.radians(22.5 + 45 * k) for k in range(8)]
for y in range(N):
    for x in range(N):
        u, v = x + 0.5 - half, y + 0.5 - half
        r = math.hypot(u, v)
        if r >= RIM_R[1]:
            continue
        if r >= RIM_R[0]:
            c = RIM
        elif r < 1.0:
            c = O
        elif r < 3.2:
            c = HUB
        else:
            c = O
            for a in SPOKE_ANGLES:
                along = u * math.cos(a) + v * math.sin(a)
                across = -u * math.sin(a) + v * math.cos(a)
                if along > 0 and abs(across) < 0.42:
                    c = SPOKE
        sym[y][x] = c
wheel = to_image(sym)
assert wheel.getchannel("A").getbbox() == (0, 0, N, N), wheel.getchannel("A").getbbox()

os.makedirs(OUT_DIR, exist_ok=True)
os.makedirs(PREVIEW_DIR, exist_ok=True)
for name, img in (("moto_body", body), ("moto_swingarm", arm), ("moto_wheel", wheel)):
    img.save(os.path.join(OUT_DIR, name + ".png"))
    img.resize((img.width * ZOOM, img.height * ZOOM), Image.NEAREST).save(os.path.join(PREVIEW_DIR, name + "_8x.png"))
    print("saved", name, img.size)

# 6. Anchors (source estimates mapped to art px) and an assembled proof.
BODY_SRC = {
    "front_axle": (975, 548),
    "swingarm_pivot": (555, 560),
    "rear_axle": (230, 548),
}
body_a = {k: art(v, body_org) for k, v in BODY_SRC.items()}
# Read off the reduced sprite (art px, texel edges / centres).
body_a.update({
    "footpeg": (33.5, 39.5),
    "grip": (53.5, 3.5),
    "seat_top": (38.5, 15.0),
    "center_of_mass": (45.5, 33.5),
    "crash_bar_top": (58.5, 0.0),
    "crash_seat_rear": (19.5, 14.0),
    "crash_tail": (0.0, 15.0),
    "crash_front": (91.0, 22.0),
})


def eye(src):
    """Centre of the hole texel punched at a source point."""
    tx = int((src[0] - arm_ox) / SCALE)
    ty = int((src[1] - arm_oy) / SCALE)
    return (tx + 0.5 - (arm_org[0] - arm_ox) / SCALE, ty + 0.5 - (arm_org[1] - arm_oy) / SCALE)


arm_a = {k: eye(v) for k, v in ARM_HOLES.items()}
print("body crop origin (%.2f, %.2f) source px" % body_org)
for k, v in body_a.items():
    print("body", k, "(%.2f, %.2f)" % v)
for k, v in arm_a.items():
    print("swingarm", k, "(%.2f, %.2f)" % v)
print("wheel centre (%.1f, %.1f)" % (half, half))
print("wheelbase %.2f art px" % math.dist(body_a["front_axle"], body_a["rear_axle"]))

# Snap the measured frame points, then put the rear axle exactly one swingarm length from the pivot
# along the measured direction, so the mounted arm's axle eye lands on it.
body_a["front_axle"] = (75.5, 40.0)
body_a["swingarm_pivot"] = (41.5, 40.5)
ape, aae = arm_a["pivot_eye"], arm_a["axle_eye"]
piv, est = body_a["swingarm_pivot"], body_a["rear_axle"]
k = math.dist(ape, aae) / math.dist(piv, est)
ax = body_a["rear_axle"] = (piv[0] + (est[0] - piv[0]) * k, piv[1] + (est[1] - piv[1]) * k)
print("body rear_axle (mounted) (%.2f, %.2f)" % ax)
print("wheelbase (mounted) %.2f art px" % math.dist(body_a["front_axle"], ax))
ang_body = math.atan2(ax[1] - piv[1], ax[0] - piv[0])
ang_arm = math.atan2(aae[1] - ape[1], aae[0] - ape[0])
rest = math.degrees(ang_body - ang_arm)
rest = (rest + 180) % 360 - 180
print("swingarm rest angle %.2f deg (clockwise, y down)" % rest)
print("arm length %.2f, body pivot->axle %.2f" % (math.dist(ape, aae), math.dist(piv, ax)))

PZ = ZOOM
margin = 20
proof = Image.new("RGBA", (body.width + 2 * margin, body.height + 2 * margin), (110, 170, 120, 255))
r = math.radians(rest)
cos_r, sin_r = math.cos(r), math.sin(r)
# Rotate the pivot eye position to find where to paste the rotated arm.
# PIL's expand=True rotates about the image centre; recompute by transforming the eye.
cx, cy = arm.width / 2, arm.height / 2
dx, dy = ape[0] - cx, ape[1] - cy
rx, ry = dx * cos_r - dy * sin_r, dx * sin_r + dy * cos_r
arm_rot = arm.rotate(-rest, resample=Image.NEAREST, expand=True)
eye_rot = (arm_rot.width / 2 + rx, arm_rot.height / 2 + ry)
layer = Image.new("RGBA", proof.size, (0, 0, 0, 0))
for axle in (body_a["front_axle"], ax):
    layer.alpha_composite(wheel, (int(round(margin + axle[0] - half)), int(round(margin + axle[1] - half))))
layer.alpha_composite(arm_rot, (int(round(margin + piv[0] - eye_rot[0])), int(round(margin + piv[1] - eye_rot[1]))))
proof.alpha_composite(layer)
proof.alpha_composite(body, (margin, margin))
mark = proof.load()
for k, v in body_a.items():
    x, y = int(margin + v[0]), int(margin + v[1])
    if 0 <= x < proof.width and 0 <= y < proof.height:
        mark[x, y] = (0, 255, 255, 255)
proof.resize((proof.width * PZ, proof.height * PZ), Image.NEAREST).save(os.path.join(PREVIEW_DIR, "moto_assembled_8x.png"))
print("saved proof")
