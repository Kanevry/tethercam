#!/usr/bin/env python3
"""Minimal IUCM protocol probe against a running usbcam-sim (stdlib only).

Connects, reads HELLO, sends START, reads CONFIG, counts VIDEO frames for a
few seconds, checks the PING/PONG echo and sends STOP. Exits non-zero on any
protocol violation, so it is usable as a smoke test in a script.

  usage: probe_sim.py [--host 127.0.0.1] [--port 7878] [--seconds 3]
"""
import argparse
import socket
import struct
import sys
import time

MAGIC = b"IUCM"
HEADER = struct.Struct("<4sBBHI")

HELLO, START, STOP, CONFIG, VIDEO, PING, PONG, ERROR = (
    0x01, 0x02, 0x03, 0x10, 0x11, 0x20, 0x21, 0x30)
NAMES = {HELLO: "HELLO", START: "START", STOP: "STOP", CONFIG: "CONFIG",
         VIDEO: "VIDEO", PING: "PING", PONG: "PONG", ERROR: "ERROR"}


class Fail(Exception):
    pass


def frame(msg_type, payload=b"", flags=0):
    return HEADER.pack(MAGIC, msg_type, flags, 0, len(payload)) + payload


class Reader:
    """Byte-stream framer mirroring IucmFrameParser."""

    def __init__(self, sock):
        self.sock = sock
        self.buf = bytearray()

    def _fill(self):
        chunk = self.sock.recv(65536)
        if not chunk:
            raise Fail("connection closed by sender")
        self.buf += chunk

    def next_message(self):
        while True:
            if len(self.buf) >= HEADER.size:
                magic, mtype, flags, reserved, length = HEADER.unpack_from(self.buf, 0)
                if magic != MAGIC:
                    raise Fail("bad magic %r" % magic)
                if reserved != 0:
                    raise Fail("reserved not zero: %d" % reserved)
                if len(self.buf) >= HEADER.size + length:
                    payload = bytes(self.buf[HEADER.size:HEADER.size + length])
                    del self.buf[:HEADER.size + length]
                    return mtype, flags, payload
            self._fill()


def parse_hello(p):
    version, = struct.unpack_from("<H", p, 0)
    off = 2
    def s8(off):
        n = p[off]
        return p[off + 1:off + 1 + n].decode("utf-8"), off + 1 + n
    name, off = s8(off)
    app, off = s8(off)
    count = p[off]; off += 1
    cams = []
    for _ in range(count):
        cid, pos = p[off], p[off + 1]; off += 2
        cname, off = s8(off)
        cams.append((cid, "back" if pos == 0 else "front", cname))
    if off != len(p):
        raise Fail("HELLO has %d trailing bytes" % (len(p) - off))
    return version, name, app, cams


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=7878)
    ap.add_argument("--seconds", type=float, default=3.0)
    ap.add_argument("--width", type=int, default=1280)
    ap.add_argument("--height", type=int, default=720)
    ap.add_argument("--fps", type=int, default=30)
    ap.add_argument("--bitrate", type=int, default=6000)
    args = ap.parse_args()

    sock = socket.create_connection((args.host, args.port), timeout=10)
    sock.settimeout(10)
    r = Reader(sock)

    mtype, _, payload = r.next_message()
    if mtype != HELLO:
        raise Fail("expected HELLO, got %s" % NAMES.get(mtype, hex(mtype)))
    version, name, app, cams = parse_hello(payload)
    print("HELLO   version=0x%04x device=%r app=%s cameras=%s" % (version, name, app, cams))
    if version >> 8 != 1:
        raise Fail("unsupported major version %d" % (version >> 8))

    sock.sendall(frame(START, struct.pack("<BHHHI", cams[0][0], args.width,
                                          args.height, args.fps, args.bitrate)))
    print("START   camera=%d %dx%d@%d %d kbps"
          % (cams[0][0], args.width, args.height, args.fps, args.bitrate))

    frames = keyframes = video_bytes = 0
    first_pts = last_pts = None
    config_seen = False
    deadline = None

    while True:
        mtype, flags, payload = r.next_message()
        if mtype == CONFIG:
            w, h, fps, hvcc_len = struct.unpack_from("<HHHI", payload, 0)
            if len(payload) != 10 + hvcc_len:
                raise Fail("CONFIG length mismatch")
            print("CONFIG  %dx%d@%d hvcc_len=%d" % (w, h, fps, hvcc_len))
            if (w, h, fps) != (args.width, args.height, args.fps):
                raise Fail("CONFIG format does not match START")
            config_seen = True
            deadline = time.monotonic() + args.seconds
        elif mtype == VIDEO:
            if not config_seen:
                raise Fail("VIDEO before CONFIG")
            pts, = struct.unpack_from("<Q", payload, 0)
            body = payload[8:]
            # Walk the 4-byte big-endian length prefixes to prove the framing.
            off = 0
            while off + 4 <= len(body):
                n = struct.unpack_from(">I", body, off)[0]
                off += 4 + n
            if off != len(body):
                raise Fail("VIDEO payload is not 4-byte-BE length prefixed")
            if last_pts is not None and pts <= last_pts:
                raise Fail("pts not monotonic: %d after %d" % (pts, last_pts))
            first_pts = pts if first_pts is None else first_pts
            last_pts = pts
            frames += 1
            video_bytes += len(body)
            if flags & 0x01:
                keyframes += 1
            if deadline and time.monotonic() >= deadline:
                break
        elif mtype == ERROR:
            code, tlen = struct.unpack_from("<HH", payload, 0)
            raise Fail("ERROR %d: %s" % (code, payload[4:4 + tlen].decode("utf-8")))
        else:
            raise Fail("unexpected %s during streaming" % NAMES.get(mtype, hex(mtype)))

    span = (last_pts - first_pts) / 1e6 if frames > 1 else 0.0
    print("VIDEO   frames=%d in %.2fs -> %.1f fps, keyframes=%d, %.0f kbps"
          % (frames, span, (frames - 1) / span if span else 0.0, keyframes,
             video_bytes * 8 / 1000.0 / span if span else 0.0))

    stamp = int(time.time() * 1e6)
    sock.sendall(frame(PING, struct.pack("<Q", stamp)))
    for _ in range(2000):
        mtype, _, payload = r.next_message()
        if mtype == PONG:
            echoed, = struct.unpack_from("<Q", payload, 0)
            if echoed != stamp:
                raise Fail("PONG echo mismatch: %d != %d" % (echoed, stamp))
            print("PONG    echo ok (%d)" % echoed)
            break
        if mtype not in (VIDEO, CONFIG):
            raise Fail("unexpected %s while waiting for PONG" % NAMES.get(mtype, hex(mtype)))
    else:
        raise Fail("no PONG within 2000 messages")

    sock.sendall(frame(STOP))
    print("STOP    sent")
    time.sleep(0.5)
    sock.close()
    print("OK")


if __name__ == "__main__":
    try:
        main()
    except Fail as exc:
        print("FAIL: %s" % exc, file=sys.stderr)
        sys.exit(1)
