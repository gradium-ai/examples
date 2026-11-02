"""Deepgram TTS over the Speak WebSocket: Aura 2 on v1/speak, Flux TTS on v2/speak.

Adapted from coval-ai/benchmarks runner/src/coval_bench/providers/tts/deepgram.py (Apache-2.0).
Deepgram names the speaker by model id (e.g. "aura-2-thalia-en", "flux-haley-en"), which goes in
the URL with the audio format, so the voice is the model. The server opens with one frame
(Metadata on v1, Connected on v2); open() drains it, like Coval does before starting its clock.
run() times Speak + Flush. v1 ends the turn with Flushed; v2 sends Flushed before the audio and
marks the end with SpeechMetadata.
"""
import asyncio
import json
from urllib.parse import urlencode

from ._util import SR, ws_connect

KEYS = ("DEEPGRAM_API_KEY",)
HOST = "api.deepgram.com"
V1 = "wss://api.deepgram.com/v1/speak"
V2 = "wss://api.deepgram.com/v2/speak"


def _speaker(L):
    return L.get("voice") or L["model"]


async def open(L, keys):
    speaker = _speaker(L)
    if not speaker.startswith(("aura-", "flux-")):
        raise RuntimeError(f"unsupported Deepgram TTS model {speaker!r}: expected aura-* or flux-*")
    flux = speaker.startswith("flux-")
    qs = urlencode({"encoding": "linear16", "sample_rate": SR, "model": speaker})
    ws = await ws_connect(f"{V2 if flux else V1}?{qs}", headers={"Authorization": f"Token {keys['DEEPGRAM_API_KEY']}"})
    try:
        raw = await asyncio.wait_for(ws.recv(), timeout=5.0)
        if isinstance(raw, str):
            m = json.loads(raw)
            if m.get("type") == "Error":
                raise RuntimeError(f"Deepgram error {m.get('code')}: {m.get('description')}")
    except BaseException:
        await ws.close()
        raise
    return {"ws": ws, "sr": SR, "final": "SpeechMetadata" if flux else "Flushed"}


async def run(lane, text, conn):
    ws = conn["ws"]
    try:
        await lane.t0()
        await ws.send(json.dumps({"type": "Speak", "text": text}))
        await ws.send(json.dumps({"type": "Flush"}))
        async for raw in ws:
            if isinstance(raw, bytes):
                await lane.audio(raw)
                continue
            m = json.loads(raw)
            t = m.get("type", "")
            if t == "Error":
                raise RuntimeError(f"Deepgram error {m.get('code')}: {m.get('description')}")
            if t == conn["final"]:
                break
    finally:
        await ws.close()
    await lane.done()
