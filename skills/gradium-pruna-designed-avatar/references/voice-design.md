# Gradium Voice Design provisioning

Use this reference only when the user needs a newly designed voice. If they
provide a permanent Gradium `voice_id`, skip this lifecycle and use that voice.

Voice Design is a one-time, server-side flow. It creates a temporary embedding,
lets the user hear an audition, and promotes only the accepted candidate to a
permanent voice. Use `https://api.gradium.ai/api` and the `x-api-key` header.

## Candidate lifecycle

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
   selected embedding reports `ready: true`. Use a finite deadline and modest
   polling interval.

3. Render an audition through Gradium TTS. The current REST endpoint for
   one-shot synthesis is `POST /post/speech/tts`:

   ```json
   {
     "text": "It is lovely to meet you.",
     "voice_id": "<vox_emb_id>",
     "output_format": "wav",
     "only_audio": true
   }
   ```

4. Let the user hear the audition. Ask whether to keep it or create one more
   candidate. Never silently generate a batch of paid candidates.

5. After explicit approval, promote it with `POST /voices/from-embedding`:

   ```json
   {
     "voxium_embedding_id": "<vox_emb_id>",
     "name": "Character voice",
     "description": "Warm, grounded, softly textured, with measured pacing."
   }
   ```

6. Store the returned `uid` as the permanent `GRADIUM_VOICE_ID` or in a
   secret-backed avatar profile. The Pruna render path must reuse this ID.

7. Delete rejected, failed, timed-out, or interrupted candidates with
   `DELETE /voice-generator/embeddings/<vox_emb_id>` once their ID is known.
   Put cleanup in a `finally`-equivalent path, but never delete an approved and
   promoted voice.

## Voice fit and audition text

Ground suggestions in visible creative qualities—not sensitive identity
inferences. A useful voice prompt covers vocal age range, warmth or brightness,
texture, pace, energy, intended language, and accent only when requested.

Keep the Voice Design prompt at or below 500 characters and audition text at or
below 100 characters. Use a neutral line that exercises the intended language,
pace, and emotional range without being the entire production script.

## Operational guardrails

- Supported design languages are `en`, `fr`, `de`, `es`, and `pt`.
- Use the same Gradium TTS model and tuning for audition and final speech.
- Put finite timeouts around generation, polling, audition, promotion, and
  cleanup; cap downloaded audition bytes.
- Check response status and schema before consuming an embedding ID or voice ID.
- Do not log keys, raw upstream error bodies, or full user-authored scripts.
- Save auditions outside the public web root and exclude them from version
  control. Apply a short retention policy after approval.
- Tests must mock the lifecycle and assert that rejection and interruption clean
  up the temporary embedding.

The public Gradium reference documents authentication, the REST base URL, and
the current TTS endpoint at https://docs.gradium.ai/api-reference/introduction
and https://docs.gradium.ai/api-reference/endpoint/tts-post.
