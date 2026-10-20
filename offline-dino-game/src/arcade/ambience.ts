/**
 * The arcade around the cabinet, for the ear: the room you would hear standing
 * at it. A low room tone and a murmur under everything, and from the other
 * machines, scattered left and right and a little far off (low-passed, a touch
 * of room reverb): chiptune phrases, someone mashing buttons, a coin going in,
 * a laser, a boom, a jingle. Henry Heffernan's site does the same with an
 * office: the ambience is what makes the machine feel like it stands somewhere.
 *
 * Synthesized, like the cabinet's own sounds (`show/sfx.ts`), so it works
 * with no file at all. A music track sits on top once there is one
 * (`ARCADE_MUSIC_SRC`).
 *
 * It sits well under the voice, and `duck()` lowers it further while Phonon is
 * speaking: the model is what people came to hear.
 *
 * Events are scheduled on the audio clock a little ahead of time
 * (`schedule()`), not fired from timers, so the room keeps time even when the
 * main thread is busy, and a stretch of it can be rendered offline to measure.
 */

/** Master level while on. Measured offline: about -44 dBFS RMS, peaks near -20, some 24 dB under a voice. */
const LEVEL = 0.6;
/** Under a voice: about -14 dB below that. */
const DUCKED = 0.2;
/** How far ahead the live loop schedules, and how often it looks. */
const AHEAD_S = 2;
const LOOK_MS = 500;
/** The other machines against the room tone: they are the arcade, the tone is the room. */
const EVENTS = 4;
/** Seconds between two things happening somewhere in the room. */
const GAP_S: [number, number] = [0.9, 3.4];

/**
 * The music track under the room, or null for the room alone. Served from
 * `static/`, so a path like `/phonon/arcade-music.mp3`: drop the file there and
 * set this. Licensed through Gradium's Artlist Enterprise agreement, which is
 * the plan that covers "app, software, games and their end-users"; a track
 * downloaded on a standard plan would not be. The shortlist is in
 * docs/phonon-arcade.md.
 */
export const ARCADE_MUSIC_SRC: string | null = null;

const rand = (lo: number, hi: number) => lo + Math.random() * (hi - lo);
const pick = <T>(items: readonly T[]) => items[Math.floor(Math.random() * items.length)];

type Kind = 'chip' | 'mash' | 'coin' | 'laser' | 'boom' | 'jingle';
/** How often each happens, out of the total. */
const WEIGHTS: [Kind, number][] = [
	['chip', 34],
	['mash', 24],
	['laser', 14],
	['coin', 10],
	['boom', 9],
	['jingle', 9]
];

/** C minor pentatonic over two octaves, in Hz: what the other cabinets play in. */
const SCALE = [0, 3, 5, 7, 10, 12, 15, 17, 19, 22].map((s) => 523.25 * 2 ** (s / 12));

export class ArcadeAmbience {
	private master: GainNode;
	private duckGain: GainNode;
	private send: GainNode;
	private events: GainNode;
	private noise: AudioBuffer;
	private bed: AudioScheduledSourceNode[] = [];
	private music: HTMLAudioElement | null = null;
	private timer: ReturnType<typeof setInterval> | undefined;
	private nextAt = 0;
	private on = false;

	constructor(
		private ctx: BaseAudioContext,
		out: AudioNode = ctx.destination,
		private musicSrc: string | null = ARCADE_MUSIC_SRC
	) {
		this.master = ctx.createGain();
		this.master.gain.value = 0;
		this.master.connect(out);
		this.duckGain = ctx.createGain();
		this.duckGain.connect(this.master);
		const reverb = ctx.createConvolver();
		reverb.buffer = this.impulse(1.8);
		this.send = ctx.createGain();
		this.send.gain.value = 0.55;
		this.send.connect(reverb);
		reverb.connect(this.duckGain);
		this.events = ctx.createGain();
		this.events.gain.value = EVENTS;
		this.events.connect(this.duckGain);
		this.events.connect(this.send);
		this.noise = this.brownNoise(4);
	}

	get enabled(): boolean {
		return this.on;
	}

	setEnabled(on: boolean): void {
		if (on === this.on) return;
		this.on = on;
		const now = this.ctx.currentTime;
		const g = this.master.gain;
		g.cancelScheduledValues(now);
		g.setValueAtTime(g.value, now);
		g.linearRampToValueAtTime(on ? LEVEL : 0, now + (on ? 1.2 : 0.4));
		if (on) {
			this.startBed();
			this.nextAt = now + 0.6;
			this.schedule(now, now + AHEAD_S);
			this.timer = setInterval(() => {
				const t = this.ctx.currentTime;
				this.schedule(t, t + AHEAD_S);
			}, LOOK_MS);
			void this.music?.play().catch(() => {});
		} else {
			clearInterval(this.timer);
			const bed = this.bed;
			this.bed = [];
			setTimeout(() => bed.forEach((s) => s.stop()), 500);
			this.music?.pause();
		}
	}

	/** Lower the room while a voice speaks; lift it after, more slowly. */
	duck(on: boolean): void {
		const now = this.ctx.currentTime;
		const g = this.duckGain.gain;
		g.cancelScheduledValues(now);
		g.setValueAtTime(g.value, now);
		g.linearRampToValueAtTime(on ? DUCKED : 1, now + (on ? 0.15 : 1.2));
	}

	/**
	 * Put events on the clock from `from` to `to`, context seconds. The live
	 * loop calls this a little ahead; an offline context can call it once for a
	 * whole stretch and render it.
	 */
	schedule(from: number, to: number): void {
		let at = Math.max(from, this.nextAt);
		while (at < to) {
			this.event(at);
			at += rand(...GAP_S);
		}
		this.nextAt = at;
	}

	/** The room's bed, with no events: for an offline render. */
	startBed(): void {
		if (this.bed.length) return;
		const ctx = this.ctx;
		// Room tone: brown noise, low-passed to a rumble.
		const tone = this.loop();
		const low = this.filter('lowpass', 300);
		const toneGain = this.gain(0.035);
		tone.connect(low).connect(toneGain).connect(this.duckGain);
		// The murmur of a room: band-passed noise, breathing slowly.
		const murmur = this.loop();
		const band = this.filter('bandpass', 520, 0.6);
		const murmurGain = this.gain(0.022);
		const lfo = ctx.createOscillator();
		lfo.frequency.value = 0.11;
		const depth = this.gain(0.012);
		lfo.connect(depth).connect(murmurGain.gain);
		murmur.connect(band).connect(murmurGain).connect(this.duckGain);
		murmurGain.connect(this.send);
		lfo.start();
		this.bed = [tone, murmur, lfo];

		if (this.musicSrc && 'createMediaElementSource' in ctx && !this.music) {
			const el = new Audio(this.musicSrc);
			el.loop = true;
			const source = (ctx as AudioContext).createMediaElementSource(el);
			source.connect(this.filter('lowpass', 6000)).connect(this.gain(0.35)).connect(this.duckGain);
			this.music = el;
		}
	}

	dispose(): void {
		clearInterval(this.timer);
		this.bed.forEach((s) => {
			try {
				s.stop();
			} catch {
				/* never started */
			}
		});
		this.bed = [];
		this.music?.pause();
		this.music = null;
		this.master.disconnect();
	}

	// ---- One thing happening somewhere in the room ----------------------------------

	private event(at: number): void {
		const total = WEIGHTS.reduce((n, [, w]) => n + w, 0);
		let roll = Math.random() * total;
		const kind = WEIGHTS.find(([, w]) => (roll -= w) < 0)?.[0] ?? 'chip';
		// Somewhere left or right, and a little far: further means duller.
		const out = this.place(rand(-0.85, 0.85), rand(1600, 3400));
		this[kind](at, out);
	}

	/** Another cabinet's tune: a few notes walking the scale. */
	private chip(at: number, out: AudioNode): void {
		const type = pick(['square', 'triangle', 'square'] as const);
		const step = rand(0.075, 0.12);
		let i = Math.floor(rand(0, SCALE.length - 4));
		const count = Math.floor(rand(4, 10));
		for (let n = 0; n < count; n++) {
			i = Math.max(0, Math.min(SCALE.length - 1, i + pick([-2, -1, 1, 1, 2, 3])));
			this.tone(out, type, SCALE[i], SCALE[i], at + n * step, step * 0.9, 0.03);
		}
	}

	/** Someone mashing a button, then the stick clacking back. */
	private mash(at: number, out: AudioNode): void {
		const count = Math.floor(rand(3, 9));
		const gap = rand(0.06, 0.11);
		for (let n = 0; n < count; n++) {
			this.burst(out, at + n * gap + rand(0, 0.015), 0.025, rand(1700, 2700), 0.07);
			if (n % 2 === 0) this.tone(out, 'triangle', 190, 80, at + n * gap, 0.05, 0.04);
		}
	}

	/** A coin going into a machine across the room. */
	private coin(at: number, out: AudioNode): void {
		this.tone(out, 'square', 988, 988, at, 0.07, 0.025);
		this.tone(out, 'square', 1319, 1319, at + 0.07, 0.24, 0.025);
		this.tone(out, 'sine', 4200, 3900, at + 0.01, 0.12, 0.015);
	}

	private laser(at: number, out: AudioNode): void {
		const shots = Math.floor(rand(1, 4));
		for (let n = 0; n < shots; n++) this.tone(out, 'square', 1500, 170, at + n * 0.13, 0.2, 0.022);
	}

	private boom(at: number, out: AudioNode): void {
		const src = this.ctx.createBufferSource();
		src.buffer = this.noise;
		const low = this.filter('lowpass', 900);
		low.frequency.setValueAtTime(900, at);
		low.frequency.exponentialRampToValueAtTime(60, at + 0.6);
		const g = this.gain(0.0001);
		g.gain.setValueAtTime(0.07, at);
		g.gain.exponentialRampToValueAtTime(0.0001, at + 0.7);
		src.connect(low).connect(g).connect(out);
		src.start(at, rand(0, 3), 0.75);
	}

	/** A level cleared on somebody else's machine. */
	private jingle(at: number, out: AudioNode): void {
		const root = pick([784, 698, 880]);
		[1, 1.25, 1.5, 2].forEach((r, n) =>
			this.tone(out, 'square', root * r, root * r, at + n * 0.09, n === 3 ? 0.22 : 0.08, 0.024)
		);
	}

	// ---- Plumbing -----------------------------------------------------------------------

	/** Where an event sits: panned, low-passed for distance, with some room on it. */
	private place(pan: number, cutoff: number): AudioNode {
		const filter = this.filter('lowpass', cutoff);
		const panner = this.ctx.createStereoPanner();
		panner.pan.value = pan;
		filter.connect(panner).connect(this.events);
		return filter;
	}

	private tone(
		out: AudioNode,
		type: OscillatorType,
		from: number,
		to: number,
		at: number,
		duration: number,
		volume: number
	): void {
		const osc = this.ctx.createOscillator();
		const g = this.ctx.createGain();
		osc.type = type;
		osc.frequency.setValueAtTime(from, at);
		osc.frequency.exponentialRampToValueAtTime(to, at + duration);
		g.gain.setValueAtTime(0.0001, at);
		g.gain.linearRampToValueAtTime(volume, at + 0.005);
		g.gain.exponentialRampToValueAtTime(0.0001, at + duration);
		osc.connect(g).connect(out);
		osc.start(at);
		osc.stop(at + duration + 0.02);
	}

	private burst(out: AudioNode, at: number, duration: number, freq: number, volume: number): void {
		const src = this.ctx.createBufferSource();
		src.buffer = this.noise;
		const band = this.filter('bandpass', freq, 1.4);
		const g = this.gain(0.0001);
		g.gain.setValueAtTime(volume, at);
		g.gain.exponentialRampToValueAtTime(0.0001, at + duration);
		src.connect(band).connect(g).connect(out);
		src.start(at, rand(0, 3), duration + 0.02);
	}

	private loop(): AudioBufferSourceNode {
		const src = this.ctx.createBufferSource();
		src.buffer = this.noise;
		src.loop = true;
		src.start();
		return src;
	}

	private filter(type: BiquadFilterType, freq: number, q = 0.7): BiquadFilterNode {
		const f = this.ctx.createBiquadFilter();
		f.type = type;
		f.frequency.value = freq;
		f.Q.value = q;
		return f;
	}

	private gain(value: number): GainNode {
		const g = this.ctx.createGain();
		g.gain.value = value;
		return g;
	}

	/** Brown noise, which is what a room sounds like once you stop listening for it. */
	private brownNoise(seconds: number): AudioBuffer {
		const length = Math.round(this.ctx.sampleRate * seconds);
		const buffer = this.ctx.createBuffer(1, length, this.ctx.sampleRate);
		const data = buffer.getChannelData(0);
		let last = 0;
		for (let i = 0; i < length; i++) {
			last = (last + 0.02 * (Math.random() * 2 - 1)) / 1.02;
			data[i] = last * 3.5;
		}
		return buffer;
	}

	/** A small hall: two channels of noise, decaying. */
	private impulse(seconds: number): AudioBuffer {
		const length = Math.round(this.ctx.sampleRate * seconds);
		const buffer = this.ctx.createBuffer(2, length, this.ctx.sampleRate);
		for (let c = 0; c < 2; c++) {
			const data = buffer.getChannelData(c);
			for (let i = 0; i < length; i++) data[i] = (Math.random() * 2 - 1) * (1 - i / length) ** 2.6;
		}
		return buffer;
	}
}
