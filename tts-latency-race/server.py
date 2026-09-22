# /// script
# requires-python = ">=3.11"
# dependencies = ["websockets>=13", "ormsgpack>=1.5", "numpy>=1.26"]
# ///
"""TTS latency race: the same sentence fired at every streaming TTS model at the same instant.

    Gradium default            wss://api.gradium.ai/api/speech/tts      output_format pcm (48 kHz)
    Gradium beta               same socket, model gradium-tts-beta-202609
    ElevenLabs v3 conv.        wss://api.elevenlabs.io  text-to-dialogue/stream-input, pcm_24000
    ElevenLabs flash v2.5      wss://api.elevenlabs.io  text-to-speech/{voice}/stream-input, pcm_24000
    Cartesia sonic-3.6         wss://api.cartesia.ai/tts/websocket      pcm_s16le 24 kHz
    Fish Audio s2.1-pro        wss://api.fish.audio/v1/tts/live         msgpack, pcm 24 kHz

This server holds the API keys, opens every socket and sends every provider's
session setup *before* Go, then writes the text to every lane at the same
instant and relays each audio chunk to the browser with a server-side
timestamp. The page draws one waveform per lane and shows time to first audio.

One lane per model: both Gradium lanes speak with the same voice, so the only
difference between them is the model tag.

Measurement: the same methodology as Coval's public benchmarks repo,
https://github.com/coval-ai/benchmarks (docs/methodology.md), so these numbers
are comparable with theirs.

  * t0 is the text submit, taken after connect, TLS, the websocket upgrade and
    any session setup. Connect time is excluded.
  * TTFA is *perceived*: first chunk arrival minus t0, plus the leading silence
    inside the stream before the first audible 10 ms frame (1 ms hop, per-frame
    mean removed, signal edge-padded by half a frame, RMS > 0.01). The onset is
    the centre of that frame.

Usage:
    export GRADIUM_API_KEY=...       # plus ELEVENLABS_API_KEY / CARTESIA_API_KEY / FISH_API_KEY
    uv run server.py                 # then open http://127.0.0.1:8403

A lane with no key is greyed out; the race runs with whatever is configured.
The browser never sees a key.
"""
import argparse
import asyncio
import base64
import json
import os
import ssl
import sys
import threading
import time
import uuid
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

import numpy as np
import ormsgpack
import websockets
from websockets.protocol import State

HERE = Path(__file__).resolve().parent
SR = 24000                      # what ElevenLabs and Cartesia are asked for; Gradium answers at its own rate
MAX_BODY = 64 * 1024            # a sentence, not a payload
SSL_CTX = ssl.create_default_context()
STATIC = {".html": "text/html; charset=utf-8", ".css": "text/css; charset=utf-8",
          ".js": "text/javascript; charset=utf-8", ".svg": "image/svg+xml"}

LANES = {
    "gradium": {
        "label": "Gradium", "runner": "gradium", "key_env": "GRADIUM_API_KEY", "host": "api.gradium.ai",
        "model": "default",
        "voice": "4rdlkbxRv4m3UQTW",                          # Tilly, British English, from the public catalog
    },
    "gradium_beta": {
        "label": "Gradium beta", "runner": "gradium", "key_env": "GRADIUM_API_KEY", "host": "api.gradium.ai",
        "model": "gradium-tts-beta-202609",
        "model_label": "beta",                                 # same voice as the lane above, so only the model differs
        "voice": "4rdlkbxRv4m3UQTW",
    },
    "elevenlabs_v3": {
        "label": "ElevenLabs", "runner": "elevenlabs", "key_env": "ELEVENLABS_API_KEY", "host": "api.elevenlabs.io",
        "model": "eleven_v3_conversational",                   # v3 speaks the text-to-dialogue socket
        "voice": "29vD33N1CtxCmqQRPOHJ",                       # Drew
    },
    "elevenlabs_flash": {
        "label": "ElevenLabs", "runner": "elevenlabs", "key_env": "ELEVENLABS_API_KEY", "host": "api.elevenlabs.io",
        "model": "eleven_flash_v2_5",                          # flash speaks the text-to-speech stream-input socket
        "voice": "29vD33N1CtxCmqQRPOHJ",
    },
    "cartesia": {
        "label": "Cartesia", "runner": "cartesia", "key_env": "CARTESIA_API_KEY", "host": "api.cartesia.ai",
        "model": "sonic-3.6",
        "voice": "30894953-bcce-41fe-892c-15ce19c843ff",       # Parker
        "version": "2025-11-04",
    },
    "fish": {
        "label": "Fish Audio", "runner": "fish", "key_env": "FISH_API_KEY", "host": "api.fish.audio",
        "model": "s2.1-pro",
        "voice": "4501d82f5de3467ebf4d7ef095a2deee",           # Marlowe
        "latency": "low",                                      # Fish's documented lowest-latency mode
    },
}


def load_key(name):
    """Environment first, then a gitignored .env next to this file. Never hardcode a key."""
    v = os.environ.get(name)
    if v:
        return v.strip()
    env = HERE / ".env"
    if env.exists():
        for line in env.read_text().splitlines():
            line = line.strip()
            if line.startswith(f"{name}="):
                return line.split("=", 1)[1].strip().strip("'\"")
    return None


KEYS = {pid: load_key(L["key_env"]) for pid, L in LANES.items()}


RTT = {}          # host -> one TCP round trip in ms, measured once at start-up


def log(*a):
    print(*a, flush=True)


def measure_rtt():
    """The network segment of the breakdown: the floor under any lane's first chunk.
    Most providers answer from an anycast edge nearby, so it is a floor, not the path to the origin."""
    import socket
    for host in {L["host"] for L in LANES.values()}:
        try:
            ip = socket.gethostbyname(host)
            best = None
            for _ in range(3):                    # DNS is resolved, so each connect is one round trip
                t = time.perf_counter()
                socket.create_connection((ip, 443), timeout=3).close()
                best = min(best or 1e9, (time.perf_counter() - t) * 1000)
            RTT[host] = round(best, 1)
        except Exception as e:  # noqa: BLE001
            log("rtt", host, "failed:", str(e)[:80])
    log("  network rtt:", " ".join(f"{h}={v}ms" for h, v in RTT.items()))


# ---------------------------------------------------------------- one lane's clock

class Lane:
    """Timestamps one provider relative to the shared start and pushes events to the browser queue."""

    def __init__(self, pid, t_go, q, sr=SR):
        self.pid, self.t_go, self.q, self.sr = pid, t_go, q, sr
        self.t_text = self.first = self.onset = None
        self.nbytes, self.carry, self.pcm, self.scan = 0, b"", bytearray(), 0

    def now(self):
        return round((time.perf_counter() - self.t_go) * 1000)

    async def emit(self, ev, **kw):
        await self.q.put({"ev": ev, "p": self.pid, "t": self.now(), **kw})

    async def t0(self):
        self.t_text = self.now()
        await self.emit("text_sent")

    def _scan_onset(self, final=False):
        """First 10 ms frame whose mean-removed RMS exceeds 0.01, scanned as audio arrives.
        Same operations as coval's metrics/ttfa.py, on the windows not yet seen: a pure-Python
        loop here costs milliseconds per chunk, and every lane shares this event loop, so the
        wait would land on another lane's timestamp."""
        x = np.frombuffer(bytes(self.pcm), dtype="<i2").astype(np.float32) / 32768.0
        n = x.size
        if not n:
            return False
        frame = max(1, round(0.010 * self.sr))
        hop = max(1, round(0.001 * self.sr))
        pad = frame // 2
        limit = n + 2 * pad if final else n + pad    # while streaming, stop before the right pad
        last = limit - frame                         # last window start that fits
        if last < self.scan:
            return False
        padded = np.pad(x, pad, mode="edge")         # edge, not zero: a DC start must not read as a step
        win = np.lib.stride_tricks.sliding_window_view(padded, frame)[self.scan:last + 1:hop]
        rms = np.sqrt(np.mean((win - win.mean(axis=1, keepdims=True)) ** 2, axis=1))
        hit = np.flatnonzero(rms > 0.01)
        if hit.size:
            self.onset = round((self.scan + int(hit[0]) * hop) / self.sr * 1000, 1)   # the frame centre
            return True
        self.scan += ((last - self.scan) // hop) * hop + hop
        return False

    async def _landed(self):
        arrival = self.first - (self.t_text or 0)
        await self.emit("landed", ttfa=round(arrival + self.onset), arrival=arrival, silence=self.onset)

    async def audio(self, data):
        # s16le: forward whole samples only, or the page decodes the rest of the stream one byte off
        data = self.carry + data
        if len(data) % 2:
            self.carry, data = data[-1:], data[:-1]
        else:
            self.carry = b""
        if not data:
            return
        if self.first is None:
            self.first = self.now()
            await self.emit("first", arrival=self.first - (self.t_text or 0))
        if self.onset is None:
            self.pcm += data
            # off the event loop: every lane shares it, and a scan running here would delay
            # the timestamp of a chunk arriving for another lane
            if await asyncio.to_thread(self._scan_onset):
                await self._landed()
        self.nbytes += len(data)
        await self.emit("audio", b64=base64.b64encode(data).decode(), sr=self.sr)

    async def done(self):
        inaudible = None
        if self.first is not None and self.onset is None:
            if await asyncio.to_thread(self._scan_onset, True):
                await self._landed()
            else:
                # coval counts a stream that never rises above the threshold as a failure,
                # not as a very slow answer, so the lane reports no TTFA at all
                inaudible = "no audible audio in the stream"
        ttfa = None if (self.first is None or self.onset is None) else round(self.first - (self.t_text or 0) + self.onset)
        # one terminal event per lane: the run loop counts lanes by done and error
        await self.emit("done", ttfa=ttfa, seconds=round(self.nbytes / 2 / self.sr, 2), msg=inaudible)


# ---------------------------------------------------------------- sockets, opened ahead of Go

POOL = {}            # pid -> {"ws", "sr", "at"}: connected and set up, used once, fresh for its TTL
POOL_TTL = 25.0      # ElevenLabs closes an idle stream-input socket at 20 s (1008, "Have not received a new text"),
POOL_TTL_ELEVEN = 15.0                                                      # so its sockets are retired earlier
LOOP = asyncio.new_event_loop()   # one long-lived loop so pre-opened sockets survive between HTTP requests
threading.Thread(target=LOOP.run_forever, daemon=True).start()


def run_async(coro, timeout=120):
    return asyncio.run_coroutine_threadsafe(coro, LOOP).result(timeout)


async def open_lane(pid):
    """Connect and send the provider's setup so only the text remains to be sent at Go."""
    L, key = LANES[pid], KEYS[pid]
    runner = L["runner"]
    if runner == "gradium":
        ws = await websockets.connect("wss://api.gradium.ai/api/speech/tts",
                                      additional_headers={"x-api-key": key}, ssl=SSL_CTX, max_size=None)
        await ws.send(json.dumps({"type": "setup", "voice_id": L["voice"],
                                  "model_name": L["model"], "output_format": "pcm"}))
        ready = json.loads(await asyncio.wait_for(ws.recv(), 8))
        if ready.get("type") != "ready":
            await ws.close()
            raise RuntimeError(str(ready.get("message") or ready)[:120])
        return {"ws": ws, "sr": int(ready.get("sample_rate") or 48000), "at": time.perf_counter()}
    if runner == "elevenlabs":
        dialogue = L["model"].startswith("eleven_v3")
        url = (f"wss://api.elevenlabs.io/v1/text-to-dialogue/stream-input?model_id={L['model']}&output_format=pcm_{SR}"
               if dialogue else
               f"wss://api.elevenlabs.io/v1/text-to-speech/{L['voice']}/stream-input?model_id={L['model']}&output_format=pcm_{SR}")
        ws = await websockets.connect(url, additional_headers={"xi-api-key": key}, ssl=SSL_CTX)
        await ws.send(json.dumps({"voices": [L["voice"]]} if dialogue else {"text": " "}))
        return {"ws": ws, "sr": SR, "at": time.perf_counter(), "dialogue": dialogue}
    if runner == "cartesia":
        ws = await websockets.connect(
            f"wss://api.cartesia.ai/tts/websocket?api_key={key}&cartesia_version={L['version']}", ssl=SSL_CTX)
        return {"ws": ws, "sr": SR, "at": time.perf_counter()}
    if runner == "fish":
        ws = await websockets.connect("wss://api.fish.audio/v1/tts/live",
                                      additional_headers={"Authorization": f"Bearer {key}", "model": L["model"]},
                                      ssl=SSL_CTX, max_size=16 * 1024 * 1024)
        # the start frame carries the voice and the format: it is session setup, like every other
        # lane's, so it goes out before the clock rather than inside the measurement
        await ws.send(ormsgpack.packb({"event": "start", "request": {
            "text": "", "format": "pcm", "sample_rate": SR, "reference_id": L["voice"],
            "latency": L["latency"], "features": ["quality-guard"]}}))
        return {"ws": ws, "sr": SR, "at": time.perf_counter()}
    raise ValueError(pid)


def fresh(pid, c):
    """A pooled socket is usable while it is inside its provider's idle window and still open."""
    ttl = POOL_TTL_ELEVEN if LANES[pid]["runner"] == "elevenlabs" else POOL_TTL
    return c is not None and time.perf_counter() - c["at"] < ttl and c["ws"].state is State.OPEN


def take_pooled(pid):
    c = POOL.pop(pid, None)
    if fresh(pid, c):
        return c
    if c:
        asyncio.ensure_future(c["ws"].close())       # stale: the lane opens a fresh one, before its own t0
    return None


async def prewarm():
    """Open the lanes ahead of Go, so the race measures synthesis and not TCP and TLS."""
    async def one(pid):
        if fresh(pid, POOL.get(pid)):
            return
        old = POOL.pop(pid, None)
        if old:
            await old["ws"].close()
        try:
            POOL[pid] = await asyncio.wait_for(open_lane(pid), 10)
        except Exception as e:  # noqa: BLE001
            log("prewarm", pid, "failed:", str(e)[:100])
    await asyncio.gather(*(one(p) for p in LANES if KEYS.get(p)))
    return sorted(POOL)


# ---------------------------------------------------------------- the provider runners
# Each one: take the pre-opened socket -> t0 -> send the text -> stream audio back.

async def run_gradium(lane, text, conn=None):
    conn = conn or await open_lane(lane.pid)
    ws = conn["ws"]
    lane.sr = conn["sr"]
    try:
        await lane.t0()
        await ws.send(json.dumps({"type": "text", "text": text}))
        await ws.send(json.dumps({"type": "end_of_stream"}))
        async for raw in ws:
            m = json.loads(raw)
            if m.get("type") == "audio" and m.get("audio"):
                await lane.audio(base64.b64decode(m["audio"]))
            elif m.get("type") == "end_of_stream":
                break
            elif m.get("type") == "error":
                raise RuntimeError(m.get("message") or str(m))
    finally:
        await ws.close()
    await lane.done()


async def run_elevenlabs(lane, text, conn=None):
    conn = conn or await open_lane(lane.pid)
    ws = conn["ws"]
    try:
        await lane.t0()
        if conn["dialogue"]:
            await ws.send(json.dumps({"inputs": [{"text": text, "voice_id": LANES[lane.pid]["voice"]}],
                                      "close_socket": True}))
        else:
            await ws.send(json.dumps({"text": text + " "}))
            await ws.send(json.dumps({"text": ""}))      # empty frame ends the input and flushes
        async for raw in ws:
            m = json.loads(raw)
            if m.get("error"):
                raise RuntimeError(f"{m.get('error')}: {m.get('message')}")
            if m.get("audio"):
                await lane.audio(base64.b64decode(m["audio"]))
            if m.get("is_final") or m.get("isFinal"):
                break
    finally:
        await ws.close()
    await lane.done()


async def run_cartesia(lane, text, conn=None):
    conn = conn or await open_lane(lane.pid)
    ws = conn["ws"]
    L = LANES[lane.pid]
    try:
        await lane.t0()
        await ws.send(json.dumps({"model_id": L["model"], "transcript": text,
                                  "voice": {"mode": "id", "id": L["voice"]},
                                  "output_format": {"container": "raw", "encoding": "pcm_s16le", "sample_rate": SR},
                                  "language": "en", "context_id": uuid.uuid4().hex[:12], "continue": False}))
        async for raw in ws:
            m = json.loads(raw)
            if m.get("type") == "chunk" and m.get("data"):
                await lane.audio(base64.b64decode(m["data"]))
            elif m.get("type") == "done":
                break
            elif m.get("type") == "error":
                raise RuntimeError(m.get("error") or str(m))
    finally:
        await ws.close()
    await lane.done()


async def run_fish(lane, text, conn=None):
    conn = conn or await open_lane(lane.pid)
    ws = conn["ws"]
    try:
        await lane.t0()                              # the start frame went out with the setup, in open_lane
        await ws.send(ormsgpack.packb({"event": "text", "text": text}))
        await ws.send(ormsgpack.packb({"event": "stop"}))
        async for message in ws:
            if not isinstance(message, (bytes, bytearray)):
                continue
            d = ormsgpack.unpackb(bytes(message))
            if d.get("event") == "audio" and d.get("audio"):
                await lane.audio(d["audio"])
            elif d.get("event") == "finish":
                if d.get("reason") == "error":
                    raise RuntimeError(str(d.get("message", "finish reason=error")))
                break
    finally:
        await ws.close()
    await lane.done()


RUNNERS = {"gradium": run_gradium, "elevenlabs": run_elevenlabs, "cartesia": run_cartesia, "fish": run_fish}


async def race(text, emit):
    q = asyncio.Queue()
    conns = {p: take_pooled(p) for p in LANES if KEYS.get(p)}
    t_go = time.perf_counter()
    lanes = {p: Lane(p, t_go, q) for p in conns}

    async def guarded(p):
        try:
            await asyncio.wait_for(RUNNERS[LANES[p]["runner"]](lanes[p], text, conns[p]), 30)
        except Exception as e:  # noqa: BLE001 - every failure becomes a lane error
            await lanes[p].emit("error", msg=str(e)[:160] or type(e).__name__)

    tasks = [asyncio.create_task(guarded(p)) for p in lanes]
    emit({"ev": "go", "lanes": list(lanes), "prewarmed": [p for p, c in conns.items() if c]})
    pending = len(tasks)
    while pending:
        m = await q.get()
        emit(m)
        if m["ev"] in ("done", "error"):
            pending -= 1
    await asyncio.gather(*tasks, return_exceptions=True)
    emit({"ev": "end"})
    return {p: (f"{l.first - l.t_text}+{l.onset or 0}ms" if l.first is not None and l.t_text is not None else "fail")
            for p, l in lanes.items()}


class Writer:
    """NDJSON writer on its own thread: the event loop never waits on the browser's socket."""

    def __init__(self, wfile):
        import queue
        self.q, self.wfile = queue.Queue(), wfile
        self.t = threading.Thread(target=self._run, daemon=True)
        self.t.start()

    def _run(self):
        while True:
            obj = self.q.get()
            if obj is None:
                return
            try:
                self.wfile.write((json.dumps(obj) + "\n").encode())
                self.wfile.flush()
            except Exception:  # noqa: BLE001  (browser went away)
                pass

    def __call__(self, obj):
        self.q.put(obj)

    def close(self):
        self.q.put(None)
        self.t.join(5)


# ---------------------------------------------------------------- http

class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *a):
        pass

    def _send(self, code, body=b"", ctype="application/json"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/api/config":
            return self._send(200, json.dumps({"lanes": {
                pid: {"label": L["label"], "model": L.get("model_label", L["model"]),
                      "configured": bool(KEYS[pid]), "key_env": L["key_env"], "rtt_ms": RTT.get(L["host"])}
                for pid, L in LANES.items()}}).encode())
        name = "index.html" if path == "/" else path.lstrip("/")
        f = (HERE / name).resolve()
        if f.suffix not in STATIC or HERE not in f.parents or not f.is_file():
            return self._send(404, b"not found", "text/plain")
        return self._send(200, f.read_bytes(), STATIC[f.suffix])

    def do_POST(self):
        path = urlparse(self.path).path
        try:
            n = int(self.headers.get("Content-Length") or 0)
            if n > MAX_BODY:
                raise ValueError(f"body over {MAX_BODY} bytes")
            body = json.loads(self.rfile.read(n) or b"{}")
        except (ValueError, TypeError) as e:
            return self._send(400, json.dumps({"error": f"bad request body: {e}"[:160]}).encode())
        if path == "/api/prewarm":
            try:
                return self._send(200, json.dumps({"open": run_async(prewarm(), 30)}).encode())
            except Exception as e:  # noqa: BLE001
                return self._send(200, json.dumps({"open": [], "error": str(e)[:160]}).encode())
        if path != "/api/race":
            return self._send(404, b"not found", "text/plain")
        text = (body.get("text") or "").strip()
        if not text:
            return self._send(400, json.dumps({"error": "empty text"}).encode())
        if not any(KEYS.values()):
            return self._send(400, json.dumps({"error": "no API key configured"}).encode())
        self.send_response(200)
        self.send_header("Content-Type", "application/x-ndjson")
        self.send_header("Cache-Control", "no-store")
        self.send_header("Connection", "close")  # no Content-Length: the body ends when the connection does
        self.end_headers()
        w = Writer(self.wfile)
        try:
            res = run_async(race(text, w))
            log("race", " ".join(f"{p}={v}" for p, v in res.items()), "|", text[:60])
        except Exception as e:  # noqa: BLE001
            log("race error:", repr(e))
            for pid in LANES:
                if KEYS.get(pid):
                    w({"ev": "error", "p": pid, "msg": str(e)[:160]})
        finally:
            w.close()
        self.close_connection = True


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--host", default="127.0.0.1")
    ap.add_argument("--port", type=int, default=8403)
    a = ap.parse_args()
    for pid, L in LANES.items():
        log(f"  {L['label']:<14} {'key ok' if KEYS[pid] else 'NO KEY (' + L['key_env'] + ')':<28} model={L['model']}")
    if not any(KEYS.values()):
        log("\n  no keys found: set GRADIUM_API_KEY (and optionally ELEVENLABS_API_KEY, CARTESIA_API_KEY)\n")
        return 1
    if a.host not in ("127.0.0.1", "localhost", "::1"):
        log(f"\n  warning: bound to {a.host}, so anyone who can reach this port can spend your API keys\n")
    threading.Thread(target=measure_rtt, daemon=True).start()
    threading.Thread(target=lambda: run_async(prewarm(), 30), daemon=True).start()
    log(f"\n  open http://{a.host}:{a.port}\n")
    try:
        ThreadingHTTPServer((a.host, a.port), Handler).serve_forever()
    except KeyboardInterrupt:
        log("bye")
    return 0


if __name__ == "__main__":
    sys.exit(main())
