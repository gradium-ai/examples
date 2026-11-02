"""Shared helpers for provider modules: sockets, pre-warmed HTTP clients, PCM conversions."""
import base64
import ssl
import time

import httpx
import numpy as np
import websockets
from websockets.protocol import State

SR = 24000                       # what every provider is asked for when it lets us choose
SSL_CTX = ssl.create_default_context()


async def ws_connect(url, headers=None, max_size=None, **kw):
    return await websockets.connect(url, additional_headers=headers or {}, ssl=SSL_CTX if url.startswith("wss") else None,
                                    max_size=max_size, open_timeout=10, **kw)


def ws_alive(conn):
    ws = conn.get("ws")
    return ws is not None and ws.state is State.OPEN


async def http_client(base_url, headers=None, warm_path="/"):
    """An HTTP/2 client with its connection already open, like Coval's shared pre-warmed pools.

    The warm-up request only has to complete the TCP, TLS and HTTP/2 handshakes; its status
    does not matter (a 404 or 401 still leaves a live connection in the pool)."""
    client = httpx.AsyncClient(base_url=base_url, headers=headers or {}, http2=True, timeout=30.0,
                               limits=httpx.Limits(max_keepalive_connections=4, keepalive_expiry=300.0))
    try:
        await client.get(warm_path)
    except httpx.HTTPError:
        pass
    return client


def http_alive(conn):
    c = conn.get("http")
    return c is not None and not c.is_closed


def b64(s):
    return base64.b64decode(s) if s else b""


def f32_to_s16(raw):
    """float32 little-endian PCM bytes -> int16 little-endian PCM bytes."""
    x = np.frombuffer(raw, dtype="<f4")
    return (np.clip(x, -1.0, 1.0) * 32767.0).astype("<i2").tobytes()


def strip_wav_header(buf):
    """Return (pcm, sample_rate) from the start of a WAV stream, or (None, None) if the header is not complete yet."""
    if len(buf) < 12 or buf[:4] != b"RIFF":
        return buf, None
    i = 12
    sr = None
    while i + 8 <= len(buf):
        cid, size = buf[i:i + 4], int.from_bytes(buf[i + 4:i + 8], "little")
        if cid == b"fmt " and i + 16 <= len(buf):
            sr = int.from_bytes(buf[i + 12:i + 16], "little")
        if cid == b"data":
            return buf[i + 8:], sr
        i += 8 + size
    return None, None


def now():
    return time.perf_counter()
