<p align="center">
  <strong>Gradium Examples</strong>
</p>

<p align="center">
  Small, standalone demo apps built directly on the <a href="https://gradium.ai">Gradium</a> APIs.
</p>

---

This is a collection of example apps built on Gradium's streaming **speech-to-text**, **text-to-speech**, and hosted **LLM** APIs - used directly, without any framework in between.

If you want a batteries-included voice-agent framework instead, see [Gradbot](https://github.com/gradium-ai/gradbot). These examples are for learning the raw APIs and copying patterns into your own app.

Each folder is self-contained: its own README, dependencies, and run instructions.

## Examples

| Example | What it does |
|---------|--------------|
| **[genz-translator](genz-translator/)** | Speak normally and read your words rewritten into GenZ slang, live and karaoke-style. Gradium streaming STT → LLM rewrite → tokens streamed to the browser. |

## Agent skills

The [`skills`](skills/) directory contains reusable instructions for coding
agents rather than standalone demo applications.

| Skill | What it builds |
|-------|----------------|
| **[gradium-live-avatar-agent](skills/gradium-live-avatar-agent/)** | A minimal live avatar voice agent using Gradium Voice Design, STT, and TTS with LiveKit orchestration and a LemonSlice animated face. |

## Getting started

Every example needs a Gradium API key:

```bash
export GRADIUM_API_KEY=your_gradium_key
```

Then pick an example, `cd` into it, and follow its README. Most use
[uv](https://docs.astral.sh/uv/):

```bash
cd genz-translator
uv sync
uv run uvicorn app:app --port 8402
```

## License

MIT
