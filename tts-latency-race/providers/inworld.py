"""Inworld TTS over its bidirectional WebSocket.

Adapted from coval-ai/benchmarks runner/src/coval_bench/providers/tts/inworld.py (Apache-2.0).
INWORLD_API_KEY is the portal-issued base64 credential; it rides the query string as
"Basic <key>" verbatim (re-encoding it fails auth). The `create` message, which picks the voice,
model and audio format, is session setup and goes out in open(); only `send_text` is timed.
"""
import json
from urllib.parse import quote

from ._util import SR, b64, ws_connect

KEYS = ("INWORLD_API_KEY",)
HOST = "api.inworld.ai"
URL = "wss://api.inworld.ai/tts/v1/voice:streamBidirectional"
CONTEXT = "race"


def _pcm(chunk):
    """Each audio chunk is a standalone WAV; keep the samples after its data header."""
    if chunk[:4] != b"RIFF":
        return chunk
    i = chunk.find(b"data")
    return chunk[i + 8:] if i != -1 else chunk


async def open(L, keys):
    ws = await ws_connect(f"{URL}?authorization={quote('Basic ' + keys['INWORLD_API_KEY'], safe='')}", max_size=None)
    await ws.send(json.dumps({"create": {"voiceId": L["voice"], "modelId": L["model"],
                                         "audioConfig": {"audioEncoding": "LINEAR16", "sampleRateHertz": SR}},
                              "contextId": CONTEXT}))
    return {"ws": ws, "sr": SR}


async def run(lane, text, conn):
    ws = conn["ws"]
    try:
        await lane.t0()
        await ws.send(json.dumps({"send_text": {"text": text, "flush_context": {}}, "contextId": CONTEXT}))
        async for raw in ws:
            if isinstance(raw, bytes):
                await lane.audio(_pcm(raw))
                continue
            m = json.loads(raw)
            if m.get("error"):
                raise RuntimeError(str(m["error"])[:200])
            result = m.get("result", {})
            audio = result.get("audioChunk", {}).get("audioContent")
            if audio:
                await lane.audio(_pcm(b64(audio)))
            elif "flushCompleted" in result:
                break
    finally:
        await ws.close()
    await lane.done()
