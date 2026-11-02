"""Rime TTS over its /ws3 JSON WebSocket.

Adapted from coval-ai/benchmarks runner/src/coval_bench/providers/tts/rime.py (Apache-2.0).
Model, voice and audio format ride the URL, so setup is the connect itself. `segment=never` makes
Rime synthesize on the explicit end-of-stream rather than at each sentence, as Coval runs it.
"""
import json
from urllib.parse import urlencode

from ._util import b64, ws_connect

KEYS = ("RIME_API_KEY",)
HOST = "users-ws.rime.ai"
URL = "wss://users-ws.rime.ai/ws3"
RATES = {"arcana": 24000, "coda": 24000, "mistv3": 22050}   # mistv3 only runs at 22.05 kHz


async def open(L, keys):
    sr = RATES.get(L["model"], 24000)
    qs = urlencode({"modelId": L["model"], "speaker": L.get("voice") or "luna", "audioFormat": "pcm",
                    "samplingRate": sr, "segment": "never"})
    ws = await ws_connect(f"{URL}?{qs}", headers={"Authorization": f"Bearer {keys['RIME_API_KEY']}"})
    return {"ws": ws, "sr": sr}


async def run(lane, text, conn):
    ws = conn["ws"]
    try:
        await lane.t0()
        await ws.send(json.dumps({"text": text}))
        await ws.send(json.dumps({"operation": "eos"}))
        async for raw in ws:
            m = json.loads(raw)
            kind = m.get("type", "")
            if kind == "chunk":
                await lane.audio(b64(m.get("data")))
            elif kind == "done":
                break
            elif kind == "error":
                raise RuntimeError(m.get("message", "rime error"))
    finally:
        await ws.close()
    await lane.done()
