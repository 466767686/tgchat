#!/usr/bin/env python3
"""Generate a 1024x1024 calculator app icon (no external deps)."""
import struct, zlib, os, sys

W = H = 2048  # supersampled, downscaled to 1024
SS = 2

def chunk(tag, data):
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

def write_png(path, pixels, w, h):
    raw = bytearray()
    stride = w * 3
    for y in range(h):
        raw.append(0)
        raw.extend(pixels[y * stride:(y + 1) * stride])
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)

buf = bytearray(W * H * 3)

def put(x, y, c):
    if 0 <= x < W and 0 <= y < H:
        i = (y * W + x) * 3
        buf[i] = c[0]; buf[i+1] = c[1]; buf[i+2] = c[2]

def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

def rounded_rect(x0, y0, x1, y1, r, color):
    for y in range(max(0, int(y0)), min(H, int(y1))):
        for x in range(max(0, int(x0)), min(W, int(x1))):
            cx = min(max(x, x0 + r), x1 - r)
            cy = min(max(y, y0 + r), y1 - r)
            dx = x - cx
            dy = y - cy
            if dx * dx + dy * dy <= r * r:
                put(x, y, color)

def vertical_gradient(x0, y0, x1, y1, r, top, bottom):
    height = max(1, y1 - y0)
    for y in range(max(0, int(y0)), min(H, int(y1))):
        t = (y - y0) / height
        color = lerp(top, bottom, t)
        for x in range(max(0, int(x0)), min(W, int(x1))):
            cx = min(max(x, x0 + r), x1 - r)
            cy = min(max(y, y0 + r), y1 - r)
            dx = x - cx
            dy = y - cy
            if dx * dx + dy * dy <= r * r:
                put(x, y, color)

def segment(x, y, w, h, color):
    for yy in range(int(y), int(y + h)):
        for xx in range(int(x), int(x + w)):
            put(xx, yy, color)

# background
vertical_gradient(0, 0, W, H, 0, (36, 36, 40), (18, 18, 20))

# calculator body
body = (46, 46, 50)
vertical_gradient(280, 220, 1768, 1828, 180, (56, 56, 62), (40, 40, 45))

# screen (LCD)
screen_bg = (214, 240, 200)
rounded_rect(400, 360, 1648, 840, 60, screen_bg)

# seven-segment "0"
seg = (26, 70, 40)
sx, sy = 1648 - 90 - 250, 470
sw, sh = 250, 60   # horizontal segment size
th = 52            # thickness
# A(top) B(top-right) C(bottom-right) D(bottom) E(bottom-left) F(top-left)
segment(sx, sy, sw, th, seg)                       # A
segment(sx + sw - th, sy, th, 150, seg)            # B
segment(sx + sw - th, sy + 160, th, 150, seg)      # C
segment(sx, sy + 300, sw, th, seg)                 # D
segment(sx, sy + 160, th, 150, seg)                # E
segment(sx, sy, th, 150, seg)                      # F

# buttons: 4 columns x 5 rows (last row: wide 0, ., =)
left, right = 400, 1648
top, bottom = 920, 1730
gap = 34
bw = (right - left - gap * 3) // 4
bh = (bottom - top - gap * 4) // 5

digit = (80, 80, 80)
func = (165, 165, 165)
op = (255, 159, 10)

rows = [
    [func, func, func, op],
    [digit, digit, digit, op],
    [digit, digit, digit, op],
    [digit, digit, digit, op],
]

for r, row in enumerate(rows):
    for c, color in enumerate(row):
        x0 = left + c * (bw + gap)
        y0 = top + r * (bh + gap)
        rounded_rect(x0, y0, x0 + bw, y0 + bh, 44, color)

# last row: 0 (double), ., =
y0 = top + 4 * (bh + gap)
rounded_rect(left, y0, left + 2 * bw + gap, y0 + bh, 44, digit)
x_dot = left + 2 * (bw + gap)
rounded_rect(x_dot, y0, x_dot + bw, y0 + bh, 44, digit)
x_eq = left + 3 * (bw + gap)
rounded_rect(x_eq, y0, x_eq + bw, y0 + bh, 44, op)

# downsample 2x
out_w = W // SS
out = bytearray(out_w * out_w * 3)
for y in range(out_w):
    for x in range(out_w):
        r = g = b = 0
        for dy in range(SS):
            for dx in range(SS):
                i = ((y * SS + dy) * W + (x * SS + dx)) * 3
                r += buf[i]; g += buf[i+1]; b += buf[i+2]
        n = SS * SS
        j = (y * out_w + x) * 3
        out[j] = r // n; out[j+1] = g // n; out[j+2] = b // n

path = sys.argv[1] if len(sys.argv) > 1 else "AppIcon-1024.png"
write_png(path, out, out_w, out_w)
print("wrote", path, os.path.getsize(path), "bytes")
