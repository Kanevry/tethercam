#!/usr/bin/env python3
"""IUCM-Empfaenger ueber usbmuxd, nur Python-stdlib.

Rueckfallweg fuer das echte iPhone, wenn der Swift-Wrapper um shared/usbmux.c
sich seltsam verhaelt: ListDevices -> erstes USB-Geraet (ConnectionType-Filter,
PROTOCOL.md 6.5) -> Connect auf Port 7878 mit htons (6.3), danach derselbe
Handshake wie probe_sim.py.

  usage: usbmux_recv.py [--serial UDID] [--port 7878] [--seconds 5]
                        [--dump out.hevc] [--size 1920x1080] [--fps 30]
                        [--bitrate 12000] [--list]

Exit-Code ungleich 0 bei jedem Protokoll- oder Tunnel-Fehler.
"""
import argparse
import plistlib
import socket
import struct
import sys
import time

USBMUXD_SOCKET = "/var/run/usbmuxd"
MUX_HEADER = struct.Struct("<IIII")   # length (inkl. Kopf), version, message, tag
MUX_VERSION = 1
MUX_MESSAGE_PLIST = 8

MAGIC = b"IUCM"
HEADER = struct.Struct("<4sBBHI")
HELLO, START, STOP, CONFIG, VIDEO, PING, PONG, ERROR = (
    0x01, 0x02, 0x03, 0x10, 0x11, 0x20, 0x21, 0x30)
NAMES = {HELLO: "HELLO", START: "START", STOP: "STOP", CONFIG: "CONFIG",
         VIDEO: "VIDEO", PING: "PING", PONG: "PONG", ERROR: "ERROR"}
START_CODE = b"\x00\x00\x00\x01"


class Fail(Exception):
    pass


# ---------------------------------------------------------------- usbmuxd

def _identity(d):
    d["ClientVersionString"] = "usbmux_recv.py 1.0"
    d["ProgName"] = "usbmux_recv"
    d["kLibUSBMuxVersion"] = 3
    return d


def mux_open():
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    s.settimeout(10)
    try:
        s.connect(USBMUXD_SOCKET)
    except OSError as exc:
        raise Fail("cannot connect %s: %s" % (USBMUXD_SOCKET, exc))
    return s


def mux_send(sock, payload_dict, tag):
    body = plistlib.dumps(payload_dict)
    sock.sendall(MUX_HEADER.pack(MUX_HEADER.size + len(body), MUX_VERSION,
                                 MUX_MESSAGE_PLIST, tag) + body)


def _recv_exact(sock, n):
    buf = b""
    while len(buf) < n:
        chunk = sock.recv(n - len(buf))
        if not chunk:
            raise Fail("usbmuxd closed the connection")
        buf += chunk
    return buf


def mux_recv(sock):
    length, version, message, tag = MUX_HEADER.unpack(_recv_exact(sock, MUX_HEADER.size))
    if version != MUX_VERSION or message != MUX_MESSAGE_PLIST:
        raise Fail("unexpected usbmux header: version=%d message=%d" % (version, message))
    if length < MUX_HEADER.size or length > MUX_HEADER.size + (1 << 20):
        raise Fail("implausible usbmux length %d" % length)
    return plistlib.loads(_recv_exact(sock, length - MUX_HEADER.size)), tag


def list_devices():
    """Nur ConnectionType == USB. Das Netzwerk-Duplikat desselben Telefons faellt raus."""
    sock = mux_open()
    try:
        mux_send(sock, _identity({"MessageType": "ListDevices"}), 1)
        reply, _ = mux_recv(sock)
    finally:
        sock.close()
    out = []
    for entry in reply.get("DeviceList", []):
        props = entry.get("Properties", {})
        if props.get("ConnectionType") != "USB":
            continue
        out.append((int(entry["DeviceID"]), props.get("SerialNumber", "?"),
                    props.get("ProductID")))
    return out


def mux_connect(device_id, port):
    """Port in HOST-Order uebergeben; htons passiert hier (PROTOCOL.md 6.3)."""
    sock = mux_open()
    mux_send(sock, _identity({"MessageType": "Connect",
                              "DeviceID": int(device_id),
                              "PortNumber": socket.htons(port)}), 3)
    reply, _ = mux_recv(sock)
    if reply.get("MessageType") != "Result":
        sock.close()
        raise Fail("Connect answered %r" % reply.get("MessageType"))
    number = int(reply.get("Number", -1))
    if number != 0:
        sock.close()
        hint = {2: "bad device", 3: "refused: port closed, app not listening, or wrong byte order",
                6: "bad version"}.get(number, "")
        raise Fail("Connect device %d port %d -> Number %d%s"
                   % (device_id, port, number, (" (%s)" % hint) if hint else ""))
    return sock


# ---------------------------------------------------------------- IUCM

def frame(msg_type, payload=b"", flags=0):
    return HEADER.pack(MAGIC, msg_type, flags, 0, len(payload)) + payload


class Reader:
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
                if length > 8 * 1024 * 1024:
                    raise Fail("oversize payload %d" % length)
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
    count = p[off]
    off += 1
    cams = []
    for _ in range(count):
        cid, pos = p[off], p[off + 1]
        off += 2
        cname, off = s8(off)
        cams.append((cid, "back" if pos == 0 else "front", cname))
    return version, name, app, cams


def hvcc_parameter_sets(hvcc):
    """VPS/SPS/PPS aus dem hvcC-Record. Fixteil 22 Byte, dann numOfArrays."""
    if len(hvcc) <= 22:
        raise Fail("hvcC too short (%d bytes)" % len(hvcc))
    off = 22
    array_count = hvcc[off]
    off += 1
    sets = []
    for _ in range(array_count):
        if off + 3 > len(hvcc):
            raise Fail("hvcC truncated in array header")
        off += 1  # array_completeness / reserved / NAL_unit_type
        nalu_count = (hvcc[off] << 8) | hvcc[off + 1]
        off += 2
        for _ in range(nalu_count):
            if off + 2 > len(hvcc):
                raise Fail("hvcC truncated in NAL length")
            n = (hvcc[off] << 8) | hvcc[off + 1]
            off += 2
            if off + n > len(hvcc):
                raise Fail("hvcC NAL overruns record")
            sets.append(hvcc[off:off + n])
            off += n
    if not sets:
        raise Fail("hvcC carries no parameter sets")
    return sets


def to_annexb(body):
    """4-Byte-BE-laengenpraefixiert -> Startcodes. Zaehlt die NALs mit."""
    out = bytearray()
    off = 0
    nals = 0
    while off + 4 <= len(body):
        n = struct.unpack_from(">I", body, off)[0]
        off += 4
        if n == 0 or off + n > len(body):
            raise Fail("VIDEO payload is not 4-byte-BE length prefixed")
        out += START_CODE + body[off:off + n]
        off += n
        nals += 1
    if off != len(body):
        raise Fail("VIDEO payload has %d trailing bytes" % (len(body) - off))
    return bytes(out), nals


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--serial", help="UDID; ohne Angabe das erste USB-Geraet")
    ap.add_argument("--port", type=int, default=7878)
    ap.add_argument("--seconds", type=float, default=5.0)
    ap.add_argument("--dump", help="Annex-B-HEVC mitschreiben")
    ap.add_argument("--size", default="1920x1080")
    ap.add_argument("--fps", type=int, default=30)
    ap.add_argument("--bitrate", type=int, default=12000)
    ap.add_argument("--camera", type=int, default=0)
    ap.add_argument("--list", action="store_true", help="nur USB-Geraete auflisten")
    ap.add_argument("--timeout", type=float, default=5.0, help="Wartezeit auf HELLO")
    args = ap.parse_args()

    width, _, height = args.size.lower().partition("x")
    width, height = int(width), int(height)

    devices = list_devices()
    if args.list:
        for did, serial, pid in devices:
            print("DeviceID %-5d serial %s ProductID %s" % (did, serial, pid))
        return
    if not devices:
        raise Fail("no USB device attached")
    if args.serial:
        match = [d for d in devices if d[1].lower() == args.serial.lower()]
        if not match:
            raise Fail("serial %s not found among %s" % (args.serial, [d[1] for d in devices]))
        device = match[0]
    else:
        device = devices[0]
    print("DEVICE  DeviceID %d serial %s" % (device[0], device[1]))

    sock = mux_connect(device[0], args.port)
    print("LINK    usbmux tunnel open on port %d" % args.port)
    sock.settimeout(args.timeout)
    r = Reader(sock)

    mtype, _, payload = r.next_message()
    if mtype != HELLO:
        raise Fail("expected HELLO, got %s" % NAMES.get(mtype, hex(mtype)))
    version, name, app, cams = parse_hello(payload)
    print("HELLO   version=0x%04x device=%r app=%s cameras=%s" % (version, name, app, cams))
    if version >> 8 != 1:
        raise Fail("unsupported major version %d" % (version >> 8))

    sock.sendall(frame(START, struct.pack("<BHHHI", args.camera, width, height,
                                          args.fps, args.bitrate)))
    print("START   camera=%d %dx%d@%d %d kbps" % (args.camera, width, height,
                                                  args.fps, args.bitrate))

    dump = open(args.dump, "wb") if args.dump else None
    param_sets = []
    frames = keyframes = nals = video_bytes = 0
    first_pts = last_pts = None
    config_seen = False
    deadline = None
    sock.settimeout(6.0)
    try:
        while True:
            mtype, flags, payload = r.next_message()
            if mtype == CONFIG:
                w, h, fps, hvcc_len = struct.unpack_from("<HHHI", payload, 0)
                if len(payload) != 10 + hvcc_len:
                    raise Fail("CONFIG length mismatch")
                print("CONFIG  %dx%d@%d hvcc_len=%d" % (w, h, fps, hvcc_len))
                param_sets = hvcc_parameter_sets(payload[10:])
                config_seen = True
                if deadline is None:
                    deadline = time.monotonic() + args.seconds
            elif mtype == VIDEO:
                if not config_seen:
                    raise Fail("VIDEO before CONFIG")
                pts, = struct.unpack_from("<Q", payload, 0)
                body = payload[8:]
                annexb, n = to_annexb(body)
                if last_pts is not None and pts <= last_pts:
                    raise Fail("pts not monotonic: %d after %d" % (pts, last_pts))
                first_pts = pts if first_pts is None else first_pts
                last_pts = pts
                frames += 1
                nals += n
                video_bytes += len(body)
                if flags & 0x01:
                    keyframes += 1
                if dump:
                    if flags & 0x01:
                        for s in param_sets:
                            dump.write(START_CODE + s)
                    dump.write(annexb)
                if deadline and time.monotonic() >= deadline:
                    break
            elif mtype == PONG:
                pass
            elif mtype == ERROR:
                code, tlen = struct.unpack_from("<HH", payload, 0)
                raise Fail("ERROR %d: %s" % (code, payload[4:4 + tlen].decode("utf-8")))
            else:
                raise Fail("unexpected %s during streaming" % NAMES.get(mtype, hex(mtype)))
    finally:
        if dump:
            dump.close()

    span = (last_pts - first_pts) / 1e6 if frames > 1 else 0.0
    print("VIDEO   frames=%d in %.2fs -> %.1f fps, keyframes=%d, nals=%d, %.0f kbps"
          % (frames, span, (frames - 1) / span if span else 0.0, keyframes, nals,
             video_bytes * 8 / 1000.0 / span if span else 0.0))
    sock.sendall(frame(STOP))
    print("STOP    sent")
    sock.close()
    if args.dump:
        print("DUMP    %s" % args.dump)
    print("OK")


if __name__ == "__main__":
    try:
        main()
    except Fail as exc:
        print("FAIL: %s" % exc, file=sys.stderr)
        sys.exit(1)
    except socket.timeout:
        print("FAIL: timeout waiting for the app", file=sys.stderr)
        sys.exit(1)
