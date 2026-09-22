# TTS Latency Race 🏁

One sentence, fired at six streaming Text-to-Speech models at the same
instant. Each lane draws what came back and shows the time a listener actually
waits before hearing the first sound.

```
browser                     server (holds the keys)
   │  text                     ├── Gradium default        wss://api.gradium.ai/api/speech/tts   pcm 48 kHz
   ├──────────────────────────►├── Gradium beta           same socket, gradium-tts-beta-202609
   │                           ├── ElevenLabs v3 conv.    wss://api.elevenlabs.io  dialogue     pcm 24 kHz
   │                           ├── ElevenLabs flash v2.5  wss://api.elevenlabs.io  stream-input pcm 24 kHz
   │  NDJSON: first, landed,   ├── Cartesia sonic-3.6     wss://api.cartesia.ai/tts/websocket   pcm 24 kHz
   │  audio, done              └── Fish Audio s2.1-pro    wss://api.fish.audio/v1/tts/live      pcm 24 kHz
   ◄───────────────────────────
   one waveform per lane, time to first audio per lane, sorted as they answer
```

One lane per model, one colour per provider. The models of a provider share a
voice, so the only difference between two lanes of the same colour is the model
tag.

Lanes climb as they answer, fastest on top, and the fastest lane is the one you
hear. Click any lane to play it. Tick **show the leading silence** to swap the
waveforms for a stacked bar: the network round trip, the rest of the first
chunk, then the silence at the head of the stream, hatched.

The metric is the one from Coval's public benchmarks repo,
[coval-ai/benchmarks](https://github.com/coval-ai/benchmarks): same definition
of t0, same perceived time to first audio, same onset detector. Two provider
settings differ from their clients, both listed below, so the numbers are
comparable with theirs with those two in mind.

## Setup

```bash
export GRADIUM_API_KEY=your_gradium_key
export ELEVENLABS_API_KEY=your_elevenlabs_key   # optional
export CARTESIA_API_KEY=your_cartesia_key       # optional
export FISH_API_KEY=your_fish_key               # optional
```

Keys can also go in a `.env` file next to `server.py` (gitignored). They stay on
the server and the browser never sees one: the page is told only which
environment variable a lane is missing. A lane with no key is greyed out and
sits out the race, so the Gradium key alone is enough to run it.

## Run it

```bash
uv run server.py                          # http://127.0.0.1:8403
uv run server.py --port 9000 --host 0.0.0.0
```

Dependencies (`websockets`, `ormsgpack`) are declared inline with PEP 723, so
[uv](https://docs.astral.sh/uv/) installs them on the first run. Python 3.11 or
newer. Then open the page, type a sentence, and press Go.

## How the number is measured

Time to first audio (TTFA) is measured exactly as Coval's public benchmarks
repo measures it, [coval-ai/benchmarks](https://github.com/coval-ai/benchmarks)
([`docs/methodology.md`](https://github.com/coval-ai/benchmarks/blob/main/docs/methodology.md)),
so the lanes are comparable with each other and with Coval's published runs:

- **t0 is the text submit**, taken after connect, TLS, the websocket upgrade and
  the provider's session setup. Every socket is opened and set up before Go, so
  the race times synthesis and not TCP. Connect time is excluded. Cartesia and
  Fish Audio have no setup handshake: their first frame is the request itself,
  so it sits inside the measurement, as it does in coval's clients.
- **TTFA is perceived**: first chunk arrival minus t0, *plus* the leading
  silence inside the stream. A provider that answers instantly with 300 ms of
  silence has not started speaking.
- **The onset** is the centre of the first 10 ms frame whose RMS exceeds 0.01,
  scanned with a 1 ms hop, per-frame mean removed, signal edge-padded by half a
  frame. On each lane the dim part of the waveform is that leading silence and
  the white line is where the voice starts.
- **A stream that never becomes audible is a failure**, not a slow answer: if no
  frame passes the threshold, the lane reports no TTFA and says so, which is how
  coval scores it.
- **The network segment** is one TCP round trip to the provider's hostname,
  measured once at start-up. It sits inside the first chunk and nothing
  subtracts it. Most providers answer from an edge nearby, so it is a floor,
  not the path to the origin.
- **Same wire settings everywhere**: raw PCM out, so no container and no decode
  step, one sentence in one frame, one voice per provider. Each model speaks the
  socket its provider documents for it: ElevenLabs v3 uses `text-to-dialogue`,
  flash uses `text-to-speech/{voice}/stream-input`.
- **Every provider gets its session setup out of the way before the clock**, so
  no lane pays for the other side's handshake inside its own number.

### Where this differs from Coval's clients

Two changes, both to stop a provider being measured unfairly. Everything else,
including the metric itself, is theirs.

- **Fish Audio runs in `latency: "low"`**, its documented lowest-latency mode;
  Coval uses `balanced`. Measured here over three runs: 489 ms median on
  `balanced`, 433 ms on `low`. `quality-guard` stays on, as in Coval's client,
  because it costs nothing measurable (433 ms with it, 440 ms without).
- **Fish's `start` frame is sent before the clock.** It carries the voice and
  the output format, which is exactly the session setup every other lane sends
  before t0, but Coval's client sends it after starting the clock, so Fish was
  paying for its own setup while Gradium and ElevenLabs were not. Worth about
  16 ms.

One thing that was checked and left alone:

- **`auto_mode=true` on the ElevenLabs stream-input socket** is documented as a
  latency win for whole-sentence input, and it is not used here because it
  measured slower: 138 ms median against 121 ms without it.

Timestamps are taken on the server the moment a chunk lands, so browser
scheduling never enters the measurement. The onset detection runs off the event
loop, so one lane's scan cannot delay the timestamp of a chunk arriving for
another lane. Numbers depend on your distance to each
provider's edge, so run it from where your users are.

## Files

- [server.py](server.py) - the four provider clients, the timing, and the NDJSON stream to the page
- [index.html](index.html), [style.css](style.css), [app.js](app.js) - the page: one textarea, one button, one lane per model

## Changing the lanes

Everything configurable sits in the `LANES` dict at the top of `server.py`:
label, model tag, voice id, host, and which `runner` speaks that provider's
protocol. Adding another model of a provider already there is one dict entry.
Adding a new provider is one entry plus one coroutine that calls `lane.t0()`
right before sending the text and `lane.audio(pcm_bytes)` for every chunk; the
`Lane` class does the rest of the timing.
