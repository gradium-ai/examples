// The show runner. Offline FM is a roast show: Rex mocks the person playing, with the session's real
// numbers. Every line is written in lines.js; Phonon voices each one live as the game happens.
// Game events (a run starting, a crash, a milestone, night) get a reply as soon as Rex is free, and
// between them he fills short pauses with general roasts, the time played, the stats and the
// listener's topic. Each kind of line is dealt from its own shuffled deck, so nothing repeats until
// that deck runs out. A crash cuts Rex off with a ready-made jab, and a new topic lets the current
// line finish and drops the rest.
import { LINES, OBSTACLES, TOPICS } from './lines.js';

const YELPS = ['Pathetic.', 'Seriously?', 'There it is.', 'Called it.', 'Embarrassing.', 'Unbelievable.', 'Come on.', 'Classic you.'];

const PAUSE = [1.5, 4];   // seconds of quiet between unprompted lines
const PROMPT = 0.15;      // Rex starts his next line once less than this much speech is left

export class Podcast {
  constructor({ speaker, onError = (message) => {} }) {
    this.speaker = speaker;
    this.onError = onError;
    this.topic = null;
    this.pending = [];       // replies to game events, said before anything else
    this.decks = new Map();  // deck name -> lines left to deal
    this.last = new Map();   // deck name -> the line dealt last, so a reshuffle does not repeat it
    this.yelps = new Map();  // voice -> [{ text, pcm }]
    this.lastYelps = [];
    this.running = false;
    this.lastTimeLine = 0;
    this.stats = { since: performance.now(), runs: 0, deaths: 0, best: 0, score: 0, obstacle: 'a cactus' };
  }

  start() {
    if (this.running) return;
    this.running = true;
    this.stats.since = performance.now();
    this.pending = [this.deal('opening')];
    this.loop();
  }

  /** Another voice: what was queued is in the old one, and the crash jabs need making again. */
  setVoice(voice) {
    if (voice === this.speaker.voice) return;
    this.ctrl?.abort();
    this.speaker.cut();
    this.speaker.voice = voice;
    this.pending = [];
    this.prepareYelps(voice).catch((err) => console.warn('[podcast] jabs', err));
  }

  /** The listener picked a topic, or `null` to drop it. */
  setTopic(id) {
    this.topic = TOPICS[id] ? id : null;
    if (!this.topic) return;
    this.speaker.dropQueued();
    this.pending = [this.deal(`topic:${id}`)];
  }

  gameEvent(e) {
    const st = this.stats;
    switch (e.type) {
      case 'start':
      case 'restart':
        st.runs++;
        st.score = 0;
        this.pending = [this.deal(st.runs === 1 ? 'start' : 'restart')];
        break;
      case 'milestone':
        st.score = e.score;
        if (this.pending.length < 2) this.pending.push(this.deal('milestone'));
        break;
      case 'night':
        this.pending.push(this.deal('night'));
        break;
      case 'idle':
        if (!this.pending.length) this.pending.push(this.deal('idle'));
        break;
      case 'crash':
        st.deaths++;
        st.score = e.score;
        st.best = Math.max(st.best, e.best, e.score);
        st.obstacle = OBSTACLES[e.obstacle];
        this.ctrl?.abort();
        this.speaker.cut();
        this.yelp();
        this.pending = [this.deal(crashDeck(e, st))];
        break;
      default:
    }
  }

  /** Synthesizes the crash jabs for a voice ahead of time, so one plays the instant Rex crashes. */
  async prepareYelps(voice) {
    if (this.yelps.has(voice)) return;
    const clips = [];
    this.yelps.set(voice, clips);
    for (const text of YELPS) {
      const pcm = await this.speaker.tts.synth(text, { voice, temperature: 0.5 });
      clips.push({ text, pcm: trimLeading(pcm) });
    }
  }

  yelp() {
    const clips = (this.yelps.get(this.speaker.voice) || []).filter((c) => !this.lastYelps.includes(c.text));
    if (!clips.length) return;
    const { text, pcm } = clips[Math.floor(Math.random() * clips.length)];
    this.lastYelps = [text, ...this.lastYelps].slice(0, 3);
    this.speaker.blurt(text, pcm);
  }

  async loop() {
    let quietUntil = 0;
    while (this.running) {
      // Wait until Rex is nearly done talking; an event's reply goes straight on, anything else
      // waits out a short pause first.
      await until(() => this.speaker.ahead() < PROMPT && (this.pending.length > 0 || performance.now() >= quietUntil));
      const text = this.pending.shift() || this.chatter();
      const ctrl = (this.ctrl = new AbortController());
      try {
        await this.speaker.speak(text, ctrl.signal);
      } catch (err) {
        if (ctrl.signal.aborted) continue;
        console.error('[podcast]', err);
        this.onError(err.message || String(err));
        await sleep(1500);
      }
      quietUntil = performance.now() + (this.speaker.ahead() + PAUSE[0] + Math.random() * (PAUSE[1] - PAUSE[0])) * 1000;
    }
  }

  /** An unprompted line: the topic, the time played, the stats or a general roast. */
  chatter() {
    const st = this.stats;
    if (!st.runs) return this.deal('waiting');
    const r = Math.random();
    if (this.topic && r < 0.45) return this.deal(`topic:${this.topic}`);
    const now = performance.now();
    if (r < 0.6 && now - st.since > 60000 && now - this.lastTimeLine > 90000) {
      this.lastTimeLine = now;
      return this.deal('time');
    }
    if (r < 0.75 && st.deaths >= 3) return this.deal('stats');
    return this.deal('roast');
  }

  /** The next line from a deck, with the session's numbers filled in. */
  deal(name) {
    let deck = this.decks.get(name);
    if (!deck?.length) {
      const lines = name.startsWith('topic:') ? TOPICS[name.slice(6)].lines : LINES[name];
      deck = shuffle(lines.slice());
      if (deck.length > 1 && deck.at(-1) === this.last.get(name)) deck.unshift(deck.pop());
      this.decks.set(name, deck);
    }
    const line = deck.pop();
    this.last.set(name, line);
    return this.fill(line);
  }

  fill(line) {
    const st = this.stats;
    const values = {
      score: st.score, best: st.best, deaths: st.deaths, runs: st.runs,
      obstacle: st.obstacle, time: duration(performance.now() - st.since),
    };
    return line.replace(/\{(\w+)\}/g, (m, key) => (key in values ? String(values[key]) : m));
  }
}

function crashDeck(e, st) {
  if (e.newHigh) return 'crashBest';
  if (st.deaths >= 5 && Math.random() < 0.4) return 'crashMany';
  return e.score < 100 ? 'crashEarly' : 'crash';
}

function duration(ms) {
  const s = Math.round(ms / 1000);
  const m = Math.floor(s / 60);
  if (!m) return `${s} seconds`;
  return `${m} minute${m === 1 ? '' : 's'} and ${s % 60} seconds`;
}

function shuffle(a) {
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

function trimLeading(pcm, threshold = 0.01) {
  let i = 0;
  while (i < pcm.length && Math.abs(pcm[i]) < threshold) i++;
  return pcm.subarray(Math.max(0, i - 240));
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
async function until(cond) { while (!cond()) await sleep(50); }
