# GenZ Realtime Translator 💅

Speak normally → read your words in GenZ, live. No TTS — the GenZ text IS the
transcript. 100% Gradium:

```
browser mic (24kHz pcm over websocket)
   ──► Gradium streaming STT + VAD pause detection
          │  (utterance ends ~0.5s after you pause; interim words shown live)
          ▼
   OpenAI-compatible LLM rewrites it in GenZ slang,
   grounded in genz_slang.json (100+ terms with meanings)
          │
          ▼
   tokens stream straight back to the page ──► transcript card
```

Example: "Hey hello, this is really good" → **"Yo, this slaps, no cap"**

## Setup

Set your keys and the LLM endpoint:

```bash
export GRADIUM_API_KEY=your_gradium_key

# Any OpenAI-compatible chat-completions endpoint (Gradium-hosted model,
# OpenAI, Groq, Ollama, LM Studio, …). Auth reuses GRADIUM_API_KEY.
export LLM_URL=https://your-provider.example/v1/chat/completions
export LLM_MODEL=google/gemma-4-26B-A4B-it   # optional, this is the default
```

Install dependencies (with [uv](https://docs.astral.sh/uv/)):

```bash
uv sync
```

## Run it

```bash
uv run uvicorn app:app --port 8402
```

Then open <http://127.0.0.1:8402>, hit the mic button, allow mic access, and
start yapping.

> Note: embedded preview panels often can't grant mic permission — open the URL
> in a normal Chrome/Safari tab.

The GenZ transcript is ONE continuous caption that grows karaoke-style: words
light up one by one following your speech (130ms cadence, fast catch-up when a
chunk finalizes), newest word glowing. Each VAD-delimited chunk is translated
as a continuation of the caption so far (the LLM gets the running GenZ text as
context), so pauses never restart the sentence or re-greet.

## Files

- [app.py](app.py) — FastAPI backend: browser audio → Gradium STT → LLM → streamed tokens
- [static/index.html](static/index.html) — the UI (mic button + live GenZ transcript)
- [genz.py](genz.py) — shared glossary loading + streaming LLM translation
- [share.py](share.py) — renders the downloadable share card
- [genz_slang.json](genz_slang.json) — the slang repository; edit it to teach the translator new words (per-language variants: `.fr`, `.de`, `.pt`, `.es`)
- [genz_translator.py](genz_translator.py) — terminal-only version that speaks the translation out loud via Gradium TTS. Needs the extra audio dep: `uv sync --extra terminal`, then `uv run python genz_translator.py`

## Tuning

- `VAD_PAUSE_PROB` in `app.py`: how long a pause ends an utterance
  (0.5s-horizon `inactivity_prob` threshold, default 0.75). Lower = snappier.
</content>
