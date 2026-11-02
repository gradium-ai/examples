"""AssemblyAI TTS over its OpenAI-compatible HTTP streaming speech endpoint: raw 24 kHz s16le PCM.

Adapted from coval-ai/benchmarks runner/src/coval_bench/providers/tts/assemblyai.py (Apache-2.0).
POST https://tts.us.assemblyai.com/v1/openai/audio/speech with `response_format: "pcm"`. The voice
goes in the `voice_id` extension field; OpenAI's `voice` field must be left out, or the request is
refused with a 400. Coval drives it through the OpenAI SDK; this posts the same body directly on a
pre-warmed HTTP/2 pool opened in open(), so TCP and TLS stay out of the timing.
"""
from ._util import SR, http_client

KEYS = ("ASSEMBLYAI_API_KEY",)
HOST = "tts.us.assemblyai.com"
BASE = "https://tts.us.assemblyai.com"
PATH = "/v1/openai/audio/speech"


async def open(L, keys):
    http = await http_client(BASE, {"Authorization": f"Bearer {keys['ASSEMBLYAI_API_KEY']}"}, warm_path=PATH)
    return {"http": http, "sr": SR, "model": L.get("model") or "assemblyai-tts-1",
            "voice": L.get("voice") or "aai-audrey"}


async def run(lane, text, conn):
    http = conn["http"]
    req = http.build_request("POST", PATH, json={"model": conn["model"], "input": text, "voice_id": conn["voice"],
                                                 "response_format": "pcm"})
    await lane.t0()
    r = await http.send(req, stream=True)
    try:
        if r.status_code >= 300:
            body = (await r.aread()).decode("utf-8", "replace").strip()
            raise RuntimeError(f"AssemblyAI HTTP {r.status_code}: {body[:300]}")
        async for chunk in r.aiter_bytes():
            if chunk:
                await lane.audio(chunk)
    finally:
        await r.aclose()
    await lane.done()
