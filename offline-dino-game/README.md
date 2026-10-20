# Offline Dino Game

An offline dino run in an arcade cabinet, with a roast show: Offline FM. While you run, Rex mocks you: how long you've
been playing, how often you crash, your scores, and a topic you pick under the game. The lines are
written in advance; Phonon, Gradium's on-device text-to-speech model, speaks each one live in the
tab with your numbers filled in. Once the page has loaded, it keeps going with the Wi-Fi off.

```bash
npm install
npm run dev        # http://127.0.0.1:5190
```

Open it and press **Tap to tune in** (or any key). The first time, this downloads Phonon (65 MB, from Hugging Face)
and gets the model ready; the game can be played meanwhile. After that it loads from the browser's cache in a couple of seconds; a build (`npm start`) also keeps the page files, so it reloads with no network.

## How it fits together

| | |
|---|---|
| Page | The Offline FM screen of the studio's Phonon arcade (`gradium-ai/studio`, `src/routes/models/text-to-speech/on-device/arcade/ArcadePage.svelte`), in Svelte 5 and Tailwind 4: the 3D room, the marquee, the screen in its bezel, the control deck (its keys press the game's keys), the volume fader, the stickers, the coin door and the maker's plate. `src/OfflineFm.svelte` is that page cut to this one screen. `src/arcade/` holds the studio's files it uses, unchanged apart from import paths and fewer words on screen: the game (`PhononRunner.svelte`: a neon dot-matrix Rex, one hit and GAME OVER with a CONTINUE? countdown, a pause screen, easter eggs), the room (`ArcadeRoom.svelte`, `arcadeGames.ts`), the halftone grille and backdrop, the room's synthesized ambience and the cabinet's sounds. `src/lib/` stands in for the studio's `$lib`: its English Phonon strings, and small versions of its Button, Kbd, Hint (tooltip) and Slider. |
| Voice | [`phonon-tts`](https://www.npmjs.com/package/phonon-tts) 0.4.0, Phonon's WebAssembly build from [xn-ptts](https://github.com/gradium-ai/xn-ptts), in a worker on 3 CPU threads (the page is cross-origin isolated for that). Weights come from Hugging Face ([`gradium/phonon-31m-en`](https://huggingface.co/gradium/phonon-31m-en), set in `src/voice.js`), with four of its English voices on the picker: Toby, Russell, Freya and Harper. `phonon-tts` keeps the files in the browser's Cache API. |
| Lines | `src/lines.js`: 250 lines, by kind (opening, waiting, start, restart, crash, early crash, new best, many crashes, milestone, night, idle, time played, stats, general roasts) plus five topics. Slots such as `{score}`, `{deaths}` and `{time}` are filled with the session's numbers before Phonon speaks the line. |
| Show runner | `src/podcast.js`. Game events (a run starting, a crash, a milestone, night falling, an idle Game Over screen) get a reply as soon as Rex is free. Between them he waits 1.5–4 s and says a general roast, the time played, the stats or a line on the chosen topic. Each kind is dealt from its own shuffled deck, so no line repeats until its deck runs out. A crash cuts Rex off with a pre-made jab ("Pathetic.", "Called it.") and his next line roasts the crash. A new topic lets the current line finish. |

URL option: `?voice=Freya` (or Harper, Russell, Toby) picks the voice.

## Hosting

The `Dockerfile` builds the site and serves it with nginx, which also sends the cross-origin
isolation headers.

```bash
docker build -t offline-dino-game . && docker run --rm -p 8080:8080 offline-dino-game   # http://localhost:8080
```

### Any other static host

```bash
npm run build      # dist/: the page and its code (about 17 MB); Phonon's weights load from Hugging Face
```

Every URL in the build is relative, so `dist/` works at a domain's root or under a sub-path.
Upload it to any HTTPS static host. Visitors open the link once with a connection and press the
button; that downloads Phonon and saves the page. After that it runs with no network,
reloads included.

- **No special headers needed.** Phonon wants cross-origin isolation for its threads; the service
  worker adds those headers itself, and the page reloads once on the first visit to pick them up.
  A host that does send `Cross-Origin-Opener-Policy: same-origin` and
  `Cross-Origin-Embedder-Policy: require-corp` skips that reload.

Tested on 2026-10-08 in Chrome 154: `dist/` served by a plain `python3 -m http.server` (no headers),
first visit, setup, then the server stopped and the network off. The page reloaded from the service
worker, still cross-origin isolated, setup finished in 2 s from cache, and Rex talked.

When testing, don't use DevTools' Offline switch for reloads: it makes Chrome skip the service
worker on navigation, so a reload looks broken. Stop the server or turn off Wi-Fi instead.

## Controls

Space or ↑ jumps, starts and confirms; ↓ ducks; ← → choose on the GAME OVER screen; Enter confirms; P or Esc
pauses; C inserts a coin; M turns the sound on and off; 0 goes back to the title screen. The deck's
buttons do the same as their keys. The topic buttons under the game (or Shift + 1 to 5) pick what Rex
riffs on; press the chosen one again to drop it. The first press anywhere turns the sound on and
starts loading Phonon; the game can be played while it loads.

The service worker that makes the page reload offline is only registered in a build (`npm start`);
the dev server removes any leftover one, since a stale copy would hide edits.

## Notes

- Chrome won't start Phonon's threaded workers in a hidden tab, so keep the tab visible while it loads.
- A run pauses when the tab is hidden, as a cabinet would if you walked off. The podcast keeps talking.
- Phonon's weights are not in this repository (the weights file is 65 MB). The page loads them from Hugging Face on the first visit.

## Licence

Apache-2.0, in [`LICENSE`](LICENSE). `phonon-tts` is MIT or Apache-2.0. IBM Plex
Mono (`src/fonts/IBMPlexMono-*`) is under the SIL Open Font License.
