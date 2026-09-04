# Gradium voice provisioning

Voice Design is a one-time setup path that produces the permanent `voice_id`
used by the live worker. Prefer a CLI script or a small server-only command. Do
not make voice generation part of every agent startup, and do not add a public
voice-design interface unless the user asks for one.

The user's natural-language voice description is the input to this flow. Do not
replace it with a stock voice merely to make the scaffold easier. If the user
explicitly supplies a permanent Gradium voice ID, skip provisioning and use it
directly.

When the requested direction imitates an identifiable real person, confirm that
the user is authorized to use that likeness and voice direction or revise it to
an original description. Never claim that a designed voice is the depicted
person or facilitate deceptive impersonation.

## Image and voice fit check

Inspect the reference image before generating a candidate. Ground suggestions
in visible creative signals such as expression, costume, color palette, setting,
apparent energy, and character archetype. A useful suggestion covers vocal age
range, warmth or brightness, texture, pacing, energy, accent only when the user
requests one, and the intended language.

Do not infer ethnicity, nationality, health, disability, sexual orientation, or
gender identity from the image. Do not describe a mismatch merely because the
voice is surprising. Intervene only when the requested voice is plainly at odds
with the intended on-screen character—for example, a deliberately sleepy,
monotone delivery for an explicitly high-energy children's host. In that case:

1. State the visible creative mismatch without judging it.
2. Offer two or three short alternative prompts fitted to the image.
3. Ask once whether the contrast is intentional.
4. Honor the answer. If intentional, retain the original prompt and do not ask
   again.

This is a creative consistency check, not permission to override the user.

## Candidate lifecycle

Use `https://api.gradium.ai/api` with the `x-api-key` header.

1. Generate one candidate with `POST /voice-generator/generate`:

   ```json
   {
     "prompt": "Warm, grounded, softly textured, with measured pacing.",
     "language": "en",
     "n_samples": 1,
     "json_config": {"cfg_scale": 10.0}
   }
   ```

2. Poll `GET /voice-generator/embeddings?embedding_id=<vox_emb_id>` until the
   first embedding reports `ready: true`. Use a bounded timeout and a modest
   polling interval.

3. Render a short audition with `POST /speech/tts`:

   ```json
   {
     "text": "It is lovely to meet you.",
     "voice_id": "<vox_emb_id>",
     "model_name": "gradium-tts-beta",
     "output_format": "wav",
     "only_audio": true
   }
   ```

4. After explicit approval, promote it with `POST /voices/from-embedding`:

   ```json
   {
     "voxium_embedding_id": "<vox_emb_id>",
     "name": "Character voice",
     "description": "Warm, grounded, softly textured, with measured pacing."
   }
   ```

5. Store the returned `uid` as `GRADIUM_VOICE_ID` or in the application's
   secret-backed character configuration.

6. Delete rejected or failed candidates with
   `DELETE /voice-generator/embeddings/<vox_emb_id>`.

Wrap candidate handling in cleanup logic so rejection, failed audition, timeout,
or interruption deletes the temporary embedding once its ID is known. Do not
automatically retry credit-consuming generation or promotion requests unless the
API operation is explicitly idempotent.

## Guardrails

- Always use Gradium Voice Design to create a new voice and Gradium TTS to render
  both the audition and the live agent.
- Supported design languages are `en`, `fr`, `de`, `es`, and `pt`.
- Keep voice descriptions at or below 500 characters and audition text at or
  below 100 characters.
- Use the same TTS model for the audition and live runtime.
- Patch RIFF/data sizes if a streamed WAV contains placeholder lengths.
- Never log API keys or return them to browser code.
- Apply finite connect and read timeouts to every request, check HTTP status and
  response shape before using IDs, cap downloaded audition bytes, and show
  sanitized errors without upstream bodies or headers.
- Do not save a candidate until the user has heard and approved it.
- Generate one candidate at a time by default. Ask whether to keep it or create
  another rather than repeatedly spending API credits.
- Tests should mock every Gradium endpoint and assert the lifecycle order.
- Keep auditions outside the public web root and ignore them in version control.

If the user already has a permanent voice ID, skip this entire workflow.
