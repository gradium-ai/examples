#!/usr/bin/env python3
"""Realtime GenZ translator — speak into the mic, hear it back in GenZ.

Pipeline (all Gradium):
  mic (24kHz pcm) -> Gradium streaming STT (+VAD pause detection)
                  -> Gradium-hosted LLM rewrites the utterance in GenZ slang
                  -> Gradium streaming TTS (Zoey, "GenZ energy" voice) -> speakers

Usage:
  python3 genz_translator.py                # live mic mode
  python3 genz_translator.py --text "Hey hello, this is really good"

Requires GRADIUM_API_KEY in the environment.
"""

import argparse
import asyncio
import json
import os
import pathlib
import queue
import sys
import threading

import aiohttp
import numpy as np
import sounddevice as sd

import gradium

SAMPLE_RATE = 24000  # mic / STT rate; TTS output rate comes from its ready msg
CHUNK = 1920  # 80ms at 24kHz, one VAD step
VAD_PAUSE_PROB = 0.75  # inactivity_prob (0.5s horizon) above this = end of utterance
VOICE_ID = "NbpkqMVS3CJeq2j8"  # Zoey — playful, upbeat, GenZ energy

# Any OpenAI-compatible chat-completions endpoint (see genz.py). Auth reuses
# your GRADIUM_API_KEY.
LLM_URL = os.environ.get("LLM_URL")
LLM_MODEL = os.environ.get("LLM_MODEL", "google/gemma-4-26B-A4B-it")
if not LLM_URL:
    sys.exit("Set LLM_URL to an OpenAI-compatible chat-completions endpoint. See README.")

DIM, BOLD_CYAN, RESET = "\033[2m", "\033[1;96m", "\033[0m"

_SLANG = json.loads(
    (pathlib.Path(__file__).parent / "genz_slang.json").read_text()
)["slang"]
_GLOSSARY = "\n".join(f'- {s["term"]}: {s["meaning"]}' for s in _SLANG)

SYSTEM_PROMPT = f"""You are a live interpreter that translates plain spoken English into GenZ slang.

Rewrite the user's sentence in GenZ speak. Ground yourself in this slang glossary:
{_GLOSSARY}

Rules:
- Output ONLY the translation. No quotes, no explanations, no emojis.
- Keep it SHORTER or equal in length to the input. Punchy. This is spoken aloud.
- Keep the original meaning intact, just maximally GenZ-ify the delivery.
- Example: "Hey hello, this is really good" -> "Yo, this slaps, no cap"
"""


async def llm_genz_stream(http: aiohttp.ClientSession, api_key: str, text: str):
    """Stream GenZ translation tokens from the Gradium-hosted LLM."""
    payload = {
        "model": LLM_MODEL,
        "messages": [
            {"role": "system", "content": SYSTEM_PROMPT},
            {"role": "user", "content": text},
        ],
        "stream": True,
        "temperature": 0.8,
        "max_tokens": 100,
        "chat_template_kwargs": {"enable_thinking": False},
    }
    headers = {"Authorization": f"Bearer {api_key}"}
    async with http.post(LLM_URL, json=payload, headers=headers) as resp:
        resp.raise_for_status()
        async for raw in resp.content:
            line = raw.decode("utf-8", "ignore").strip()
            if not line.startswith("data:"):
                continue
            data = line[5:].strip()
            if data == "[DONE]":
                break
            delta = json.loads(data)["choices"][0].get("delta", {})
            if tok := delta.get("content"):
                yield tok


class Player:
    """Speaker playback on a dedicated thread so the event loop never blocks."""

    def __init__(self):
        self.q: queue.Queue[bytes | None] = queue.Queue()
        self.stream = None
        self.rate = None
        threading.Thread(target=self._run, daemon=True).start()

    def ensure(self, rate: int):
        """(Re)open the output stream at the TTS sample rate before queueing audio."""
        if rate != self.rate:
            if self.stream is not None:
                self.stream.stop()
                self.stream.close()
            self.stream = sd.RawOutputStream(samplerate=rate, channels=1, dtype="int16")
            self.stream.start()
            self.rate = rate

    def _run(self):
        while (data := self.q.get()) is not None:
            self.stream.write(data)

    async def drain(self):
        while not self.q.empty():
            await asyncio.sleep(0.05)
        # let the last buffered chunk fully leave the speakers before unmuting
        # the mic, or the STT hears the tail of our own TTS and echo-loops
        tail = self.stream.latency if self.stream is not None else 0.2
        await asyncio.sleep(0.5 + tail)


async def speak_genz(
    client: gradium.GradiumClient,
    http: aiohttp.ClientSession,
    player: Player,
    text: str,
) -> None:
    """Translate one utterance and play it: LLM tokens stream straight into TTS."""
    print(f'{DIM}you said: "{text}"{RESET}')
    print(f"{BOLD_CYAN}genz: ", end="", flush=True)

    setup = {"model_name": "default", "voice_id": VOICE_ID, "output_format": "pcm"}
    async with client.tts_realtime(**setup) as tts:
        player.ensure(tts.ready.get("sample_rate", 48000))

        async def feed():
            async for tok in llm_genz_stream(http, client._api_key, text):
                print(tok, end="", flush=True)
                await tts.send_text(tok)
            await tts.send_eos()

        feed_task = asyncio.create_task(feed())
        async for msg in tts:
            if msg["type"] == "audio":
                player.q.put(msg["audio"])
        await feed_task
    print(RESET)
    await player.drain()


async def live_mic(client: gradium.GradiumClient, http: aiohttp.ClientSession):
    player = Player()
    loop = asyncio.get_running_loop()
    mic_q: asyncio.Queue[bytes] = asyncio.Queue()
    muted = False  # half-duplex: mic is dropped while the translation plays
    words: list[str] = []
    flush_pending = False

    def on_audio(indata, frames, time_info, status):
        loop.call_soon_threadsafe(mic_q.put_nowait, bytes(indata))

    mic = sd.RawInputStream(
        samplerate=SAMPLE_RATE,
        channels=1,
        dtype="int16",
        blocksize=CHUNK,
        callback=on_audio,
    )

    async with client.stt_realtime(model_name="default", input_format="pcm") as stt:
        mic.start()
        print("🎤 mic is live — say something (Ctrl-C to quit)\n")

        async def sender():
            silence = np.zeros(CHUNK, dtype=np.int16).tobytes()
            while True:
                chunk = await mic_q.get()
                await stt.send_audio(silence if muted else chunk)

        send_task = asyncio.create_task(sender())
        try:
            async for msg in stt:
                if msg["type"] == "text":
                    words.append(msg["text"])
                elif msg["type"] == "step" and words and not flush_pending:
                    prob = msg["vad"][0]["inactivity_prob"]  # 0.5s horizon: snappy
                    if prob > VAD_PAUSE_PROB:
                        flush_pending = True
                        await stt.send_flush()
                elif msg["type"] == "flushed":
                    flush_pending = False
                    text = " ".join(w.strip() for w in words).strip()
                    words.clear()
                    if len(text) < 3:
                        continue
                    muted = True
                    try:
                        await speak_genz(client, http, player, text)
                    except Exception as e:
                        print(f"\n[translation error: {e}]", file=sys.stderr)
                    muted = False
        finally:
            send_task.cancel()
            mic.stop()


async def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--text", help="translate one line of text instead of using the mic")
    args = parser.parse_args()

    client = gradium.GradiumClient()  # reads GRADIUM_API_KEY
    async with aiohttp.ClientSession() as http:
        if args.text:
            await speak_genz(client, http, Player(), args.text)
        else:
            await live_mic(client, http)


if __name__ == "__main__":
    try:
        asyncio.run(main())
    except KeyboardInterrupt:
        print("\nbye 💅")
