<script lang="ts">
	/**
	 * The room the cabinet stands in: rings of halftone spreading out from
	 * behind it, the way sound would, fading before the edges. The website hangs
	 * halftone sculpture around Phonon; this is the same print screen with
	 * nothing borrowed. Static: drawn on resize and never again.
	 */
	import { onMount } from 'svelte';
	import { cssToken } from '$lib/cssToken';
	import { fitCanvas, dotPath } from './halftone';

	let canvas: HTMLCanvasElement;

	const smooth = (a: number, b: number, x: number) => {
		const t = Math.min(1, Math.max(0, (x - a) / (b - a)));
		return t * t * (3 - 2 * t);
	};

	function draw() {
		const width = window.innerWidth;
		const height = window.innerHeight;
		const ctx = fitCanvas(canvas, width, height, 1.5);
		if (!ctx) return;
		const pitch = width < 640 ? 8 : 10;
		const cx = width / 2;
		const cy = height * 0.48;
		const reach = Math.max(width, height) * 0.62;
		ctx.fillStyle = cssToken('--phonon-line', '#262626');
		dotPath(ctx, width, height, pitch, (x, y) => {
			const r = Math.hypot(x - cx, (y - cy) * 1.15) / reach;
			const rings = 0.5 + 0.5 * Math.cos(r * Math.PI * 2 * 4.2);
			const envelope = smooth(0.28, 0.5, r) * (1 - smooth(0.78, 1.18, r));
			return pitch * 0.44 * Math.sqrt(rings * rings * envelope);
		});
		ctx.fill();
	}

	onMount(() => {
		draw();
		let frame = 0;
		const onResize = () => {
			cancelAnimationFrame(frame);
			frame = requestAnimationFrame(draw);
		};
		window.addEventListener('resize', onResize);
		return () => {
			window.removeEventListener('resize', onResize);
			cancelAnimationFrame(frame);
		};
	});
</script>

<canvas bind:this={canvas} aria-hidden="true" class="pointer-events-none fixed inset-0 block"></canvas>
