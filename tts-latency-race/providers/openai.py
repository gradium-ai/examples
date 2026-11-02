"""OpenAI TTS over HTTP streaming: POST /v1/audio/speech, raw 24 kHz s16le PCM.

Written from OpenAI's docs (https://developers.openai.com/api/docs/guides/text-to-speech and the
/v1/audio/speech reference); Coval's runner no longer ships an OpenAI TTS client. The docs' latency
advice is followed: `response_format: "pcm"` (headerless 24 kHz 16-bit mono, the fastest format) and
a chunked streaming response, so playback can start before generation finishes. The stream_format
default ("audio", raw bytes) is kept; SSE would add base64 and JSON framing.

The connection pool is opened and warmed in open(), like Coval's shared HTTP/2 pools, so TCP and TLS
stay out of the measurement. OpenAI has announced that tts-1, tts-1-hd and gpt-4o-mini-tts shut
down on 2027-01-06 (their replacement, gpt-realtime-2.1-mini, is Realtime-API only).
"""
from ._util import SR, http_client

KEYS = ("OPENAI_API_KEY",)
HOST = "api.openai.com"
BASE = "https://api.openai.com"
PATH = "/v1/audio/speech"


async def open(L, keys):
    http = await http_client(BASE, {"Authorization": f"Bearer {keys['OPENAI_API_KEY']}"}, warm_path="/v1/models")
    return {"http": http, "sr": SR, "model": L.get("model") or "gpt-4o-mini-tts", "voice": L.get("voice") or "alloy"}


async def run(lane, text, conn):
    http = conn["http"]
    req = http.build_request("POST", PATH, json={"model": conn["model"], "input": text, "voice": conn["voice"],
                                                 "response_format": "pcm"})
    await lane.t0()
    r = await http.send(req, stream=True)
    try:
        if r.status_code >= 300:
            body = (await r.aread()).decode("utf-8", "replace").strip()
            raise RuntimeError(f"OpenAI HTTP {r.status_code}: {body[:300]}")
        async for chunk in r.aiter_bytes():
            if chunk:
                await lane.audio(chunk)
    finally:
        await r.aclose()
    await lane.done()
