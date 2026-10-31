#!/usr/bin/env python3
"""Generate small animated GIF stickers (pure stdlib, no PIL)."""
import math, os, struct

W = H = 96
PALETTE = [
    (0, 0, 0),        # 0 transparent
    (255, 255, 255),  # 1 white
    (235, 64, 82),    # 2 red
    (255, 149, 0),    # 3 orange
    (255, 214, 10),   # 4 yellow
    (52, 199, 89),    # 5 green
    (50, 160, 255),   # 6 blue
    (175, 82, 222),   # 7 purple
    (255, 105, 180),  # 8 pink
    (30, 30, 34),     # 9 dark
]


def lzw_encode(data, min_code_size):
    clear = 1 << min_code_size
    end = clear + 1
    code_size = min_code_size + 1
    next_code = end + 1
    table = {bytes([i]): i for i in range(clear)}
    out = []

    def emit(code):
        out.append(code)

    emit(clear)
    current = b""
    for byte in data:
        candidate = current + bytes([byte])
        if candidate in table:
            current = candidate
        else:
            emit(table[current])
            if next_code < 4096:
                table[candidate] = next_code
                next_code += 1
                if next_code > (1 << code_size) and code_size < 12:
                    code_size += 1
            else:
                emit(clear)
                table = {bytes([i]): i for i in range(clear)}
                code_size = min_code_size + 1
                next_code = end + 1
            current = bytes([byte])
    if current:
        emit(table[current])
    emit(end)

    # pack variable-length codes (LSB first) into bytes
    result = bytearray()
    bit_buffer = 0
    bit_count = 0
    # NOTE: code_size changes are mirrored exactly as above while packing
    code_size = min_code_size + 1
    next_code = end + 1
    table = {bytes([i]): i for i in range(clear)}
    # Re-run to know sizes at emit time: simpler approach -> build with sizes recorded
    return _pack_with_sizes(data, min_code_size)


def _pack_with_sizes(data, min_code_size):
    clear = 1 << min_code_size
    end = clear + 1
    code_size = min_code_size + 1
    next_code = end + 1
    table = {bytes([i]): i for i in range(clear)}
    codes = []

    def emit(code):
        codes.append((code, code_size))

    emit(clear)
    current = b""
    for byte in data:
        candidate = current + bytes([byte])
        if candidate in table:
            current = candidate
        else:
            emit(table[current])
            if next_code < 4096:
                table[candidate] = next_code
                next_code += 1
                if next_code > (1 << code_size) and code_size < 12:
                    code_size += 1
            else:
                emit(clear)
                table = {bytes([i]): i for i in range(clear)}
                code_size = min_code_size + 1
                next_code = end + 1
            current = bytes([byte])
    if current:
        emit(table[current])
    emit(end)

    result = bytearray()
    buffer = 0
    bits = 0
    for code, size in codes:
        buffer |= code << bits
        bits += size
        while bits >= 8:
            result.append(buffer & 0xFF)
            buffer >>= 8
            bits -= 8
    if bits > 0:
        result.append(buffer & 0xFF)
    return bytes(result)


def write_gif(path, frames, palette, delay=8, loop=0):
    # palette must be 2^n entries
    n = 1
    while n < len(palette):
        n *= 2
    palette = palette + [(0, 0, 0)] * (n - len(palette))
    bits = max(1, int(math.log2(n)))
    gct = b"".join(bytes(c) for c in palette)

    out = bytearray()
    out += b"GIF89a"
    out += struct.pack("<HHBBB", W, H, 0x80 | (bits - 1), 0, 0)  # global color table
    out += gct
    # loop extension
    out += b"\x21\xff\x0bNETSCAPE2.0" + struct.pack("<H", 1) + struct.pack("<H", loop) + b"\x00"
    for frame in frames:
        out += b"\x21\xf9\x04" + bytes([0x09, delay & 0xFF, delay >> 8, 0]) + b"\x00"
        out += b"\x2c" + struct.pack("<HHHH", 0, 0, W, H) + b"\x00"
        out += bytes([bits]) + lzw_encode(bytes(frame), bits) + b"\x00"
    out += b"\x3b"
    with open(path, "wb") as f:
        f.write(out)


def canvas():
    return bytearray([0] * (W * H))


def put(buf, x, y, color):
    if 0 <= x < W and 0 <= y < H:
        buf[y * W + x] = color


def circle(buf, cx, cy, r, color):
    for y in range(max(0, int(cy - r)), min(H, int(cy + r) + 1)):
        for x in range(max(0, int(cx - r)), min(W, int(cx + r) + 1)):
            if (x - cx) ** 2 + (y - cy) ** 2 <= r * r:
                put(buf, x, y, color)


def rect(buf, x0, y0, x1, y1, color):
    for y in range(max(0, int(y0)), min(H, int(y1))):
        for x in range(max(0, int(x0)), min(W, int(x1))):
            put(buf, x, y, color)


def polygon(buf, points, color):
    xs = [p[0] for p in points]
    ys = [p[1] for p in points]
    for y in range(max(0, int(min(ys))), min(H, int(max(ys)) + 1)):
        for x in range(max(0, int(min(xs))), min(W, int(max(xs)) + 1)):
            inside = False
            j = len(points) - 1
            for i in range(len(points)):
                xi, yi = points[i]
                xj, yj = points[j]
                if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi) + xi:
                    inside = not inside
                j = i
            if inside:
                put(buf, x, y, color)


def heart(size, color, glow=False):
    buf = canvas()
    cx, cy = W / 2, H / 2
    r = size * 10
    circle(buf, cx - r * 0.55, cy - r * 0.35, r * 0.62, color)
    circle(buf, cx + r * 0.55, cy - r * 0.35, r * 0.62, color)
    polygon(buf, [(cx - r * 1.12, cy - r * 0.12), (cx + r * 1.12, cy - r * 0.12), (cx, cy + r * 1.15)], color)
    if glow:
        circle(buf, cx, cy, r * 1.35, color)  # subtle halo
    return buf


def ball(pos):
    buf = canvas()
    circle(buf, W / 2, 28 + pos * 40, 16, 6)
    circle(buf, W / 2 - 5, 22 + pos * 40, 4, 1)
    rect(buf, 18, 88, 78, 92, 9)
    return buf


def face(blink, smile):
    buf = canvas()
    circle(buf, W / 2, H / 2, 34, 4)
    eye_y = H / 2 - 8
    if blink:
        rect(buf, W / 2 - 20, eye_y, W / 2 - 8, eye_y + 3, 9)
        rect(buf, W / 2 + 8, eye_y, W / 2 + 20, eye_y + 3, 9)
    else:
        circle(buf, W / 2 - 14, eye_y, 4, 9)
        circle(buf, W / 2 + 14, eye_y, 4, 9)
    if smile:
        for i in range(-14, 15, 2):
            y = H / 2 + 12 + int(math.sqrt(max(0, 196 - i * i)) * 0.5)
            circle(buf, W / 2 + i, y, 1.5, 9)
    else:
        rect(buf, W / 2 - 10, H / 2 + 14, W / 2 + 10, H / 2 + 17, 9)
    return buf


def star(scale, color):
    buf = canvas()
    cx, cy = W / 2, H / 2
    points = []
    for i in range(10):
        angle = -math.pi / 2 + i * math.pi / 5
        radius = (32 if i % 2 == 0 else 13) * scale
        points.append((cx + math.cos(angle) * radius, cy + math.sin(angle) * radius))
    polygon(buf, points, color)
    return buf


def dots(active):
    buf = canvas()
    for i in range(3):
        color = 6 if i == active else 9
        circle(buf, 28 + i * 20, H / 2, 8 if i == active else 6, color)
    return buf


def confetti(frame):
    buf = canvas()
    colors = [2, 3, 4, 5, 6, 7, 8]
    for i in range(14):
        x = (i * 37 + frame * 11) % W
        y = (i * 23 + frame * 17) % H
        rect(buf, x, y, x + 5, y + 7, colors[i % len(colors)])
    return buf


def main(out_dir):
    os.makedirs(out_dir, exist_ok=True)
    gifs = {
        "heart_pulse": [heart(1.0 + 0.12 * math.sin(i / 5 * math.pi), 2) for i in range(10)],
        "ball_bounce": [ball(abs(math.sin(i / 9 * math.pi))) for i in range(10)],
        "face_blink": [face(i % 10 in (4, 5), i % 10 < 8) for i in range(10)],
        "star_twinkle": [star(0.85 + 0.2 * abs(math.sin(i / 9 * math.pi)), 4) for i in range(10)],
        "dots_waiting": [dots(i % 4 if i % 4 < 3 else 0) for i in range(12)],
        "confetti_party": [confetti(i) for i in range(10)],
    }
    for name, frames in gifs.items():
        path = os.path.join(out_dir, name + ".gif")
        write_gif(path, frames, PALETTE)
        print("wrote", path, os.path.getsize(path), "bytes")


if __name__ == "__main__":
    import sys
    main(sys.argv[1] if len(sys.argv) > 1 else ".")
