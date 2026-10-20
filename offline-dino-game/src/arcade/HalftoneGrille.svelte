<script lang="ts">
	/**
	 * The cabinet's speaker grille, in halftone: a field of small dots that
	 * swell with the voice actually coming out, read off an analyser on the
	 * audio path. The spectrum is mirrored about the centre, low frequencies in
	 * the middle, so a voice reads as a shape breathing out from the centre.
	 *
	 * The loudest dots, at the heart of the shape, light lime, like a meter's
 * last segment.
 *
 * It is the one thing on the page that moves with the model, and it only
	 * moves while there is sound: the loop runs while `active`, lets the dots
	 * settle, then stops. Under reduced motion it stays a still grille.
	 */
	import { onMount } from 'svelte';
	import { cssToken } from '$lib/cssToken';
	import { fitCanvas, eachCell, reducedMotion } from './halftone';

	interface Props {
		analyser: AnalyserNode | null;
		active: boolean;
		class?: string;
	}

	let { analyser, active, class: className = '' }: Props = $props();

	/** The bins a voice lives in: up to ~4.5 kHz at 24 kHz, ~9 at 48. */
	const BANDS = 48;

	let box: HTMLDivElement;
	let canvas: HTMLCanvasElement;
	let ctx: CanvasRenderingContext2D | null = null;
	let width = 0;
	let height = 0;
	let pitch = 9;
	let raf = 0;
	let running = false;
	let bins = new Uint8Array(128);
	const levels = new Float32Array(BANDS);
	let colors = { ink: '#f2f2f2', idle: '#3d3d3d', peak: '#daff52' };

	function layout() {
		width = box.clientWidth;
		height = box.clientHeight;
		if (!width || !height) return;
		ctx = fitCanvas(canvas, width, height);
		pitch = width < 480 ? 7 : 9;
		draw();
	}

	function sample() {
		if (!analyser) {
			for (let i = 0; i < BANDS; i++) levels[i] *= 0.85;
			return;
		}
		if (bins.length !== analyser.frequencyBinCount) bins = new Uint8Array(analyser.frequencyBinCount);
		analyser.getByteFrequencyData(bins);
		for (let i = 0; i < BANDS; i++) {
			// Fast up, slow down: a dot jumps with a syllable and sinks after it.
			const next = Math.max(0, (bins[i + 1] - 70) / 150);
			levels[i] = next > levels[i] ? next : levels[i] * 0.86 + next * 0.14;
		}
	}

	function strength(x: number, y: number): number {
		const d = Math.abs(x / width - 0.5) * 2;
		const band = Math.min(BANDS - 1, Math.floor(Math.pow(d, 1.25) * BANDS * 0.8));
		const level = Math.min(1, levels[band] * (1.15 - d * 0.4));
		if (level < 0.02) return 0;
		const e = Math.abs(y / height - 0.5) * 2;
		return Math.min(1, Math.max(0, (level * 1.15 - e) / 0.22));
	}

	function draw() {
		if (!ctx) return;
		ctx.clearRect(0, 0, width, height);
		const lit: number[] = [];
		const dim: number[] = [];
		const peak: number[] = [];
		eachCell(width, height, pitch, (x, y) => {
			const k = strength(x, y);
			(k > 0.99 && Math.abs(y / height - 0.5) < 0.05 ? peak : k > 0.04 ? lit : dim).push(
				x,
				y,
				pitch * 0.5 * (0.26 + 0.66 * k)
			);
		});
		for (const [list, color] of [
			[dim, colors.idle],
			[lit, colors.ink],
			[peak, colors.peak]
		] as const) {
			ctx.fillStyle = color;
			ctx.beginPath();
			for (let i = 0; i < list.length; i += 3) {
				ctx.moveTo(list[i] + list[i + 2], list[i + 1]);
				ctx.arc(list[i], list[i + 1], list[i + 2], 0, Math.PI * 2);
			}
			ctx.fill();
		}
	}

	function loop() {
		sample();
		draw();
		const settled = levels.every((l) => l < 0.01);
		if (!active && settled) {
			running = false;
			levels.fill(0);
			draw();
			return;
		}
		raf = requestAnimationFrame(loop);
	}

	$effect(() => {
		if (active && !running && !reducedMotion()) {
			running = true;
			raf = requestAnimationFrame(loop);
		}
	});

	onMount(() => {
		colors = {
			ink: cssToken('--phonon-ink', colors.ink),
			idle: cssToken('--phonon-grille', colors.idle),
			peak: cssToken('--phonon-accent', colors.peak)
		};
		layout();
		const observer = new ResizeObserver(layout);
		observer.observe(box);
		return () => {
			observer.disconnect();
			cancelAnimationFrame(raf);
			running = false;
		};
	});
</script>

<div bind:this={box} class="relative {className}" aria-hidden="true">
	<canvas bind:this={canvas} class="absolute inset-0 block"></canvas>
</div>
