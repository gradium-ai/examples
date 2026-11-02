"""MiniMax TTS (Speech 2.8 line) over the t2a_v2 WebSocket.

Adapted from coval-ai/benchmarks runner/src/coval_bench/providers/tts/minimax.py (Apache-2.0).
open() connects, waits for connected_success, sends task_start (model, voice, 24 kHz mono PCM)
and waits for task_started, exactly the setup Coval keeps outside its clock. run() times
task_continue (the text) + task_finish. Audio arrives hex-encoded in task_continued frames.
A bad key is refused at the upgrade with HTTP 200 and a JSON base_resp, surfaced as the error.
"""
import json

from websockets.exceptions import InvalidStatus

from ._util import SR, ws_connect

KEYS = ("MINIMAX_API_KEY",)
HOST = "api.minimax.io"
URL = "wss://api.minimax.io/ws/v1/t2a_v2"


def _frame(raw):
    m = json.loads(raw)
    base = m.get("base_resp") or {}
    if m.get("event") == "task_failed" or base.get("status_code", 0) != 0:
        raise RuntimeError(f"MiniMax {m.get('event')}: [{base.get('status_code')}] {base.get('status_msg', '')}")
    return m


async def _expect(ws, event):
    while True:
        raw = await ws.recv()
        if isinstance(raw, (bytes, bytearray)):
            continue
        if _frame(raw).get("event") == event:
            return


async def open(L, keys):
    try:
        ws = await ws_connect(URL, headers={"Authorization": f"Bearer {keys['MINIMAX_API_KEY']}"}, max_size=16 * 1024 * 1024)
    except InvalidStatus as e:
        # a rejected handshake comes back as HTTP 200 with a JSON base_resp, e.g. 2049 "invalid api key"
        body = bytes(e.response.body or b"").decode("utf-8", "replace")
        raise RuntimeError(f"MiniMax handshake rejected (HTTP {e.response.status_code}): {body[:200]}") from None
    try:
        await _expect(ws, "connected_success")
        await ws.send(json.dumps({"event": "task_start", "model": L["model"],
                                  "voice_setting": {"voice_id": L["voice"]},
                                  "audio_setting": {"format": "pcm", "sample_rate": SR, "channel": 1}}))
        await _expect(ws, "task_started")
    except BaseException:
        await ws.close()
        raise
    return {"ws": ws, "sr": SR}


async def run(lane, text, conn):
    ws = conn["ws"]
    try:
        await lane.t0()
        await ws.send(json.dumps({"event": "task_continue", "text": text}))
        await ws.send(json.dumps({"event": "task_finish"}))
        async for raw in ws:
            if isinstance(raw, (bytes, bytearray)):
                continue
            m = _frame(raw)
            ev = m.get("event")
            if ev == "task_continued":
                audio = (m.get("data") or {}).get("audio")
                if audio:
                    await lane.audio(bytes.fromhex(audio))
                if m.get("is_final"):
                    break
            elif ev == "task_finished":
                break
    finally:
        await ws.close()
    await lane.done()
