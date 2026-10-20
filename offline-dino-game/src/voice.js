// Phonon, running in this tab (WebAssembly, in a worker), and a scheduler that plays its audio as
// a gapless stream of lines. Lines can be dropped before they start (a new topic) or cut mid-word
// (a crash), and the scheduler reports which line is playing for the captions.
import { PhononTTS } from 'phonon-tts';

/** The voices on the picker, by name. */
export const VOICES = ['Toby', 'Russell', 'Freya', 'Harper'];
// Their files in gradium/phonon-voices, by voice id (the catalog's voices.jsonl lists them all).
const VOICE_FILES = {
  Toby: 'dME3IWyZBvmh1n1q',
  Russell: '_6Aslh2DxfmnRLmP',
  Freya: 'GgfEkEJtxZR7gnpy',
  Harper: '4SZHfMpw-p46Ywgs',
};

// Phonon 31M (Apache-2.0), straight from Hugging Face, which allows cross-origin requests. Each repo
// is pinned to a commit, so a cached file is never served after the repo changes. phonon-tts keeps
// the files in the browser's Cache API after the first visit, so it runs offline.
const MODEL_URL = 'https://huggingface.co/gradium/phonon-31m-en/resolve/39e33dec4ea8bb6e7d81385d6a634456f08410e2';
const VOICES_URL = 'https://huggingface.co/gradium/phonon-voices/resolve/0ee17205f254b5abc43b266c8a0f215565c352f7';

const MODEL = {
  weights: { q8: `${MODEL_URL}/model.q8.gguf` },
  tokenizer: `${MODEL_URL}/tokenizer.json`,
  config: `${MODEL_URL}/config.json`,
  voices: Object.fromEntries(Object.entries(VOICE_FILES).map(([name, id]) => [name, `${VOICES_URL}/voices/${id}.safetensors`])),
  defaultVoice: VOICES[0],
};

export async function loadPhonon(onProgress) {
  const files = new Map();
  return PhononTTS.load({
    lang: 'en',
    model: MODEL,
    // Only the default voice up front: another is fetched the first time it speaks, so a voice
    // that goes missing from the server breaks only itself, not the setup.
    voices: [MODEL.defaultVoice],
    onProgress: ({ file, loaded, total }) => {
      files.set(file, { loaded, total: total || loaded });
      let l = 0, t = 0;
      for (const f of files.values()) { l += f.loaded; t += f.total; }
      onProgress(t ? l / t : 0, l);
    },
  });
}

export class Speaker {
  /** `out` is where Rex is heard: the speakers, or the page's meter and volume fader. */
  constructor(tts, ctx, out = ctx.destination) {
    this.tts = tts;
    this.ctx = ctx;
    this.voice = VOICES[0];
    this.lines = [];
    this.playhead = 0;
    this.lastFirstAudioMs = null;   // from asking for a line to its first sound being scheduled
    this.bus = ctx.createGain();
    this.bus.connect(out);
    this.newEpoch();
  }

  newEpoch() {
    this.gain = this.ctx.createGain();
    this.gain.connect(this.bus);
  }

  setMuted(muted) {
    this.bus.gain.setTargetAtTime(muted ? 0 : 1, this.ctx.currentTime, 0.02);
  }

  /** Seconds of audio scheduled past now. */
  ahead() { return Math.max(0, this.playhead - this.ctx.currentTime); }

  /** The line being heard right now, if any. */
  current() {
    const t = this.ctx.currentTime;
    return this.lines.find((l) => !l.dropped && l.start <= t && t < l.end) || null;
  }

  /** Synthesizes `text` and schedules it after everything already queued. Resolves once the
   *  whole line is scheduled (well before it finishes playing), with the line, or null if aborted
   *  before any of it was scheduled. */
  async speak(text, signal) {
    const line = { text, start: Infinity, end: 0, sources: [], gain: this.gain, cut: false, dropped: false };
    this.lines.push(line);
    this.lines = this.lines.slice(-40);
    const rate = this.tts.sampleRate;
    const asked = performance.now();
    try {
      for await (const pcm of this.tts.stream(text, { voice: this.voice, signal })) {
        if (signal?.aborted || line.dropped || line.cut) break;
        if (!line.sources.length) this.lastFirstAudioMs = performance.now() - asked;
        const at = Math.max(this.playhead, this.ctx.currentTime + 0.06);
        const src = this.play(pcm, rate, at, line.gain);
        line.sources.push(src);
        line.start = Math.min(line.start, at);
        line.end = at + pcm.length / rate;
        this.playhead = line.end;
      }
    } catch (err) {
      if (!signal?.aborted) throw err;
    }
    if (!line.sources.length) { line.dropped = true; return null; }
    return line;
  }

  play(pcm, rate, at, gain) {
    const buf = this.ctx.createBuffer(1, pcm.length, rate);
    buf.getChannelData(0).set(pcm);
    const src = this.ctx.createBufferSource();
    src.buffer = buf;
    src.connect(gain);
    src.start(at);
    return src;
  }

  /** Lets the line being heard finish and drops every line queued after it. */
  dropQueued() {
    const t = this.ctx.currentTime;
    for (const l of this.lines) {
      if (l.dropped || l.start <= t) continue;
      l.dropped = true;
      for (const s of l.sources) try { s.stop(); } catch { /* not started */ }
    }
    const kept = this.lines.filter((l) => !l.dropped && l.end > t);
    this.playhead = Math.max(t, ...kept.map((l) => l.end));
  }

  /** Fades everything out right now. */
  cut() {
    const t = this.ctx.currentTime;
    const old = this.gain;
    old.gain.setValueAtTime(old.gain.value, t);
    old.gain.linearRampToValueAtTime(0, t + 0.06);
    for (const l of this.lines) {
      if (l.dropped || l.end <= t) continue;
      if (l.start > t) l.dropped = true;
      else { l.cut = true; l.end = t + 0.06; }
      for (const s of l.sources) try { s.stop(t + 0.08); } catch { /* fine */ }
    }
    setTimeout(() => old.disconnect(), 300);
    this.newEpoch();
    this.playhead = t;
  }

  /** Plays ready-made audio straight away, queued ahead of anything synthesized after it. */
  blurt(text, pcm) {
    const at = Math.max(this.playhead, this.ctx.currentTime + 0.02);
    const src = this.play(pcm, this.tts.sampleRate, at, this.gain);
    const line = { text, start: at, end: at + pcm.length / this.tts.sampleRate, sources: [src], gain: this.gain, cut: false, dropped: false };
    this.lines.push(line);
    this.playhead = line.end;
    return line;
  }
}

