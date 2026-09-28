# voice-design-demo

**["Giving voice agents a voice that adapts to context" Live Demo](https://voice-design-demo.thomassegura.workers.dev)**

Type a customer message, pick a language (en, fr, de) and register (formal,
casual), and watch each step of a turn:

1. **Extract context**: Jev answers two Choice questions (tone, energy) in one
   request. Answers below 0.6 confidence fall back to the defaults (neutral,
   relaxed).
2. **Map**: PERSONA and DELIVERY turn the spec into a Voice Design prompt.
3. **Resolve**: `resolveVoice` picks an exact match from the library, or the
   nearest approved voice in the same language. Every miss is queued for Voice
   Design. If no voice is approved for the language yet, a Gradium flagship
   voice stands in.
4. **Speak**: an ordinary Gradium TTS request with the resolved `voice_id`.

Off the hot path, the design queue runs generate, waitUntilReady, audition and
convert (see the [Voice Design guide](https://docs.gradium.ai/guides/voices/voice-design)). The trace panel records every request with browser and upstream
timings, split into critical-path and off-path lanes.

## Run locally

```bash
bun install
bun dev
```

Open http://localhost:3000.

Add keys with the **Keys** button. Without a Jev key, an offline keyword classifier stands
in.

## Docs

- [Voice Design guide](https://docs.gradium.ai/guides/voices/voice-design): create a voice from a description, audition it, and convert it.
- [Gradium API reference](https://docs.gradium.ai/api-reference/introduction): TTS, Voices and Voice Design endpoints.

## Layout

- `src/lib/pipeline/`: the article's code (questions, context, prompt, resolve, gradium).
- `src/app/api/`: thin routes that proxy Jev and Gradium and return upstream timings.
- `src/lib/trace.ts`: span store behind the trace panel.
- `src/components/`: one card per step, plus the pipeline strip and trace panel.
