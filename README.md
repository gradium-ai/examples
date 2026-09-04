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
agents rather than standalone demo applications. Install a skill in Codex or
Claude Code, describe what you want, and let the coding agent generate and test
the project in your workspace.

| Skill | What it builds |
|-------|----------------|
| **[gradium-live-avatar-agent](skills/gradium-live-avatar-agent/)** | A minimal live avatar voice agent using Gradium Voice Design, STT, and TTS with LiveKit orchestration and a LemonSlice animated face. |
| **[gradium-pruna-designed-avatar](skills/gradium-pruna-designed-avatar/)** | A reviewed, non-realtime talking-avatar video using a bespoke Gradium voice and Pruna `p-video-avatar`. |

### Gradium Live Avatar Agent

This skill turns three creative inputs into an extensible realtime agent:

1. A reference image for the avatar.
2. A description of the voice that should accompany the image.
3. The agent's purpose and behavior, such as a language teacher, coach, tutor,
   concierge, or game character.

The generated project uses:

- **Gradium Voice Design** to create and audition an original voice;
- **Gradium STT and TTS** for the live speech pipeline;
- **LiveKit** for realtime orchestration, room access, and agent dispatch;
- **LemonSlice** to animate the supplied portrait and publish synchronized audio
  and video.

The result is deliberately minimal: one worker, one avatar-only call surface,
server-side configuration, focused tests, and a clear extension point for tools
or function calling.

Install it for Codex:

```bash
mkdir -p ~/.codex/skills
cp -R skills/gradium-live-avatar-agent ~/.codex/skills/
```

Or install it for Claude Code:

```bash
mkdir -p ~/.claude/skills
cp -R skills/gradium-live-avatar-agent ~/.claude/skills/
```

Then provide the three creative inputs in one prompt:

```text
Use $gradium-live-avatar-agent to build a live avatar agent.

Reference image: ./portrait.png
Voice: A warm, low voice with a lightly textured tone, measured pacing,
and calm confidence. English.
Agent purpose: A language coach who helps adults practise conversational
English with concise corrections and encouraging follow-up questions.
```

If an input is missing, the skill asks for it. After the creative direction is
settled, it asks about LiveKit Inference credits or a custom LLM, explains where
to configure credentials, generates one Gradium voice candidate, and waits for
approval before promoting that voice and completing the agent.

You need server-side Gradium and LemonSlice API keys plus LiveKit credentials.
Configure them in the generated project's environment file or deployment secret
store; never paste credentials into the prompt or expose them to browser code.

### Gradium + Pruna Designed Avatar

This skill creates a polished talking-avatar video from three creative inputs:

1. A portrait image for the avatar.
2. A description of the original voice to design and audition.
3. The exact spoken script, or the clip's goal and audience if you want help
   writing it.

Gradium Voice Design creates the approved voice, Gradium TTS renders the final
speech audio, and Pruna `p-video-avatar` animates the portrait from that audio.
The skill checks the finished MP4 for duration, audio, speech accuracy, lip
movement, face stability, framing, and visual artifacts. Unlike the LiveKit and
LemonSlice skill above, this workflow renders a video asynchronously; it does
not create a live or interruptible conversation.

Install it for Codex:

```bash
mkdir -p ~/.codex/skills
cp -R skills/gradium-pruna-designed-avatar ~/.codex/skills/
```

Or install it for Claude Code:

```bash
mkdir -p ~/.claude/skills
cp -R skills/gradium-pruna-designed-avatar ~/.claude/skills/
```

Then provide the creative inputs in one prompt:

```text
Use $gradium-pruna-designed-avatar to create a talking-avatar video.

Portrait: ./portrait.png
Voice: A warm, softly textured voice with measured pacing and calm confidence.
Language: English.
Script: Welcome. In the next minute, I will walk you through the three ideas
that matter most.
```

The skill creates one Gradium voice candidate, asks you to approve its audition,
then promotes that voice and submits one Pruna render. Both operations can use
paid credits, so it does not generate extra candidates or rerender without your
approval. Configure `GRADIUM_API_KEY` and `PRUNA_API_KEY` in your environment or
secret store; never put either key in a prompt, client-side bundle, or committed
file.

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
