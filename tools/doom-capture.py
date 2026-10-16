#!/usr/bin/env python3
"""Pull captured frames from a running ps5-doom title over its test socket (port 9119).

Standalone port of the receive/detile half of lowbit/ps5-doom tools/console_test.py, with the
console-side launch, upload and Payload Manager parts removed so it works against a title running
under AnyPS5 on the same machine. Frames arrive as 1920x1080 RGBA in the PS5's 512x128 tile
layout and are written as PNG; the title's doom.log arrives over the same connection at exit.

Usage: python3 -I doom-capture.py [--host 127.0.0.1] [--port 9119] [--out DIR] [--timeout 300]
Exit 0 = at least one frame or log received, 2 = could not connect, 1 = stream error.
"""
import argparse
import socket
import struct
import sys
import time
from pathlib import Path

FRAME = (1920, 1080)


def tiled_pixels(width, height):
    """Pixel count of the title's tiled scanout buffer (src/ps5/tiling.h tiled_pixels)."""
    return ((height - 1) // 128) * 128 * width + ((width - 1) // 512) * 65536 + 65536


def receive_exactly(sock, size):
    data = bytearray()
    while len(data) < size:
        chunk = sock.recv(min(1 << 20, size - len(data)))
        if not chunk:
            raise ConnectionError("capture stream ended early")
        data += chunk
    return bytes(data)


def tile_offset(x, y):
    bit = lambda v, n: (v >> n) & 1  # noqa: E731
    return (bit(x, 0) | bit(x, 1) << 1 | bit(y, 0) << 2 | bit(y, 1) << 3 | bit(y, 2) << 4 |
            bit(x, 2) << 5 | (bit(x, 3) ^ bit(y, 3)) << 6 | (bit(x, 4) ^ bit(y, 4)) << 7 |
            (bit(x, 6) ^ bit(y, 5)) << 8 | (bit(x, 5) ^ bit(y, 6)) << 9 | bit(y, 3) << 10 |
            bit(x, 4) << 11 | bit(y, 6) << 12 | bit(x, 6) << 13 | bit(x, 7) << 14 | bit(x, 8) << 15)


def detile(data):
    import numpy as np

    width, height = FRAME
    x = np.arange(width, dtype=np.int64)
    y = np.arange(height, dtype=np.int64)
    columns = (x // 512) * 65536 + tile_offset(x % 512, 0)
    rows = (y // 128) * 128 * width
    index = rows[:, None] + (columns[None, :] ^ tile_offset(0, y % 128)[:, None])
    pixels = np.frombuffer(data, dtype=np.uint32)[index]
    return pixels.astype("<u4").tobytes()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=9119)
    ap.add_argument("--out", default="captured")
    ap.add_argument("--timeout", type=int, default=300, help="seconds to keep waiting for a connection")
    args = ap.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    from PIL import Image

    deadline = time.time() + args.timeout
    sock = None
    while time.time() < deadline:
        try:
            sock = socket.create_connection((args.host, args.port), timeout=2)
            break
        except OSError:
            time.sleep(1)
    if sock is None:
        print(f"could not connect to {args.host}:{args.port} within {args.timeout}s", file=sys.stderr)
        return 2

    sock.settimeout(60)
    received = 0
    try:
        while True:
            (name_length,) = struct.unpack("<I", receive_exactly(sock, 4))
            if not name_length:
                break
            name = receive_exactly(sock, name_length).decode()
            (size,) = struct.unpack("<Q", receive_exactly(sock, 8))
            data = receive_exactly(sock, size)
            received += 1
            if name.endswith(".log"):
                (out / name).write_bytes(data)
                print(f"received {name} ({size} bytes)")
                continue
            if size != tiled_pixels(*FRAME) * 4:
                print(f"skipping {name}: {size} bytes is not a tiled {FRAME[0]}x{FRAME[1]} RGBA frame ({tiled_pixels(*FRAME) * 4})", file=sys.stderr)
                continue
            Image.frombuffer("RGBA", FRAME, detile(data), "raw", "RGBA", 0, 1).convert("RGB").save(out / f"{name}.png")
            print(f"captured {name}")
    except (OSError, ConnectionError) as e:
        print(f"capture stream interrupted: {e}", file=sys.stderr)
        return 1 if received == 0 else 0
    finally:
        sock.close()
    return 0 if received else 1


if __name__ == "__main__":
    sys.exit(main())
