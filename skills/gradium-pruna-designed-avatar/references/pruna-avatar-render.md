# Pruna avatar render

Use this reference after the Gradium voice has been approved and promoted.
Pruna accepts an uploaded WAV and animates a single portrait around that audio.
The audio determines the clip duration and preserves the Gradium-designed voice.

## 1. Synthesize the production WAV

Call `POST https://api.gradium.ai/api/post/speech/tts` with `x-api-key`:

```json
{
  "text": "<approved script>",
  "voice_id": "<permanent Gradium voice ID>",
  "output_format": "wav",
  "only_audio": true
}
```

Apply the approved language-specific rewrite rules, pronunciation dictionary,
speed, and pauses when the project uses them. Validate that the response is a
bounded, decodable WAV before sending it downstream.

## 2. Upload portrait and audio

Upload each file as multipart field `content`:

```bash
curl -X POST https://api.pruna.ai/v1/files \
  -H "apikey: $PRUNA_API_KEY" \
  -F "content=@portrait.png"
```

Use each response's `urls.get` value in the prediction request. Never pass a
local path or base64 string as Pruna's `image` or `audio` input.

## 3. Submit `p-video-avatar`

```bash
curl -X POST https://api.pruna.ai/v1/predictions \
  -H "Content-Type: application/json" \
  -H "apikey: $PRUNA_API_KEY" \
  -H "Model: p-video-avatar" \
  -d '{
    "input": {
      "image": "<uploaded portrait URL>",
      "audio": "<uploaded WAV URL>",
      "resolution": "720p",
      "video_prompt": "Fixed camera; natural head movement and subtle gestures.",
      "disable_safety_filter": false,
      "disable_prompt_upsampling": true
    }
  }'
```

Use 720p for drafts and first takes. Choose 1080p only when the user wants it
and understands the higher charge. Add a `seed` when reproducibility or a reroll
is needed. Keep `negative_prompt` short; long lists can suppress facial motion.

Do not send `voice_script`, `voice`, `voice_language`, or `voice_prompt` with the
uploaded Gradium audio. The external audio is the source of truth.

Keep the safety filter enabled explicitly. Disable prompt upsampling by default
because the current upsampling path can send the image and prompt to an
additional model provider. If a user deliberately enables upsampling, disclose
that extra data flow and obtain consent before submission.

## 4. Poll and download

Poll `GET /v1/predictions/status/{id}` at a modest interval until `succeeded` or
`failed`, with an overall deadline. A success response includes
`generation_url`. When downloading:

- attach the `apikey` header only to the exact `https://api.pruna.ai` origin;
- resolve relative delivery URLs against that origin, and never forward
  credentials across a redirect or origin change;
- cap response bytes and validate the downloaded media container;
- write only to a server-generated or explicitly approved output path.

Treat 429 and transient 5xx responses with bounded backoff. Do not automatically
resubmit a prediction when the submission result is ambiguous; first reconcile
the prediction ID or idempotency record to avoid duplicate charges.

Use an HTTP client and structured JSON/multipart APIs in application code. The
curl snippets are illustrative only; never construct a shell command by
concatenating user-controlled paths, prompts, filenames, URLs, IDs, or scripts.

## Prompting

`video_prompt` controls motion, framing, and scene behavior, not the voice. Lead
with mouth articulation when lip motion is weak, then describe the physical
performance:

> The person speaks clearly; lips and jaw articulate every syllable. Fixed
> camera, direct eye line, natural head movement, subtle shoulder gestures, and
> stable background.

Prefer a clean, single-subject portrait with the face unobstructed, useful space
around the head, and lighting that remains believable during animation.

Official Pruna documentation:

- https://docs.api.pruna.ai/guides/models/p-video-avatar
- https://docs.api.pruna.ai/apis/models-api-0/versions/d086a242-3813-4148-a087-e724d4b333f8
