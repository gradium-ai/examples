/**
 * The runner's sound effects, synthesized rather than shipped: a jump blip, a
 * crash thud, the two-note chime every 100 points, and the cabinet's own: a
 * coin, a menu blip, the continue countdown's tick and a pause. In the spirit
 * of Chrome's offline game (square waves, a few dozen milliseconds each).
 * They share Rex's AudioContext so the page asks for audio once, and sit well
 * under his voice. They play into `out`, the context's speakers unless the
 * page passes a node of its own (the arcade's master volume).
 */

const VOLUME = 0.06;

function tone(
	out: AudioNode,
	type: OscillatorType,
	from: number,
	to: number,
	at: number,
	duration: number,
	volume = VOLUME
) {
	const ctx = out.context;
	const osc = ctx.createOscillator();
	const gain = ctx.createGain();
	osc.type = type;
	osc.frequency.setValueAtTime(from, at);
	osc.frequency.exponentialRampToValueAtTime(to, at + duration);
	gain.gain.setValueAtTime(volume, at);
	gain.gain.exponentialRampToValueAtTime(0.0001, at + duration);
	osc.connect(gain).connect(out);
	osc.start(at);
	osc.stop(at + duration + 0.02);
}

export class Sfx {
	muted = false;

	constructor(
		private ctx: AudioContext,
		private out: AudioNode = ctx.destination
	) {}

	jump(): void {
		if (this.muted) return;
		tone(this.out, 'square', 620, 940, this.ctx.currentTime, 0.07);
	}

	hit(): void {
		if (this.muted) return;
		const t = this.ctx.currentTime;
		tone(this.out, 'square', 180, 60, t, 0.18, VOLUME * 1.2);
		tone(this.out, 'triangle', 90, 40, t, 0.22, VOLUME * 1.5);
	}

	/** A coin dropping in: two bright notes, the second held. */
	coin(): void {
		if (this.muted) return;
		const t = this.ctx.currentTime;
		tone(this.out, 'square', 988, 988, t, 0.07);
		tone(this.out, 'square', 1319, 1319, t + 0.07, 0.28);
	}

	/** Moving the menu cursor. */
	select(): void {
		if (this.muted) return;
		tone(this.out, 'square', 440, 440, this.ctx.currentTime, 0.04, VOLUME * 0.7);
	}

	/** One second of the continue countdown. */
	tick(): void {
		if (this.muted) return;
		tone(this.out, 'triangle', 330, 330, this.ctx.currentTime, 0.05, VOLUME * 0.8);
	}

	/** Pause and resume: down, or up. */
	pause(on: boolean): void {
		if (this.muted) return;
		const t = this.ctx.currentTime;
		const [a, b] = on ? [660, 330] : [330, 660];
		tone(this.out, 'square', a, a, t, 0.06);
		tone(this.out, 'square', b, b, t + 0.07, 0.08);
	}

	/** Game over: three falling notes. */
	over(): void {
		if (this.muted) return;
		const t = this.ctx.currentTime;
		tone(this.out, 'square', 523, 523, t, 0.14);
		tone(this.out, 'square', 392, 392, t + 0.16, 0.14);
		tone(this.out, 'square', 262, 196, t + 0.32, 0.4);
	}

	reached(): void {
		if (this.muted) return;
		const t = this.ctx.currentTime;
		tone(this.out, 'square', 880, 880, t, 0.08);
		tone(this.out, 'square', 1320, 1320, t + 0.09, 0.12);
	}

	// ---- The arcade cabinet's own (the classic page plays none of these) ----

	private noise: AudioBuffer | null = null;

	/** A burst of filtered noise: the mechanical half of a key or a button. */
	private burst(at: number, duration: number, freq: number, volume: number): void {
		if (!this.noise) {
			const length = Math.round(this.ctx.sampleRate * 0.2);
			this.noise = this.ctx.createBuffer(1, length, this.ctx.sampleRate);
			const data = this.noise.getChannelData(0);
			for (let i = 0; i < length; i++) data[i] = Math.random() * 2 - 1;
		}
		const source = this.ctx.createBufferSource();
		source.buffer = this.noise;
		const filter = this.ctx.createBiquadFilter();
		filter.type = 'bandpass';
		filter.frequency.value = freq;
		filter.Q.value = 1.2;
		const gain = this.ctx.createGain();
		gain.gain.setValueAtTime(volume, at);
		gain.gain.exponentialRampToValueAtTime(0.0001, at + duration);
		source.connect(filter).connect(gain).connect(this.out);
		source.start(at, Math.random() * 0.15, duration + 0.02);
	}

	/** A key on the cabinet's keyboard: a short tick, never twice the same. */
	key(): void {
		if (this.muted) return;
		this.burst(this.ctx.currentTime, 0.03, 2600 + Math.random() * 1600, VOLUME * 0.9);
	}

	/** An arcade button going down: a click with a little body under it. */
	clack(): void {
		if (this.muted) return;
		const t = this.ctx.currentTime;
		this.burst(t, 0.04, 1800, VOLUME * 1.2);
		tone(this.out, 'triangle', 160, 70, t, 0.06, VOLUME * 0.8);
	}

	/** The tube warming up: a low thump and the hiss of the screen charging. */
	powerOn(): void {
		if (this.muted) return;
		const t = this.ctx.currentTime;
		tone(this.out, 'sine', 70, 42, t, 0.35, VOLUME * 2);
		this.burst(t + 0.02, 0.18, 5200, VOLUME * 0.6);
	}

	/** PRESS START answered: four notes up. */
	start(): void {
		if (this.muted) return;
		const t = this.ctx.currentTime + 0.12;
		[523, 659, 784, 1047].forEach((f, i) => tone(this.out, 'square', f, f, t + i * 0.07, i === 3 ? 0.22 : 0.06));
	}

	/** A new best time: the milestone chime, twice, the second higher. */
	record(): void {
		if (this.muted) return;
		const t = this.ctx.currentTime;
		[880, 1320, 1175, 1760].forEach((f, i) => tone(this.out, 'square', f, f, t + i * 0.09, i === 3 ? 0.24 : 0.08));
	}
}
