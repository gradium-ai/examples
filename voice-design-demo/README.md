# voice-design-demo

**["Giving voice agents a voice that adapts to context" Live Demo](https://voice-design-demo.thomassegura.workers.dev)**

Type a customer message, pick a language (en, fr, de) and register (formal,
casual), and watch each step of a turn:

1. **Extract context**: Jev answers two Choice questions (tone, energy) in one
   request. Answers below 0.6 confidence fall back to the defaults (neutral,
   relaxed).
2. **Map**: PERSONA and DELIVERY turn the spec into a Voice Design prompt.
3. **Speak**: click **Generate speech**. The demo reuses an exact matching voice
   from your library, or generates a voice, waits until it is ready, and saves it
   automatically before speaking with Gradium TTS. Creating a new voice uses one
   custom-voice slot. There is no audition or selection step.

The trace panel shows the requests and their timings. See the
[Voice Design guide](https://docs.gradium.ai/guides/voices/voice-design)
for details on generating and saving voices.

## Run locally

```bash
bun install
bun dev
```

Open http://localhost:3000.

Add keys with the **Keys** button. Without a Jev key, an offline keyword classifier stands
in.

## Docs

- [Voice Design guide](https://docs.gradium.ai/guides/voices/voice-design): create a voice from a description and save it to your library.
- [Gradium API reference](https://docs.gradium.ai/api-reference/introduction): TTS, Voices and Voice Design endpoints.

## Layout

- `src/lib/pipeline/`: the article's code (questions, context, prompt, resolve, gradium).
- `src/app/api/`: thin routes that proxy Jev and Gradium and return upstream timings.
- `src/lib/trace.ts`: span store behind the trace panel.
- `src/components/`: one card per step, plus the pipeline strip and trace panel.
