"""GenZ live transcript — speak normally, read it in GenZ, near-realtime.

Browser mic audio (24kHz pcm int16) streams over a websocket to Gradium's
realtime STT. As words arrive, the current utterance is continuously
re-translated into GenZ and streamed to the page WHILE you're still talking —
each rewrite updates the same transcript card in place. When the built-in VAD
hears you pause, a final translation locks the card and the next one starts.

Run: python3 -m uvicorn app:app --port 8402
Needs GRADIUM_API_KEY in the environment.
"""

import asyncio
import collections

import pathlib

import aiohttp
import fastapi
from fastapi.responses import Response
from fastapi.staticfiles import StaticFiles

import genz
import gradium
import share

VAD_PAUSE_PROB = 0.75  # inactivity_prob (0.5s horizon) above this = end of utterance

app = fastapi.FastAPI(title="GenZ Live Transcript")


@app.websocket("/ws")
async def ws_translate(websocket: fastapi.WebSocket):
    await websocket.accept()
    # The UI picker sets the target GenZ language; STT stays multilingual.
    lang = websocket.query_params.get("lang", genz.DEFAULT_LANG)
    if lang not in genz.LANGS:
        lang = genz.DEFAULT_LANG
    client = gradium.GradiumClient()

    async with aiohttp.ClientSession() as http:
        async with client.stt_realtime(
            model_name="default", input_format="pcm"
        ) as stt:
            await websocket.send_json({"type": "ready"})

            words: list[str] = []  # current (unfinished) utterance
            finals: collections.deque[str] = collections.deque()
            dirty = False  # new words since the last partial translation
            flush_pending = False
            wake = asyncio.Event()

            async def browser_audio():
                """Binary frames from the page -> Gradium STT."""
                while True:
                    msg = await websocket.receive()
                    if msg["type"] == "websocket.disconnect":
                        raise fastapi.WebSocketDisconnect(msg.get("code", 1000))
                    if data := msg.get("bytes"):
                        await stt.send_audio(data)

            async def stt_reader():
                """Gradium STT -> live words + pause detection."""
                nonlocal dirty, flush_pending
                async for msg in stt:
                    t = msg["type"]
                    if t == "text":
                        words.append(msg["text"])
                        dirty = True
                        wake.set()
                        await websocket.send_json(
                            {"type": "partial", "text": " ".join(words)}
                        )
                    elif t == "step" and words and not flush_pending:
                        prob = msg["vad"][0]["inactivity_prob"]  # 0.5s horizon
                        if prob > VAD_PAUSE_PROB:
                            flush_pending = True
                            await stt.send_flush()
                    elif t == "flushed":
                        flush_pending = False
                        text = " ".join(w.strip() for w in words).strip()
                        words.clear()
                        dirty = False  # the final supersedes any pending partial
                        if len(text) >= 3:
                            finals.append(text)
                            wake.set()

            async def translator():
                """Re-translate the growing utterance; finalize on pause.

                One translation call in flight at a time. Partial results
                update card `card_id` in place; a queued final supersedes any
                in-flight partial for the same card.
                """
                nonlocal dirty
                seg_id = 0
                caption = ""  # the committed GenZ caption so far
                while True:
                    await wake.wait()
                    wake.clear()
                    while finals or dirty:
                        if finals:
                            text, final = finals.popleft(), True
                        else:
                            text, final = " ".join(words).strip(), False
                            dirty = False
                        if len(text) < 3:
                            continue
                        # translate as a continuation of the caption so far
                        # (last chunk of context keeps the prompt small), and
                        # buffer each rewrite so the segment text is replaced
                        # whole instead of shrinking and regrowing
                        acc = ""
                        stale = False
                        async for tok in genz.llm_genz_stream(
                            http, client._api_key, text,
                            context=caption[-500:], lang=lang,
                        ):
                            acc += tok
                            if not final and finals:
                                stale = True  # a final arrived: skip this one
                                break
                        acc = " ".join(acc.split())
                        if not stale and not final:
                            await websocket.send_json({
                                "type": "genz_live",
                                "id": seg_id,
                                "text": acc,
                            })
                        if final:
                            await websocket.send_json({
                                "type": "genz_done",
                                "id": seg_id,
                                "text": acc,
                                "src": text,  # what was said, for share cards
                            })
                            caption = f"{caption} {acc}".strip()
                            seg_id += 1

            tasks = [
                asyncio.create_task(browser_audio()),
                asyncio.create_task(stt_reader()),
                asyncio.create_task(translator()),
            ]
            try:
                done, _ = await asyncio.wait(
                    tasks, return_when=asyncio.FIRST_EXCEPTION
                )
                for task in done:
                    if not isinstance(
                        task.exception(), fastapi.WebSocketDisconnect
                    ):
                        task.result()  # surface unexpected errors in the log
            finally:
                for task in tasks:
                    task.cancel()


# --- Downloadable share card (no database: state lives in the query string) --
# Registered before the "/" static mount so it wins over the catch-all.


@app.get("/card.png")
async def card_image(said: str = "", genz: str = ""):
    """Branded 1200x630 card, rendered on the fly and offered as a download."""
    return Response(
        content=share.render_card(said, genz),
        media_type="image/png",
        headers={
            "Cache-Control": "public, max-age=86400",
            "Content-Disposition": 'attachment; filename="genz-translator.png"',
        },
    )


app.mount(
    "/",
    StaticFiles(directory=pathlib.Path(__file__).parent / "static", html=True),
    name="static",
)
