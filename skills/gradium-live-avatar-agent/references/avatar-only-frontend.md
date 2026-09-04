# Avatar-only frontend

The web client exists to show and control the live conversation. It is not a
configuration product.

## Visible surface

Include only:

- the remote LemonSlice video filling the primary viewport;
- remote avatar audio;
- a start/end call control;
- a microphone mute/unmute control;
- a restrained connecting, ready, listening, or speaking state.

Before the video arrives, the same reference portrait may fill the stage as a
placeholder. A compact error message is acceptable. Do not add transcript,
character fields, voice controls, model selectors, debug panels, provider
branding, or setup steps unless the user explicitly requests them.

## LiveKit browser behavior

The server returns a participant token and `LIVEKIT_URL`. The browser connects
with `livekit-client`, subscribes to remote tracks, and attaches them:

```javascript
room.on(RoomEvent.TrackSubscribed, (track) => {
  if (track.kind === Track.Kind.Video) track.attach(videoElement);
  if (track.kind === Track.Kind.Audio) audioRoot.appendChild(track.attach());
});
```

Enable the microphone immediately after the LiveKit room connects. Do not put
microphone startup inside the avatar `TrackSubscribed` callback: video arrival
and microphone publication are independent lifecycles, and coupling them can
produce a visually connected call with no input audio. Request echo
cancellation, noise suppression, and automatic gain control.

Keep a lightweight microphone health check while the call is active. Observe
whether the local publication exists and its underlying media track is enabled
and `live`; republish the microphone once if the track unexpectedly ends, but
only while an explicit `desiredMicEnabled` state is true and the call remains
active. Never recover capture after the user muted, ended the call, denied or
revoked permission, removed the device, or left the page.

Send connection and microphone health events to a server-side diagnostic
endpoint only when diagnostics are enabled. Authenticate and rate-limit it,
accept a small allowlisted event schema, and do not include transcripts, audio,
device labels, room tokens, authorization headers, upstream responses, or
arbitrary exception objects. This telemetry is background-only and must not add
a debug panel to the avatar surface.

On hangup, stop the health check, disconnect the room, detach tracks, remove
generated audio elements, and restore the still portrait.

The token endpoint must remain server-side and grant only the room permissions
the participant needs. Never place provider secrets in HTML, JavaScript bundles,
query strings, or browser storage. An unauthenticated endpoint is permitted only
for a loopback-bound development server. For a hosted app, follow
[security-and-privacy.md](security-and-privacy.md): authenticate the caller,
rate-limit starts, generate opaque room and participant identities server-side,
reject browser-selected room configuration or grants, and issue a short-lived
token limited to subscription and microphone publication.

Insert status and error strings with `textContent`, not `innerHTML`. A hosted app
should send a restrictive Content Security Policy and Permissions Policy that
allow only its own assets, the configured LiveKit connection, and microphone
capture needed for an active call.

## Visual direction

Let the avatar dominate. Prefer a full-bleed stage with small floating call
controls. Preserve consistent framing when switching from the reference portrait
to the live track: default the remote video to `object-fit: contain` and center it
so the face and head are never cropped. Letterboxing is preferable to changing
the character's apparent framing. Use `cover` only when the user explicitly
wants an edge-to-edge crop or the generated video has a known matching aspect
ratio. Status copy should remain secondary and disappear when the avatar is
ready. The user should perceive a conversation with a character, not an API
dashboard.
