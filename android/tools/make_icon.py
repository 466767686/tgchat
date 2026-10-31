#!/usr/bin/env python3
"""Generate Android adaptive-icon foreground PNGs (calculator, transparent background)."""
import struct, zlib, os, sys

DESIGN = 108          # dp canvas for adaptive icons
SS = 4                # supersampling factor

def chunk(tag, data):
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

def write_png(path, pixels, w, h):
    raw = bytearray()
    stride = w * 4
    for y in range(h):
        raw.append(0)
        raw.extend(pixels[y * stride:(y + 1) * stride])
    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    with open(path, "wb") as f:
        f.write(png)

def render(size):
    W = H = size * SS
    k = (size / float(DESIGN)) * SS
    buf = bytearray(W * H * 4)

    def put(x, y, c):
        if 0 <= x < W and 0 <= y < H:
            i = (y * W + x) * 4
            buf[i] = c[0]; buf[i+1] = c[1]; buf[i+2] = c[2]; buf[i+3] = c[3]

    def rr(x0, y0, x1, y1, r, color):
        x0, y0, x1, y1, r = x0*k, y0*k, x1*k, y1*k, r*k
        for y in range(max(0, int(y0)), min(H, int(y1))):
            for x in range(max(0, int(x0)), min(W, int(x1))):
                cx = min(max(x, x0 + r), x1 - r)
                cy = min(max(y, y0 + r), y1 - r)
                dx, dy = x - cx, y - cy
                if dx*dx + dy*dy <= r*r:
                    put(x, y, color)

    body = (52, 52, 58, 255)
    screen = (214, 240, 200, 255)
    digit = (88, 88, 94, 255)
    func = (168, 168, 172, 255)
    op = (255, 159, 10, 255)
    seg = (30, 74, 44, 255)

    # body
    rr(26, 16, 82, 92, 8, body)

    # screen
    rr(31, 22, 77, 38, 2.5, screen)

    # "0" on the screen (rounded ring)
    rr(65, 25, 74, 35, 1.6, seg)
    rr(66.9, 26.9, 72.1, 33.1, 0.9, screen)

    # keypad 4 x 5
    left, right = 31, 77
    top, bottom = 44, 90
    gap = 2.2
    cols, rows = 4, 5
    bw = (right - left - gap * (cols - 1)) / cols
    bh = (bottom - top - gap * (rows - 1)) / rows

    colors = [
        [func, func, func, op],
        [digit, digit, digit, op],
        [digit, digit, digit, op],
        [digit, digit, digit, op],
    ]
    for r, row in enumerate(colors):
        for c, color in enumerate(row):
            x0 = left + c * (bw + gap)
            y0 = top + r * (bh + gap)
            rr(x0, y0, x0 + bw, y0 + bh, 1.6, color)

    # bottom row: wide 0, ., =
    y0 = top + 4 * (bh + gap)
    rr(left, y0, left + 2 * bw + gap, y0 + bh, 1.6, digit)
    x = left + 2 * (bw + gap)
    rr(x, y0, x + bw, y0 + bh, 1.6, digit)
    x = left + 3 * (bw + gap)
    rr(x, y0, x + bw, y0 + bh, 1.6, op)

    # downsample
    out_w = W // SS
    out = bytearray(out_w * out_w * 4)
    n = SS * SS
    for y in range(out_w):
        for x in range(out_w):
            r = g = b = a = 0
            for dy in range(SS):
                for dx in range(SS):
                    i = ((y * SS + dy) * W + (x * SS + dx)) * 4
                    r += buf[i]; g += buf[i+1]; b += buf[i+2]; a += buf[i+3]
            j = (y * out_w + x) * 4
            out[j] = r // n; out[j+1] = g // n; out[j+2] = b // n; out[j+3] = a // n
    return out, out_w

if __name__ == "__main__":
    out_dir = sys.argv[1] if len(sys.argv) > 1 else "."
    for density, px in [("mdpi", 108), ("hdpi", 162), ("xhdpi", 216), ("xxhdpi", 324), ("xxxhdpi", 432)]:
        pixels, w = render(px)
        path = os.path.join(out_dir, f"mipmap-{density}", "ic_launcher_foreground.png")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        write_png(path, pixels, w, w)
        print("wrote", path, os.path.getsize(path), "bytes")
