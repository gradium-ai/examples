# /// script
# requires-python = ">=3.11"
# dependencies = ["websockets>=14", "ormsgpack>=1.5", "numpy>=1.26", "httpx[http2]>=0.27"]
# ///
"""Run one provider module on its own: open, race one sentence, report the timing, save a WAV.

    uv run providers/_try.py inworld --model inworld-tts-2-flash --voice Brooke
    uv run providers/_try.py deepgram --model aura-2-thalia-en --fake-key   # checks endpoint + auth only

Keys come from the environment or ../.env, like the server. --fake-key passes a dummy key, to
check that the URL and auth scheme are right: the provider should answer with an auth error.
"""
import argparse
import asyncio
import json
import sys
import time
import wave
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

import numpy as np  # noqa: E402

import providers  # noqa: E402


def load_key(name):
    import os
    if os.environ.get(name):
        return os.environ[name].strip()
    env = HERE.parent / ".env"
    if env.exists():
        for line in env.read_text().splitlines():
            if line.strip().startswith(f"{name}="):
                return line.split("=", 1)[1].strip().strip("'\"") or None
    return None


def onset_ms(pcm, sr):
    x = np.frombuffer(pcm, dtype="<i2").astype(np.float32) / 32768
    if not x.size:
        return None
    f, h = max(1, round(0.010 * sr)), max(1, round(0.001 * sr))
    w = np.lib.stride_tricks.sliding_window_view(np.pad(x, f // 2, mode="edge"), f)[::h]
    hit = np.flatnonzero(np.sqrt(np.mean((w - w.mean(axis=1, keepdims=True)) ** 2, axis=1)) > 0.01)
    return None if not hit.size else round(hit[0] * h / sr * 1000, 1)


class FakeLane:
    def __init__(self, sr):
        self.pid, self.sr, self.t_text, self.first, self.pcm, self.chunks = "try", sr, None, None, bytearray(), 0

    async def t0(self):
        self.t_text = time.perf_counter()

    async def audio(self, data):
        if data and self.first is None:
            self.first = time.perf_counter()
        self.pcm += data
        self.chunks += 1

    async def done(self):
        pass


async def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("provider")
    ap.add_argument("--model", default="")
    ap.add_argument("--voice", default="")
    ap.add_argument("--extra", default="{}", help="JSON of extra lane fields")
    ap.add_argument("--text", default="Hi, thanks for calling. Doctor Smith has an opening tomorrow at half past ten. Shall I book you in?")
    ap.add_argument("--fake-key", action="store_true")
    ap.add_argument("--runs", type=int, default=2)
    a = ap.parse_args()
    mod = providers.get(a.provider)
    keys = {k: ("fake-key-for-endpoint-check" if a.fake_key else load_key(k)) for k in mod.KEYS}
    if not all(keys.values()):
        sys.exit(f"missing {', '.join(k for k, v in keys.items() if not v)}")
    cfg = {"label": a.provider, "provider": a.provider, "model": a.model, "voice": a.voice, **json.loads(a.extra)}
    for i in range(a.runs):
        t = time.perf_counter()
        try:
            conn = await mod.open(cfg, keys)
        except Exception as e:  # noqa: BLE001
            print(f"open failed: {type(e).__name__}: {str(e)[:300]}")
            return
        opened = (time.perf_counter() - t) * 1000
        lane = FakeLane(conn["sr"])
        t = time.perf_counter()
        try:
            await asyncio.wait_for(mod.run(lane, a.text, conn), 30)
        except Exception as e:  # noqa: BLE001
            print(f"run failed: {type(e).__name__}: {str(e)[:300]}")
            return
        total = (time.perf_counter() - t) * 1000
        sil = onset_ms(bytes(lane.pcm), conn["sr"])
        first = None if lane.first is None or lane.t_text is None else (lane.first - lane.t_text) * 1000
        secs = len(lane.pcm) / 2 / conn["sr"]
        print(f"run {i + 1}: open {opened:.0f} ms | first chunk {first and round(first)} ms + silence {sil} ms"
              f" | {lane.chunks} chunks, {secs:.2f} s audio at {conn['sr']} Hz | total {total:.0f} ms")
        if i == a.runs - 1 and lane.pcm:
            out = HERE.parent / f".try-{a.provider}.wav"
            with wave.open(str(out), "wb") as w:
                w.setnchannels(1); w.setsampwidth(2); w.setframerate(conn["sr"]); w.writeframes(bytes(lane.pcm))
            print(f"wrote {out.name}")


asyncio.run(main())
