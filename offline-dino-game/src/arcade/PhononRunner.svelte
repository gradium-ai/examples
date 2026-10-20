<script lang="ts">
	/**
	 * The offline runner as an arcade cabinet, in Phonon's dot matrix: a neon
	 * T-rex on a black ground, framed by the screens every cabinet has —
	 * START GAME with its attract loop, GAME OVER with a CONTINUE? countdown,
	 * a pause screen — under CRT scanlines.
	 *
	 * The run keeps what makes Chrome's game feel alive (ducking, pterodactyls
	 * once you are quick, clouds, night every 700 points, a blink and chime
	 * every hundred), and like Chrome's, one hit ends it.
	 *
	 * Easter eggs, for whoever goes looking: a coin slot (C), the Konami code,
	 * meteors every 500 points, stars at night, and a crown for a new hi-score.
	 *
	 * Keys: Space / ↑ jump, start and confirm; ↓ ducks; ← → move the GAME OVER
	 * cursor; Enter confirms; P or Esc pauses; C inserts a coin. Ignored while
	 * focus is in a field or on a control, so typing never makes the dino jump.
	 *
	 * It raises the events Offline FM's show reacts to (`onevent`) and does
	 * nothing else with them; what Rex says is the page's business.
	 */
	import { onMount } from 'svelte';
	import { cssToken } from '$lib/cssToken';
	import { Button } from '$lib/components/ui/button';
	import { Kbd } from '$lib/components/ui/kbd';
	import { t } from '$lib/i18n';
	import { marquee } from './marquee';
	import type { GameEvent } from './types';
	import type { Sfx } from './sfx';

	interface Props {
		onevent?: (event: GameEvent) => void;
		sfx?: Sfx | null;
	}

	let { onevent, sfx = null }: Props = $props();

	// ---- Sprites: one string per row, `x` is a dot. ------------------------

	const REX = [
		'.......xxxxxxx.',
		'......xx.xxxxxx',
		'......xxxxxxxxx',
		'......xxxxxxxxx',
		'......xxxxx....',
		'......xxxxxxx..',
		'x....xxxxx.....',
		'x...xxxxxxxx...',
		'xx.xxxxxxx.x...',
		'xxxxxxxxxx.....',
		'.xxxxxxxxx.....',
		'..xxxxxxxx.....',
		'...xxxxxx......'
	];
	const REX_DEAD_EYE = { row: 1, col: 8 };
	const LEGS = [
		['....xx.xx......', '....x...x......', '....xx..xx.....'],
		['....xxx.x......', '....x....x.....', '.........xx....'],
		['....xx.xx......', '....x...x......', '....x...x......']
	];
	const DUCK = [
		[
			'..............xxxxxx.',
			'x.............x.xxxxx',
			'xx...xxxxxxxxxxxxxxxx',
			'xxxxxxxxxxxxxxxxxxx..',
			'.xxxxxxxxxxxxxx.x....',
			'..xxxxxxxxxxxx.......',
			'...xx..xx............',
			'...x....x............'
		],
		[
			'..............xxxxxx.',
			'x.............x.xxxxx',
			'xx...xxxxxxxxxxxxxxxx',
			'xxxxxxxxxxxxxxxxxxx..',
			'.xxxxxxxxxxxxxx.x....',
			'..xxxxxxxxxxxx.......',
			'...xxx..x............',
			'.........xx..........'
		]
	];
	const CROWN = ['x.x.x', 'xxxxx', 'xxxxx'];
	const CACTUS = ['..x..', '..x..', 'x.x..', 'x.x.x', 'xxx.x', '..xxx', '..x..', '..x..', '..x..', '..x..'];
	const CACTUS_BIG = [
		'...x...',
		'..xxx..',
		'..xxx..',
		'x.xxx..',
		'x.xxx.x',
		'x.xxx.x',
		'xxxxx.x',
		'..xxxxx',
		'..xxx..',
		'..xxx..',
		'..xxx..',
		'..xxx..',
		'..xxx..'
	];
	const BIRD = [
		['....x.........', '...xx.........', '..xxxx........', 'xxxxxxxxxxxx..', '....xxxxxxxxxx', '.....xxxxxx...'],
		[
			'..............',
			'..............',
			'..xxx.........',
			'xxxxxxxxxxxx..',
			'....xxxxxxxxxx',
			'.....xx.......',
			'.....x........',
			'....x.........'
		]
	];
	const CLOUD = ['....xxxx....', '..xxxxxxxx..', 'xxxxxxxxxxxx'];
	/** The HUD's little Rex, as SVG pixel art. */
	const cells = (sprite: string[]) =>
		sprite.flatMap((row, y) => [...row].flatMap((c, x) => (c === 'x' ? [{ x, y }] : [])));
	const REX_CELLS = cells([...REX, ...LEGS[2]]);

	// ---- Geometry, physics and rules, in CSS pixels. -------------------------

	const CELL = 4;
	const HEIGHT = 260;
	const GROUND = HEIGHT - 34;
	const REX_X = 48;
	const GRAVITY = 2800;
	const JUMP_V = -880;
	const START_SPEED = 380;
	const MAX_SPEED = 980;
	const BIRD_SPEED = 560;
	const NIGHT_EVERY = 700;
	const NIGHT_LENGTH = 250;
	const METEOR_EVERY = 500;
	const CONTINUE_FROM = 9;
	const KONAMI = [
		'ArrowUp',
		'ArrowUp',
		'ArrowDown',
		'ArrowDown',
		'ArrowLeft',
		'ArrowRight',
		'ArrowLeft',
		'ArrowRight',
		'KeyB',
		'KeyA'
	];

	type Phase = 'attract' | 'running' | 'paused' | 'over';
	type Obstacle = {
		x: number;
		y: number;
		kind: 'cactus' | 'cacti' | 'bird';
		frames: string[][];
		width: number;
	};

	let phase = $state<Phase>('attract');
	let score = $state(0);
	let best = $state(0);
	let menu = $state(0); // GAME OVER: 0 = yes, 1 = no.
	let countdown = $state(CONTINUE_FROM);
	let blink = $state(false);
	let night = $state(false);
	let rainbow = $state(false);
	let newHigh = $state(false);
	let note = $state<'konami' | null>(null);

	let canvas: HTMLCanvasElement;
	let frame: HTMLDivElement;
	let width = 640;
	let ctx: CanvasRenderingContext2D | null = null;
	let raf = 0;
	let last = 0;
	let overAt = 0;
	let hadRun = false;
	let countdownTimer: ReturnType<typeof setInterval> | undefined;
	let noteTimer: ReturnType<typeof setTimeout> | undefined;
	let typed: string[] = [];

	let rexY = 0;
	let rexV = 0;
	let ducking = false;
	let speed = START_SPEED;
	let distance = 0;
	let gap = 0;
	let obstacles: Obstacle[] = [];
	let clouds: { x: number; y: number }[] = [];
	let specks: { x: number; y: number }[] = [];
	let stars: { x: number; y: number }[] = [];
	let meteors: { x: number; y: number; vx: number; vy: number }[] = [];
	let nightUntil = 0;

	let colors = {
		rex: '#daff52',
		ink: '#f2f2f2',
		muted: '#8a8a8a',
		bg: '#0b0b0b',
		sun: '#ffb592',
		ember: '#ffb592'
	};

	const rexHeight = (REX.length + 3) * CELL;
	const rexWidth = REX[0].length * CELL;

	const pad = (n: number, digits = 5) => String(Math.min(n, 10 ** digits - 1)).padStart(digits, '0');

	// ---- The cabinet ---------------------------------------------------------

	function flash(kind: 'konami') {
		note = kind;
		clearTimeout(noteTimer);
		noteTimer = setTimeout(() => (note = null), 2200);
	}

	function insertCoin() {
		sfx?.coin();
		// A coin buys time on the continue screen, as on any cabinet.
		if (phase === 'over') countdown = CONTINUE_FROM;
	}

	function moveMenu(delta: -1 | 1) {
		if (phase !== 'over') return;
		const next = Math.max(0, Math.min(1, menu + delta));
		if (next === menu) return;
		menu = next;
		sfx?.select();
	}

	function confirm() {
		if (phase === 'attract') {
			start();
		} else if (phase === 'over') {
			// The key that ended the run should not also answer the question.
			if (performance.now() - overAt < 600) return;
			if (menu === 0) start();
			else toAttract();
		} else if (phase === 'paused') {
			resume();
		}
	}

	function toAttract() {
		clearInterval(countdownTimer);
		phase = 'attract';
		menu = 0;
		sfx?.select();
		draw(performance.now());
	}

	function reset() {
		rexY = 0;
		rexV = 0;
		ducking = false;
		speed = START_SPEED;
		distance = 0;
		score = 0;
		obstacles = [];
		meteors = [];
		gap = 0;
		nightUntil = 0;
		night = false;
		newHigh = false;
	}

	function start() {
		clearInterval(countdownTimer);
		reset();
		phase = 'running';
		last = performance.now();
		raf = requestAnimationFrame(tick);
		onevent?.({ type: hadRun ? 'restart' : 'start' });
		hadRun = true;
	}

	function pause() {
		if (phase !== 'running') return;
		phase = 'paused';
		ducking = false;
		cancelAnimationFrame(raf);
		sfx?.pause(true);
		draw(performance.now());
	}

	function resume() {
		if (phase !== 'paused') return;
		phase = 'running';
		last = performance.now();
		sfx?.pause(false);
		raf = requestAnimationFrame(tick);
	}

	function jump() {
		if (phase !== 'running') {
			confirm();
			return;
		}
		if (rexY === 0 && !ducking) {
			rexV = JUMP_V;
			sfx?.jump();
		}
	}

	function crash(obstacle: Obstacle): boolean {
		sfx?.hit();
		const wasNewHigh = score > best && best > 0;
		onevent?.({ type: 'crash', score, best, newHigh: wasNewHigh, obstacle: obstacle.kind });
		phase = 'over';
		overAt = performance.now();
		cancelAnimationFrame(raf);
		newHigh = score > best;
		best = Math.max(best, score);
		menu = 0;
		countdown = CONTINUE_FROM;
		sfx?.over();
		draw(performance.now());
		onevent?.({ type: 'over' });
		clearInterval(countdownTimer);
		countdownTimer = setInterval(() => {
			if (phase !== 'over') return clearInterval(countdownTimer);
			countdown -= 1;
			if (countdown <= 0) toAttract();
			else sfx?.tick();
		}, 1000);
		return true;
	}

	// ---- The run -------------------------------------------------------------

	function spawn() {
		const roll = Math.random();
		if (speed > BIRD_SPEED && roll < 0.25) {
			// Low birds are jumped, high ones are ducked under.
			const high = Math.random() < 0.5;
			obstacles.push({
				x: width + 20,
				y: GROUND - (high ? 62 : 30),
				kind: 'bird',
				frames: BIRD,
				width: BIRD[0][0].length * CELL
			});
			return;
		}
		if (roll < 0.55) {
			obstacles.push({
				x: width + 20,
				y: GROUND - CACTUS.length * CELL,
				kind: 'cactus',
				frames: [CACTUS],
				width: CACTUS[0].length * CELL
			});
			return;
		}
		const sprite = Math.random() < 0.5 ? CACTUS_BIG : CACTUS;
		const count = speed > 520 && Math.random() < 0.5 ? 3 : 2;
		const rows = sprite.map((row) => Array(count).fill(row).join('.'));
		obstacles.push({
			x: width + 20,
			y: GROUND - sprite.length * CELL,
			kind: 'cacti',
			frames: [rows],
			width: rows[0].length * CELL
		});
	}

	function tick(now: number) {
		// rAF stamps the frame start, which can precede the `performance.now()` that
		// started the run: clamp, or the first step runs backwards.
		const dt = Math.max(0, Math.min(0.05, (now - last) / 1000));
		last = now;

		speed = Math.min(MAX_SPEED, speed + 10 * dt);
		const before = score;
		distance += speed * dt;
		score = Math.floor(distance / 10);
		if (Math.floor(score / 100) > Math.floor(before / 100)) {
			const reached = Math.floor(score / 100) * 100;
			sfx?.reached();
			blink = true;
			setTimeout(() => (blink = false), 900);
			onevent?.({ type: 'milestone', score: reached });
		}
		if (Math.floor(score / METEOR_EVERY) > Math.floor(before / METEOR_EVERY)) {
			// An extinction-level reminder, every 500 points.
			meteors.push({ x: width * (0.15 + Math.random() * 0.4), y: -10, vx: 260, vy: 150 });
		}
		if (Math.floor(score / NIGHT_EVERY) > Math.floor(before / NIGHT_EVERY)) {
			night = true;
			nightUntil = score + NIGHT_LENGTH;
			onevent?.({ type: 'night' });
		} else if (night && score >= nightUntil) {
			night = false;
		}

		rexV += GRAVITY * (ducking && rexY < 0 ? 2.2 : 1) * dt;
		rexY = Math.min(0, rexY + rexV * dt);
		if (rexY === 0) rexV = 0;

		for (const o of obstacles) o.x -= (o.kind === 'bird' ? speed * 1.08 : speed) * dt;
		obstacles = obstacles.filter((o) => o.x > -o.width - 10);
		const lastX = obstacles.at(-1)?.x ?? -Infinity;
		if (lastX < width - gap) {
			spawn();
			gap = 300 + Math.random() * 360 + speed * 0.42;
		}
		for (const c of clouds) {
			c.x -= speed * 0.12 * dt;
			if (c.x < -60) {
				c.x = width + Math.random() * 200;
				c.y = 20 + Math.random() * 60;
			}
		}
		for (const s of specks) {
			s.x -= speed * dt;
			if (s.x < 0) s.x += width;
		}
		for (const m of meteors) {
			m.x += m.vx * dt;
			m.y += m.vy * dt;
		}
		meteors = meteors.filter((m) => m.y < GROUND - 20 && m.x < width + 40);

		const hitBy = hit();
		if (hitBy && crash(hitBy)) return;
		draw(now);
		raf = requestAnimationFrame(tick);
	}

	function hit(): Obstacle | null {
		const h = ducking && rexY === 0 ? DUCK[0].length * CELL : rexHeight;
		const w = ducking && rexY === 0 ? DUCK[0][0].length * CELL : rexWidth;
		const top = GROUND - h + rexY;
		const rex = { l: REX_X + 8, r: REX_X + w - 12, t: top + 6, b: top + h - 4 };
		for (const o of obstacles) {
			const rows = o.frames[0];
			const c = { l: o.x + 4, r: o.x + o.width - 4, t: o.y + 4, b: o.y + rows.length * CELL };
			if (rex.l < c.r && rex.r > c.l && rex.t < c.b && rex.b > c.t) return o;
		}
		return null;
	}

	// ---- Drawing -------------------------------------------------------------

	function dots(sprite: string[], x: number, y: number, color: string, scale = 0.42) {
		if (!ctx) return;
		ctx.fillStyle = color;
		ctx.beginPath();
		for (let r = 0; r < sprite.length; r++) {
			const row = sprite[r];
			for (let c = 0; c < row.length; c++) {
				if (row[c] !== 'x') continue;
				const cx = x + c * CELL + CELL / 2;
				const cy = y + r * CELL + CELL / 2;
				ctx.moveTo(cx + CELL * scale, cy);
				ctx.arc(cx, cy, CELL * scale, 0, Math.PI * 2);
			}
		}
		ctx.fill();
	}

	function draw(now: number) {
		if (!ctx) return;
		const dead = phase === 'over';
		const ink = night ? colors.bg : colors.ink;
		const muted = night ? '#3a3a3a' : colors.muted;
		ctx.clearRect(0, 0, width, HEIGHT);
		if (night) {
			ctx.fillStyle = colors.ink;
			ctx.fillRect(0, 0, width, HEIGHT);
		} else {
			ctx.fillStyle = colors.muted;
			ctx.beginPath();
			for (const s of stars) {
				ctx.moveTo(s.x + 0.8, s.y);
				ctx.arc(s.x, s.y, 0.8, 0, Math.PI * 2);
			}
			ctx.fill();
		}

		for (const c of clouds) dots(CLOUD, c.x, c.y, muted, 0.3);

		for (const m of meteors) {
			const trail = ctx.createLinearGradient(m.x - m.vx * 0.25, m.y - m.vy * 0.25, m.x, m.y);
			trail.addColorStop(0, 'transparent');
			trail.addColorStop(1, colors.ember);
			ctx.strokeStyle = trail;
			ctx.lineWidth = 3;
			ctx.beginPath();
			ctx.moveTo(m.x - m.vx * 0.25, m.y - m.vy * 0.25);
			ctx.lineTo(m.x, m.y);
			ctx.stroke();
			ctx.fillStyle = colors.sun;
			ctx.beginPath();
			ctx.arc(m.x, m.y, 3, 0, Math.PI * 2);
			ctx.fill();
		}

		ctx.fillStyle = muted;
		ctx.beginPath();
		for (let x = 0; x < width; x += 8) {
			ctx.moveTo(x + 1.5, GROUND + 2);
			ctx.arc(x, GROUND + 2, 1.5, 0, Math.PI * 2);
		}
		for (const s of specks) {
			ctx.moveTo(s.x + 1, s.y);
			ctx.arc(s.x, s.y, 1, 0, Math.PI * 2);
		}
		ctx.fill();

		const flap = Math.floor(now / 160) % 2;
		for (const o of obstacles) dots(o.frames[o.frames.length > 1 ? flap : 0], o.x, o.y, ink);

		// At night the ground is light: Rex goes dark with everything else, or the neon (grey on
		// the cabinet's greyscale screen) vanishes into it.
		const rexColor = rainbow ? `hsl(${(now / 6) % 360} 95% 65%)` : night ? ink : colors.rex;
		const step = Math.floor(now / 100) % 2;
		if (ducking && rexY === 0 && !dead) {
			const sprite = DUCK[step];
			dots(sprite, REX_X, GROUND - sprite.length * CELL, rexColor);
			return;
		}
		const legs = phase !== 'running' || rexY < 0 ? LEGS[2] : LEGS[step];
		const body = dead
			? REX.map((row, r) =>
					r === REX_DEAD_EYE.row
						? row.slice(0, REX_DEAD_EYE.col) + 'x' + row.slice(REX_DEAD_EYE.col + 1)
						: row
				)
			: REX;
		const top = GROUND - rexHeight + rexY;
		dots([...body, ...legs], REX_X, top, rexColor);
		if (dead && newHigh) dots(CROWN, REX_X + 7 * CELL, top - CROWN.length * CELL - 2, colors.sun);
	}

	function resize() {
		if (!canvas || !frame) return;
		width = frame.clientWidth;
		const dpr = window.devicePixelRatio || 1;
		canvas.width = Math.round(width * dpr);
		canvas.height = Math.round(HEIGHT * dpr);
		canvas.style.width = `${width}px`;
		canvas.style.height = `${HEIGHT}px`;
		ctx = canvas.getContext('2d');
		ctx?.setTransform(dpr, 0, 0, dpr, 0, 0);
		specks = Array.from({ length: Math.ceil(width / 40) }, () => ({
			x: Math.random() * width,
			y: GROUND + 10 + Math.random() * 18
		}));
		stars = Array.from({ length: Math.ceil(width / 24) }, () => ({
			x: Math.random() * width,
			y: 8 + Math.random() * (GROUND * 0.55)
		}));
		const n = Math.max(2, Math.ceil(width / 260));
		clouds = Array.from({ length: n }, (_, i) => ({
			x: (i + 0.5) * (width / n),
			y: 20 + Math.random() * 60
		}));
		draw(performance.now());
	}

	// ---- Keys ----------------------------------------------------------------

	function ignored(target: EventTarget | null): boolean {
		return !!(target as HTMLElement | null)?.closest(
			'input, textarea, select, button, a, [contenteditable], [role="combobox"], [role="listbox"], [role="menu"], [role="dialog"]'
		);
	}

	function onkeydown(event: KeyboardEvent) {
		if (event.metaKey || event.ctrlKey || event.altKey || ignored(event.target)) return;

		typed = [...typed, event.code].slice(-KONAMI.length);
		if (typed.join() === KONAMI.join()) {
			typed = [];
			rainbow = !rainbow;
			sfx?.coin();
			flash('konami');
		}

		switch (event.code) {
			case 'Space':
			case 'ArrowUp':
				event.preventDefault();
				if (event.repeat && phase !== 'running') return;
				jump();
				break;
			case 'Enter':
				if (phase === 'running') return;
				event.preventDefault();
				confirm();
				break;
			case 'ArrowDown':
				if (phase !== 'running') return;
				event.preventDefault();
				ducking = true;
				break;
			case 'ArrowLeft':
			case 'ArrowRight':
				if (phase !== 'attract' && phase !== 'over') return;
				event.preventDefault();
				moveMenu(event.code === 'ArrowLeft' ? -1 : 1);
				break;
			case 'KeyP':
			case 'Escape':
				if (phase === 'running') pause();
				else if (phase === 'paused') resume();
				else return;
				event.preventDefault();
				break;
			case 'KeyC':
				insertCoin();
				break;
		}
	}

	function onkeyup(event: KeyboardEvent) {
		if (event.code === 'ArrowDown') ducking = false;
	}

	onMount(() => {
		colors = {
			rex: cssToken('--phonon-accent', colors.rex),
			ink: cssToken('--phonon-ink', colors.ink),
			muted: cssToken('--phonon-ink-muted', colors.muted),
			bg: cssToken('--phonon-surface', colors.bg),
			sun: cssToken('--phonon-arcade-sun', colors.sun),
			ember: cssToken('--phonon-arcade-ember', colors.ember)
		};
		resize();
		const observer = new ResizeObserver(resize);
		observer.observe(frame);
		// A run in a background tab pauses itself, as a cabinet would if you walked off.
		const onVisibility = () => document.hidden && pause();
		document.addEventListener('visibilitychange', onVisibility);
		return () => {
			observer.disconnect();
			document.removeEventListener('visibilitychange', onVisibility);
			cancelAnimationFrame(raf);
			clearInterval(countdownTimer);
			clearTimeout(noteTimer);
		};
	});
</script>

<svelte:window {onkeydown} {onkeyup} />

{#snippet littleRex()}
	<svg viewBox="0 0 15 16" class="h-4 w-4" shape-rendering="crispEdges" aria-hidden="true">
		{#each REX_CELLS as c (c.x + ',' + c.y)}
			<rect x={c.x} y={c.y} width="1" height="1" fill={night ? 'var(--phonon-surface)' : 'var(--phonon-accent)'} />
		{/each}
	</svg>
{/snippet}

{#snippet option(label: string, index: number)}
	<!-- The cabinet's cursor: ▶ before the choice, blinking. Clickable too. -->
	<Button
		variant="ghost"
		size="sm"
		class="h-auto! gap-2! rounded-none! p-0! font-komuna text-sm! font-thin tracking-[0.2em] uppercase hover:bg-transparent! {menu ===
		index
			? 'text-[var(--phonon-arcade-sun)]!'
			: 'text-[var(--phonon-ink-muted)]! hover:text-[var(--phonon-ink)]!'}"
		onpointerdown={(e: PointerEvent) => e.stopPropagation()}
		onclick={(e: MouseEvent) => {
			menu = index;
			confirm();
			(e.currentTarget as HTMLElement).blur();
		}}
	>
		<span class="w-3 {menu === index ? 'animate-arcade-blink' : 'invisible'}" aria-hidden="true">▶</span>
		{label}
	</Button>
{/snippet}

<div
	bind:this={frame}
	class="relative w-full overflow-hidden border border-[var(--phonon-line)] transition-colors duration-500 select-none {night
		? 'bg-[var(--phonon-ink)]'
		: 'bg-[var(--phonon-surface)]'}"
>
	<!-- svelte-ignore a11y_no_static_element_interactions -->
	<canvas
		bind:this={canvas}
		class="block touch-manipulation"
		onpointerdown={(e) => {
			e.preventDefault();
			jump();
		}}
		aria-label={$t('phonon.arcade.pressStart')}
	></canvas>

	<!-- HUD: always up, like a cabinet's top line. -->
	<div
		class="pointer-events-none absolute inset-x-0 top-0 z-10 grid grid-cols-3 items-start px-4 pt-3 font-komuna font-thin tracking-[0.2em] uppercase"
	>
		<div class="flex flex-col gap-1">
			<!-- At night the screen is light: the labels go dark with it, as Rex does. -->
			<span class="flex items-center gap-1.5 text-caption {night ? 'text-[var(--phonon-surface)]' : 'text-[var(--phonon-arcade-pink)]'}">
				{@render littleRex()}
				{marquee($t('phonon.arcade.player'))}
			</span>
			<span
				class="font-mono text-sm tracking-normal tabular-nums {night
					? 'text-[var(--phonon-surface)]'
					: 'text-[var(--phonon-ink)]'} {blink ? 'animate-arcade-blink' : ''}"
			>
				{pad(score)}
			</span>
		</div>
		<div class="flex flex-col items-center gap-1">
			<span class="text-caption {night ? 'text-[var(--phonon-surface)]' : 'text-[var(--phonon-arcade-cyan)]'}">{marquee($t('phonon.arcade.hiScore'))}</span>
			<span class="font-mono text-sm tracking-normal tabular-nums {night ? 'text-[var(--phonon-surface)]' : 'text-[var(--phonon-arcade-sun)]'}">
				{pad(best)}
			</span>
		</div>
	</div>

	{#if note === 'konami'}
		<p
			class="pointer-events-none absolute inset-x-0 top-14 z-10 m-0 animate-arcade-rainbow text-center font-komuna text-sm font-thin tracking-[0.2em] text-[var(--phonon-arcade-pink)] uppercase"
		>
			{marquee($t('phonon.arcade.konami'))}
		</p>
	{/if}

	{#if phase !== 'running'}
		<!-- The cabinet's screens. Tapping anywhere on them is the start button. -->
		<!-- svelte-ignore a11y_no_static_element_interactions -->
		<div
			class="phonon-crt absolute inset-0 flex flex-col items-center justify-center gap-3 px-4 pt-10 pb-6 text-center"
			onpointerdown={(e) => {
				e.preventDefault();
				confirm();
			}}
		>
			{#if phase === 'attract'}
				<h2
					class="m-0 animate-arcade-pop bg-linear-to-b from-[var(--phonon-arcade-sun)] via-[var(--phonon-arcade-ember)] to-[var(--phonon-arcade-blaze)] bg-clip-text font-komuna text-4xl font-[200] tracking-[0.15em] text-transparent uppercase drop-shadow-[3px_3px_0_var(--phonon-bg)] max-md:text-2xl"
				>
					{marquee($t('phonon.arcade.start'))}
				</h2>
				<p class="m-0 animate-arcade-blink font-mono text-caption tracking-[0.25em] text-[var(--phonon-ink)] uppercase">
					{$t('phonon.arcade.pressStart')}
				</p>
			{:else if phase === 'over'}
				<h2
					class="m-0 animate-arcade-pop bg-linear-to-b from-[var(--phonon-arcade-sun)] via-[var(--phonon-arcade-ember)] to-[var(--phonon-arcade-blaze)] bg-clip-text font-komuna text-4xl font-[200] tracking-[0.15em] text-transparent uppercase drop-shadow-[3px_3px_0_var(--phonon-bg)] max-md:text-2xl"
				>
					{marquee($t('phonon.game.over'))}
				</h2>
				{#if newHigh}
					<p
						class="m-0 animate-arcade-rainbow font-komuna text-sm font-thin tracking-[0.2em] text-[var(--phonon-arcade-pink)] uppercase"
					>
						{marquee($t('phonon.arcade.newHigh'))} · {pad(best)}
					</p>
				{:else}
					<p class="m-0 font-mono text-caption tracking-[0.2em] text-[var(--phonon-ink-muted)] uppercase">
						{$t('phonon.game.score', { score: pad(score) })}
					</p>
				{/if}
				<p class="m-0 flex items-center gap-3 font-komuna text-sm font-thin tracking-[0.2em] text-[var(--phonon-ink)] uppercase">
					{marquee($t('phonon.arcade.continue'))}
					<span class="animate-arcade-blink font-mono text-xl text-[var(--phonon-arcade-sun)]">{countdown}</span>
				</p>
				<div class="flex items-center gap-10">
					{@render option(marquee($t('phonon.arcade.yes')), 0)}
					{@render option(marquee($t('phonon.arcade.no')), 1)}
				</div>
			{:else if phase === 'paused'}
				<h2
					class="m-0 animate-arcade-blink font-komuna text-3xl font-[200] tracking-[0.25em] text-[var(--phonon-arcade-cyan)] uppercase"
				>
					{marquee($t('phonon.arcade.paused'))}
				</h2>
				<p class="m-0 flex items-center gap-2 font-mono text-caption tracking-[0.2em] text-[var(--phonon-ink-muted)] uppercase">
					<Kbd>P</Kbd>
					{$t('phonon.arcade.resume')}
				</p>
			{/if}
		</div>
	{/if}
</div>
