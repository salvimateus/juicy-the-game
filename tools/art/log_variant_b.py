import sys
from collections import Counter
from PIL import Image

# Reduces a large RGBA illustration (alpha binarized at 128) to a pixel-art sprite TW x TH texels:
# mode per cell over a split palette (grays and warm colours quantized apart), orphan-pixel cleanup
# and a continuous dark outline. Run with python3 -I outside the project folder:
#   python3 -I log_variant_b.py <src.png> <out.png> [colors=14] [outline_max=40] [width=152] [height=56]
src, out_path = sys.argv[1], sys.argv[2]
COLORS = int(sys.argv[3]) if len(sys.argv) > 3 else 14
DARK_MAX = int(sys.argv[4]) if len(sys.argv) > 4 else 40
TW = int(sys.argv[5]) if len(sys.argv) > 5 else 152
TH = int(sys.argv[6]) if len(sys.argv) > 6 else 56
OUT = (20, 16, 19)

im = Image.open(src).convert("RGBA")
W, H = im.size
alpha = im.getchannel("A").point(lambda a: 255 if a >= 128 else 0)
bbox = alpha.getbbox()
x0, y0, x1, y1 = bbox
print("bbox", bbox)

# 1. AI pixel size and grid phase: score each (size, phase) by the colour change across the
# grid lines versus inside the cells.
rgb = im.convert("RGB")
px = rgb.load()
am = alpha.load()


def diff(a, b):
    return abs(a[0] - b[0]) + abs(a[1] - b[1]) + abs(a[2] - b[2])


cols = Counter()
for y in range(y0, y1, 5):
    for x in range(x0 + 1, x1):
        if am[x, y] and am[x - 1, y]:
            cols[x] += diff(px[x, y], px[x - 1, y])
best = None
for size10 in range(40, 200, 2):
    size = size10 / 10.0
    for ph10 in range(0, int(size * 10), 5):
        ph = ph10 / 10.0
        on = off = 0.0
        non = noff = 0
        for x, v in cols.items():
            f = (x - ph) / size
            d = abs(f - round(f))
            if d * size < 0.6:
                on += v
                non += 1
            else:
                off += v
                noff += 1
        score = (on / max(1, non)) / (off / max(1, noff) + 1e-6)
        if best is None or score > best[0]:
            best = (score, size, ph)
print("estimated AI pixel %.1f px, phase %.1f (contrast ratio %.2f)" % (best[1], best[2], best[0]))

# 2. Palette from the opaque pixels.
opaque = [px[x, y] for y in range(y0, y1, 3) for x in range(x0, x1, 3) if am[x, y]]
def _pal(pixels, n):
    img = Image.new("RGB", (len(pixels), 1))
    img.putdata(pixels)
    q = img.quantize(colors=n, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    flat = q.getpalette()[: n * 3]
    return [tuple(flat[i * 3:i * 3 + 3]) for i in range(n)]


gray = [c for c in opaque if max(c) - min(c) < 40]
warm = [c for c in opaque if max(c) - min(c) >= 40]
n_gray = max(4, COLORS * 2 // 5)
palette = _pal(gray, n_gray) + _pal(warm, COLORS - n_gray)
print("palette", ["#%02x%02x%02x" % c for c in palette])


def nearest(c):
    return min(range(len(palette)), key=lambda i: (palette[i][0] - c[0]) ** 2 + (palette[i][1] - c[1]) ** 2 + (palette[i][2] - c[2]) ** 2)


# 3. Mode per target cell (palette index), cells are (x1-x0)/(TW-2) source px wide.
sx = (x1 - x0) / (TW - 2)
sy = sx
rows = min(TH - 2, int(round((y1 - y0) / sy)))
oy = y0 - ((TH - 2) - rows) * sy / 2
grid = [[-1] * TW for _ in range(TH)]
cache = {}
for ty in range(TH - 2):
    for tx in range(TW - 2):
        cx0, cx1 = int(x0 + tx * sx), int(x0 + (tx + 1) * sx)
        cy0, cy1 = int(oy + ty * sy), int(oy + (ty + 1) * sy)
        votes = Counter()
        n = solid = 0
        for y in range(max(cy0, 0), min(cy1, H)):
            for x in range(cx0, cx1):
                n += 1
                if am[x, y]:
                    solid += 1
                    c = px[x, y]
                    k = (c[0] >> 3, c[1] >> 3, c[2] >> 3)
                    if k not in cache:
                        cache[k] = nearest(c)
                    votes[cache[k]] += 1
        if n and solid * 2 >= n:
            grid[ty + 1][tx + 1] = votes.most_common(1)[0][0]

# Near-black palette entries are the outline.
dark = {i for i, c in enumerate(palette) if max(c) < DARK_MAX}

# 4. Orphans: a pixel whose colour no 4-neighbour shares takes the majority of its 8 neighbours.
for _ in range(2):
    changed = 0
    new = [row[:] for row in grid]
    for y in range(1, TH - 1):
        for x in range(1, TW - 1):
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
                    changed += 1
    grid = new
    print("orphans fixed", changed)

# 5. Continuous outline: transparent cells touching the silhouette.
img = Image.new("RGBA", (TW, TH), (0, 0, 0, 0))
p = img.load()
for y in range(TH):
    for x in range(TW):
        c = grid[y][x]
        if c >= 0:
            p[x, y] = (OUT if c in dark else palette[c]) + (255,)
marks = []
for y in range(TH):
    for x in range(TW):
        if grid[y][x] >= 0:
            continue
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < TW and 0 <= ny < TH and grid[ny][nx] >= 0 and grid[ny][nx] not in dark:
                marks.append((x, y))
                break
for x, y in marks:
    p[x, y] = OUT + (255,)
img.save(out_path)
print("saved", out_path, img.size, "colors", len({c[:3] for c in img.getdata() if c[3]}))
