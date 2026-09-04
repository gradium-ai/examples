# Quality, safety, and product checks

Every paid render must pass mechanical, auditory, and visual review before it is
presented as final. Avatar generation is stochastic; a successful API response
does not prove a usable result.

## Mechanical and audio checks

- Use `ffprobe` to confirm the MP4 is decodable and its duration approximately
  matches the source Gradium WAV.
- Confirm the MP4 contains an audio stream and is not silent.
- Extract the audio track and transcribe it with Gradium STT when exact wording
  matters. Compare normalized transcript text with the approved script.
- Preserve the original WAV and request metadata until the take is accepted, but
  never persist credentials or raw provider headers.

## Visual checks

Build and inspect two contact sheets:

1. Six to eight frames evenly spaced over the full clip, checking face and hair
   stability, eye behavior, gaze drift, background changes, framing, accidental
   text, and source-image morphing at the start.
2. Frames at speech-word midpoints, using Gradium timestamps when available or
   evenly spaced speaking moments otherwise. The mouth should visibly articulate
   most sampled words.

Inspect the first second separately. Pruna can begin close to the source image
and blend into generated motion; repair the source or use a short fade only when
that transition is distracting.

Speech containing IDs, numbers, or serials can provoke pseudo-caption artifacts.
Add a concise no-text physical description to `video_prompt`, then inspect the
entire frame over time. Crop or mask only when the artifact stays outside the
subject at every checked timestamp; otherwise rerender.

## Retry policy

Choose the least expensive fix that addresses the failure:

1. source-image cleanup or reframing;
2. a tighter positive motion prompt or shorter negative prompt;
3. local crop, mask, or fade when it cannot damage the subject;
4. one user-authorized rerender with a different seed.

Do not claim deterministic lip-sync or identity stability. Grade a rerender from
scratch rather than assuming it fixed only the targeted flaw.

## Media and URL safety

For uploads, cap bytes and decoded pixels, allow only required raster/audio
formats, strip metadata, and re-encode to known output formats. Generate storage
names server-side and keep assets outside executable and public directories.

If the product accepts remote URLs, allow HTTPS only; reject embedded
credentials, unusual ports, loopback, private, link-local, multicast, and cloud
metadata destinations for both IPv4 and IPv6. Revalidate every redirect and
enforce redirect, timeout, and byte limits.

Hosted generation endpoints must authenticate callers, enforce exact schemas and
request-size limits, rate-limit by account and source, cap concurrent jobs and
daily spend, and make repeated starts idempotent. Never let the browser choose
server filesystem paths, provider headers, prediction IDs belonging to another
account, or arbitrary download destinations.

## Data flow and retention

Document that the portrait and synthesized audio go to Pruna, while the voice
description and script go to Gradium for Voice Design and TTS. State actual
provider region, recording, observability, retention, and deletion controls;
never promise zero retention unless verified for the selected accounts.

Keep Pruna prompt upsampling disabled by default so this provider list remains
complete. If an implementation enables it, disclose the additional model
provider and obtain the user's consent before sending the portrait or prompt.

For an identifiable real person, record the user's authorization before paid
generation and recommend a clear synthetic-media disclosure anywhere the output
could plausibly be mistaken for authentic footage. Do not claim that a designed
voice is the subject's real voice.

Keep `.env`, auditions, local portraits, generated WAV files, and private video
outputs out of version control by default. Before publication, inspect staged
files and history for credentials and personal media without printing matched
secret values.
