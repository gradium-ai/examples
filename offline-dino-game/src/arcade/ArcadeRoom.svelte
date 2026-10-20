<script lang="ts">
	/**
	 * The arcade the cabinet stands in, printed: an aisle in one-point
	 * perspective drawn the way gradium.ai/phonon draws its world, in halftone,
	 * ASCII and screen-print inks rather than shaded planes.
	 *
	 * Every surface carries its own screen of dots, laid out on the surface in
	 * world space and then projected, so the dots grow toward the eye and crowd
	 * toward the vanishing point: the distribution of the dots *is* the depth.
	 * The vanishing lines are drawn in the same dots: lines down the floor, a
	 * rail and a baseboard along each wall, strips of light down the ceiling.
	 *
	 * The two walls are not mirrors: each has its own run of machines, of their
	 * own widths, heights and colours, and each machine has its own game on its
	 * screen, printed in ASCII from a real picture (`arcadeGames.ts`): a ringed
	 * planet, Rex, a sunset, a squadron, a voice, a paddle game, a maze. The
	 * bare wall between them is a plain dot print.
	 *
	 * The cabinet's own sides and top are printed last, opaque, so the room
	 * never shows through them: solid boards, BOARD thick, in the front's own
	 * style: flat greys, one per face (an inner face shading from
	 * `--phonon-side` to `--phonon-side-lit` toward the eye, `--phonon-roof`
	 * under the top, `--phonon-board-edge` and `--phonon-roof-front` on the
	 * edges), under the same fine dot screen the front carries. The boards'
	 * front edges join into one frame round the cabinet, the lime T-molding
	 * run along it, a light running round it (an SVG over the canvas).
	 *
	 * The spot inks (lime, sun, pale lime) are printed a hair off register, the
	 * way a screen print is. Drawn on one canvas behind the cabinet with the
	 * cabinet's own perspective and eye (the page passes both in, and the
	 * cabinet's box). Redrawn only when the eye or the layout moves.
	 * Decoration only: hidden from assistive tech, and not on a phone.
	 */
	import { onMount } from 'svelte';
	import { cssToken } from '$lib/cssToken';
	import { fitCanvas } from './halftone';
	import { GAMES, RAMP, type GameName, type Ink } from './arcadeGames';

	interface Props {
		/** The eye's offset from centre, px: the page's parallax. */
		eye: { x: number; y: number };
		/** The eye's height in this layer's px. */
		eyeY: number;
		/** The cabinet's front, in this layer's px. */
		box: { left: number; right: number; top: number; bottom: number };
		/** How far the cabinet's side panels come toward the eye, px. */
		depth: number;
		perspective: number;
	}

	let { eye, eyeY, box, depth, perspective }: Props = $props();

	/** The aisle runs from just in front of the eye's plane to here. */
	const Z_NEAR = 420;
	const Z_FAR = -3600;
	/** The room's dots, the website's size: a fine screen, never a blot. */
	const DOT_SCALE = 0.42;
	const DOT_MAX = 2;
	/** The perspective grid's pitch, world px: every fifth dot of the floor's screen. */
	const GRID = 150;

	/** The top board: how far it stands above the marquee. */
	const ROOF = 15;
	/** The side boards' thickness: their front edges frame the cabinet. */
	const BOARD = 19;

	interface Machine {
		/** Its near edge along the wall, px (back is negative), and its width along it. */
		near: number;
		width: number;
		/** Its height, as a share of the cabinet's. */
		height: number;
		game: GameName;
		cap: Ink;
		/** Its screen's height, as a share of the machine's. */
		screen?: number;
		/** Its screen edge to edge, a poster rather than a cabinet's glass. */
		poster?: boolean;
	}

	/** Each wall its own run: different sizes, gaps and colours, a different game each. */
	// Every machine starts and ends on one of the wall's lines (every `GRID`
	// from `Z_NEAR`: 420, 270, 120, -30, ...), three squares wide, one square
	// of bare wall between neighbours, except Rex's machine, which starts on
	// the planet's last line: a square further back and the cabinet would hide
	// it. The planet starts on 120, the guitar a line further back, on -30.
	// Screens and dots snap to the lattice (`body`).
	const WALLS: Record<'left' | 'right', Machine[]> = {
		left: [
			// Deep space, as a poster: the screen takes nearly the whole machine.
			{ near: 120, width: 450, height: 1, game: 'planet', cap: 'sun', screen: 0.8, poster: true },
			{ near: -330, width: 450, height: 0.85, game: 'runner', cap: 'lime' },
			{ near: -930, width: 450, height: 0.97, game: 'sunset', cap: 'pale' },
			{ near: -1530, width: 450, height: 0.86, game: 'squadron', cap: 'sun' }
		],
		// A rock game on a tall screen: a wall seen from the aisle squeezes what
		// runs along it and keeps what runs up it, so the guitar stands on its
		// diagonal.
		right: [
			{ near: -30, width: 450, height: 0.95, game: 'guitar', cap: 'lime', screen: 0.64 },
			{ near: -630, width: 450, height: 0.92, game: 'paddles', cap: 'pale' },
			{ near: -1230, width: 450, height: 0.88, game: 'maze', cap: 'sun' }
		]
	};

	let host: HTMLDivElement;
	let canvas: HTMLCanvasElement;
	let ctx: CanvasRenderingContext2D | null = null;
	/** The ramp's glyphs, drawn once per ink in the mono face, stamped from then on. */
	let atlases: Partial<Record<Ink, HTMLCanvasElement>> = {};
	const CELL = 40;
	let width = 0;
	let height = 0;
	let frame = 0;
	/** The T-molding's line on screen, for the light that runs along it. */
	let moldingPath = $state('');
	type Grey = 'side' | 'sideLit' | 'roof' | 'roofFront' | 'edge';
	// The room is printed in black and white: each of the games' spot inks
	// (`lime`, `sun`, `pale`, and the ceiling's `cyan`) is a grey here, and
	// only the cabinet's own molding (`brand`) keeps the lime.
	let inks: Record<Ink | Grey | 'cyan' | 'brand', string> = {
		brand: '#daff52',
		cyan: '#d4d4d4',
		ink: '#f2f2f2',
		lime: '#d4d4d4',
		sun: '#9e9e9e',
		pale: '#6b6b6b',
		side: '#131313',
		sideLit: '#232323',
		roof: '#0b0b0b',
		roofFront: '#1d1d1d',
		edge: '#2a2a2a'
	};
	const INKS: Ink[] = ['ink', 'pale', 'sun', 'lime'];

	/** Where each spot ink lands against the key: a screen print's registration. */
	const OFF_REGISTER: Record<Ink, [number, number]> = {
		ink: [0, 0],
		lime: [1.4, -0.9],
		sun: [-1.1, 1.2],
		pale: [0.9, 1]
	};

	function makeAtlases(family: string) {
		for (const ink of INKS) {
			const atlas = document.createElement('canvas');
			atlas.width = CELL * RAMP.length;
			atlas.height = CELL;
			const a = atlas.getContext('2d');
			if (!a) continue;
			a.fillStyle = inks[ink];
			a.font = `500 ${CELL * 0.9}px ${family}`;
			a.textAlign = 'center';
			a.textBaseline = 'middle';
			for (let i = 0; i < RAMP.length; i++) a.fillText(RAMP[i], i * CELL + CELL / 2, CELL / 2 + 2);
			atlases[ink] = atlas;
		}
	}

	function schedule() {
		if (frame) return;
		frame = requestAnimationFrame(() => {
			frame = 0;
			draw();
		});
	}

	$effect(() => {
		// Read what the drawing depends on, so a change redraws it.
		void [eye.x, eye.y, eyeY, box.left, box.right, box.top, box.bottom, depth];
		schedule();
	});

	function draw() {
		if (!ctx || !width || box.right <= box.left) return;
		const P = perspective;
		const ox = width / 2 + eye.x;
		const oy = eyeY + eye.y;
		const cabW = box.right - box.left;
		const cabH = box.bottom - box.top;
		const cx = (box.left + box.right) / 2;
		// How far each wall stands from the cabinet's centre. The right one is
		// nearer, so the machine standing forward on it stays in the frame.
		// The aisle's width is a whole number of grid squares, so the floor's last
		// line is the right wall's foot, as its first is the left's.
		// Both walls the same distance out, so the cabinet stands in the middle
		// of the room and not only of the screen.
		const half = (Math.round((cabW * 1.9) / GRID) * GRID) / 2;
		const reach = { left: half, right: half };
		const floorY = box.bottom;
		const ceilY = box.top - cabH * 0.32;
		const roof = box.top - ROOF;
		// The cabinet's front covers the middle: nothing behind it is drawn.
		const hide = { l: box.left + 6, r: box.right - 6, t: box.top + 6, b: box.bottom - 6 };

		const scale = (z: number) => P / (P - z);
		const project = (x: number, y: number, z: number): [number, number] => {
			const s = scale(z);
			return [ox + (x - ox) * s, oy + (y - oy) * s];
		};
		const visible = (sx: number, sy: number, pad: number) =>
			sx > -pad &&
			sx < width + pad &&
			sy > -pad &&
			sy < height + pad &&
			!(sx > hide.l && sx < hide.r && sy > hide.t && sy < hide.b);

		const fresh = () => ({ ink: [], lime: [], sun: [], pale: [] }) as Record<Ink, number[]>;
		const world = fresh();
		const glyphs = fresh();

		const fade = (z: number) => (z > -300 ? 1 : Math.max(0, 1 - (-300 - z) / 3000));

		// The perspective lines, Tron-style: thin strokes on the same grid the
		// dots are printed on, grey for the room, a touch of colour for what
		// leads the eye (the path on the floor, the ceiling's lights, the rails,
		// the machines' screens). Flat colours, no gradients; long lines are cut
		// into GRID-long pieces so each can fade with its distance.
		type LineInk = 'grey' | 'lime' | 'cyan' | 'sun' | 'pale';
		// Each surface its own weight and density: the floor the heaviest and
		// densest, the walls lighter and looser, the ceiling the faintest; the
		// coloured lines, which lead the eye, a little heavier than the grey.
		const lines: [LineInk, number, number, number, number, number, number][] = [];
		const seg = (ink: LineInk, width: number, a: [number, number, number], b: [number, number, number]) => {
			const f = fade((a[2] + b[2]) / 2);
			if (f <= 0) return;
			const [ax, ay] = project(a[0], a[1], a[2]);
			const [bx, by] = project(b[0], b[1], b[2]);
			lines.push([ink, f, width, ax, ay, bx, by]);
		};
		/** `v` onto the lattice of `pitch` that starts at `origin`: nothing off the grid. */
		const snap = (v: number, origin: number, pitch: number) => origin + Math.round((v - origin) / pitch) * pitch;
		/** A line running back along z, from the near end of the aisle to the far one. */
		const along = (ink: LineInk, width: number, x: number, y: number) => {
			for (let z = Z_NEAR; z > Z_FAR; z -= GRID) seg(ink, width, [x, y, z], [x, y, Math.max(Z_FAR, z - GRID)]);
		};

		/** A dot of `r` world px on a surface at (x, y, z), in `ink`, into `layer`. */
		const dot = (
			layer: Record<Ink, number[]>,
			ink: Ink,
			x: number,
			y: number,
			z: number,
			r: number,
			cull = true
		) => {
			const s = scale(z);
			// Near the eye a dot stops growing: a print's coarsest screen, not a blot.
			const rr = Math.min(r * s * DOT_SCALE, DOT_MAX);
			if (rr < 0.25) return;
			const sx = ox + (x - ox) * s;
			const sy = oy + (y - oy) * s;
			if (cull && !visible(sx, sy, rr)) return;
			layer[ink].push(sx, sy, rr);
		};

		// ---- The floor: a halftone carpet, every fifth row of dots a line to the
		// vanishing point, a sparse lime dot in the weave.
		// The room's screens, between the bare room they were and the cabinet's
		// own fine screen (6px): the floor twice as dense each way, the walls and
		// the ceiling half again. Dots keep their size (`*R`, the old pitches).
		const fp = 15;
		const fpR = 30 * 0.85;
		let row = 0;
		for (let z = Z_NEAR; z > Z_FAR; z -= fp, row++) {
			const f = fade(z);
			if (f <= 0) break;
			let col = 0;
			for (let x = cx - reach.left; x <= cx + reach.right + 0.5; x += fp, col++) {
				const line = col % 10 === 0 || row % 10 === 0;
				const tone = line ? 0.95 : 0.22;
				dot(world, 'ink', x, floorY, z, fpR * 0.34 * Math.sqrt(tone) * f);
			}
		}
		// The floor's grid, and the path to the cabinet in lime: the two lines
		// that run just outside its sides.
		const pathAt = cabW * 0.6;
		for (let x = cx - reach.left; x <= cx + reach.right + 0.5; x += GRID) {
			const path = Math.abs(Math.abs(x - cx) - pathAt) < GRID / 2;
			along(path ? 'lime' : 'grey', path ? 2 : 1.4, x, floorY);
		}
		for (let z = Z_NEAR; z > Z_FAR; z -= GRID) seg('grey', 1.4, [cx - reach.left, floorY, z], [cx + reach.right, floorY, z]);

		// ---- The ceiling: dark, a strip of light over each wall's run, not mirrored.
		const cp = 25;
		const cpR = 34 * 0.85;
		row = 0;
		for (let z = Z_NEAR; z > Z_FAR; z -= cp, row++) {
			const f = fade(z);
			if (f <= 0) break;
			let col = 0;
			for (let x = cx - reach.left; x <= cx + reach.right + 0.5; x += cp, col++) {
				dot(world, 'ink', x, ceilY, z, cpR * 0.1 * f);
			}
		}
		// The ceiling's grid, and its lights: a strip over each wall's run, in cyan.
		for (let x = cx - reach.left; x <= cx + reach.right + 0.5; x += GRID) along('grey', 0.8, x, ceilY);
		for (let z = Z_NEAR; z > Z_FAR; z -= GRID) seg('grey', 0.8, [cx - reach.left, ceilY, z], [cx + reach.right, ceilY, z]);
		for (const at of [-0.45, 0.45]) {
			const lx = snap(cx + at * (at < 0 ? reach.left : reach.right), cx - reach.left, cp);
			along('cyan', 3, lx, ceilY);
			along('cyan', 3, lx + cp, ceilY);
		}

		// ---- The walls: each its own run of machines, a plain dot print between
		// them, a rail and a baseboard running back.
		// The walls on one lattice from the ceiling's edge and the near end of the
		// aisle: machines printed at 10px, the bare wall at 20px, lines every
		// 100px, every machine's edges and screen on it. Nothing is off the grid.
		const mp = 10;
		const wpR = 22 * 0.85;
		const WALL_LINES = GRID; // the floor's and the ceiling's squares, carried up the wall
		/** A machine, measured on the wall's lattice. */
		const body = (m: Machine) => {
			const top = snap(floorY - m.height * cabH, ceilY, mp * 2);
			const mh = floorY - top;
			const head = m.poster ? 0.06 : 0.15;
			const inset = m.poster ? 0.03 : 0.09;
			const sTop = snap(top + mh * head, ceilY, mp);
			const sBottom = snap(top + mh * (head + (m.screen ?? 0.37)), ceilY, mp);
			const sNear = snap(m.near - m.width * inset, Z_NEAR, mp);
			const sFar = snap(m.near - m.width * (1 - inset), Z_NEAR, mp);
			return { top, mh, sTop, sBottom, sNear, sFar };
		};
		for (const side of [-1, 1] as const) {
			const run = WALLS[side < 0 ? 'left' : 'right'];
			const x = cx + side * (side < 0 ? reach.left : reach.right);
			const tallest = Math.max(...run.map((m) => m.height)) * cabH;
			const rail = snap(floorY - tallest * (side < 0 ? 1.06 : 0.99), ceilY, mp * 2);
			const railInk: Ink = side < 0 ? 'lime' : 'sun';
			const bodies = run.map((m) => ({ m, ...body(m) }));
			let zi = 0;
			for (let z = Z_NEAR; z > Z_FAR; z -= mp, zi++) {
				const f = fade(z);
				if (f <= 0) break;
				const hit = bodies.find((bb) => z <= bb.m.near && z > bb.m.near - bb.m.width);
				let yi = 0;
				for (let y = ceilY; y <= floorY; y += mp, yi++) {
					if (hit && y >= hit.top) {
						const { m, top, sTop, sBottom, sNear, sFar } = hit;
						if (y >= sTop && y <= sBottom && z <= sNear && z >= sFar) continue; // the screen, below
						if (y < sTop && y < top + (sTop - top) * 0.6) dot(world, m.cap, x, y, z, wpR * 0.42 * f);
						else if (y > sBottom && y <= sBottom + mp * 3) dot(world, 'ink', x, y, z, wpR * 0.36 * f);
						else dot(world, 'ink', x, y, z, wpR * 0.22 * f);
					} else if (zi % 2 === 0 && yi % 2 === 0) {
						dot(world, 'ink', x, y, z, wpR * 0.15 * f);
					}
				}
			}
			// The wall's lines, its rail and baseboard, and each machine drawn in
			// outline, its screen framed in its own colour, so the games read.
			for (let z = Z_NEAR; z > Z_FAR; z -= WALL_LINES) seg('grey', 1, [x, ceilY, z], [x, floorY, z]);
			for (let y = ceilY; y < floorY; y += WALL_LINES) along('grey', 1, x, y);
			along(railInk === 'lime' ? 'lime' : 'sun', 1.8, x, rail);
			for (const { m, top, sTop, sBottom, sNear, sFar } of bodies) {
				const back = m.near - m.width;
				seg('grey', 1.4, [x, top, m.near], [x, floorY, m.near]);
				seg('grey', 1.4, [x, top, back], [x, floorY, back]);
				seg('grey', 1.4, [x, top, m.near], [x, top, back]);
				const frame = m.cap === 'lime' ? 'lime' : m.cap === 'sun' ? 'sun' : 'pale';
				seg(frame, 1.8, [x, sTop, sNear], [x, sTop, sFar]);
				seg(frame, 1.8, [x, sBottom, sNear], [x, sBottom, sFar]);
				seg(frame, 1.8, [x, sTop, sNear], [x, sBottom, sNear]);
				seg(frame, 1.8, [x, sTop, sFar], [x, sBottom, sFar]);
			}

			// Each machine's screen: its game, in ASCII, the glyphs squeezed into the
			// wall's perspective so the picture reads as lying on it.
			for (const { m, sTop, sBottom, sNear, sFar } of bodies) {
				// One glyph per cell of the 10px lattice, inside the frame.
				const sw = sNear - sFar;
				const sh = sBottom - sTop;
				const cols = Math.round(sw / mp);
				const rows = Math.round(sh / mp);
				const aspect = sw / sh;
				const game = GAMES[m.game];
				for (let i = 0; i < cols; i++) {
					// The picture's left is the end nearer the eye on the left wall and
					// the farther end on the right one, so neither is mirrored.
					const a = (i + 0.5) / cols;
					const along = side < 0 ? a : 1 - a;
					const z0 = sNear - along * sw;
					const f = fade(z0);
					if (f <= 0) continue;
					const s = scale(z0);
					const colW = Math.abs((x - ox) * (scale(z0 - sw / cols) - s));
					const xa = ox + (x - ox) * s;
					for (let j = 0; j < rows; j++) {
						const down = (j + 0.5) / rows - 0.5;
						const pixel = game((a - 0.5) * aspect, down, aspect);
						if (!pixel || pixel[0] < 0.03) continue;
						const [tone, ink] = pixel;
						const g = Math.max(1, Math.min(RAMP.length - 1, Math.round(tone * (RAMP.length - 1))));
						const y0 = sTop + ((j + 0.5) / rows) * sh;
						const sy = oy + (y0 - oy) * s;
						const h = (sh / rows) * s * 1.15;
						if (h < 2.5 || !visible(xa, sy, h)) continue;
						glyphs[ink].push(g, xa, sy, Math.max(colW * 1.25, h * 0.35), h, f);
					}
				}
			}
		}

		// ---- The cabinet's sides and roof, as solid boards: each side a board
		// BOARD thick from the top board to the floor, the top board spanning
		// both above the marquee. Seen from the front: each board's inner face
		// running back to the cabinet's front (a flat grey, a side shading from
		// the back toward the eye), and their front edges, facing the player,
		// joining into one frame round the cabinet, the lime T-molding run along
		// it. Their outer faces turn away from the eye and are never seen.
		type Face = { quad: [number, number, number][]; back: Grey; front: Grey };
		const outL = box.left - BOARD;
		const outR = box.right + BOARD;
		const faces: Face[] = [
			{
				// The left board's inner face, under the top board.
				quad: [
					[box.left, box.top, 0],
					[box.left, box.top, depth],
					[box.left, box.bottom, depth],
					[box.left, box.bottom, 0]
				],
				back: 'side',
				front: 'sideLit'
			},
			{
				// The right one, away from the light: a shade darker.
				quad: [
					[box.right, box.top, 0],
					[box.right, box.top, depth],
					[box.right, box.bottom, depth],
					[box.right, box.bottom, 0]
				],
				back: 'roof',
				front: 'side'
			},
			{
				// The top board's underside, seen from below.
				quad: [
					[box.left, box.top, 0],
					[box.right, box.top, 0],
					[box.right, box.top, depth],
					[box.left, box.top, depth]
				],
				back: 'roof',
				front: 'roof'
			},
			// The front edges, one frame: the left board, the top, the right board.
			{
				quad: [
					[outL, roof, depth],
					[box.left, roof, depth],
					[box.left, box.bottom, depth],
					[outL, box.bottom, depth]
				],
				back: 'edge',
				front: 'edge'
			},
			{
				quad: [
					[box.left, roof, depth],
					[box.right, roof, depth],
					[box.right, box.top, depth],
					[box.left, box.top, depth]
				],
				back: 'roofFront',
				front: 'roofFront'
			},
			{
				quad: [
					[box.right, roof, depth],
					[outR, roof, depth],
					[outR, box.bottom, depth],
					[box.right, box.bottom, depth]
				],
				back: 'edge',
				front: 'edge'
			}
		];
		const screen: number[] = [];
		const fine = (x: number, y: number, z: number) => {
			const s = scale(z);
			screen.push(ox + (x - ox) * s, oy + (y - oy) * s, 0.85 * s);
		};
		const sp = 6;
		for (const xs of [box.left, box.right]) {
			for (let z = sp / 2; z < depth; z += sp) {
				for (let y = box.top + sp / 2; y < box.bottom; y += sp) fine(xs, y, z);
			}
		}
		for (let z = sp / 2; z < depth; z += sp) {
			for (let xs = box.left + sp / 2; xs < box.right; xs += sp) fine(xs, box.top, z);
		}
		for (let y = roof + sp / 2; y < box.bottom; y += sp) {
			for (let xs = outL + sp / 2; xs < outR; xs += sp) {
				// The front edges only: the cabinet's own front is the page's.
				if (y > box.top && xs > box.left && xs < box.right) continue;
				fine(xs, y, depth);
			}
		}
		// The T-molding: down the middle of each board's edge and across the top.
		const molding = [
			[outL + BOARD / 2, box.bottom],
			[outL + BOARD / 2, roof + ROOF / 2],
			[outR - BOARD / 2, roof + ROOF / 2],
			[outR - BOARD / 2, box.bottom]
		].map(([x, y]) => project(x, y, depth));

		// ---- Print it: the room's inks, its type, then the cabinet over it.
		const c = ctx;
		const dpr = canvas.width / width;
		c.setTransform(dpr, 0, 0, dpr, 0, 0);
		c.clearRect(0, 0, width, height);
		const printDots = (layer: Record<Ink, number[]>) => {
			for (const ink of INKS) {
				const list = layer[ink];
				if (!list.length) continue;
				const [dx, dy] = OFF_REGISTER[ink];
				c.globalAlpha = ink === 'ink' ? 0.4 : 0.8;
				c.fillStyle = inks[ink];
				c.beginPath();
				for (let i = 0; i < list.length; i += 3) {
					const sx = list[i] + dx;
					const sy = list[i + 1] + dy;
					c.moveTo(sx + list[i + 2], sy);
					c.arc(sx, sy, list[i + 2], 0, Math.PI * 2);
				}
				c.fill();
			}
		};
		printDots(world);
		// The lines, thin and flat, over the dots they run through.
		for (const [ink, f, width, ax, ay, bx, by] of lines) {
			c.lineWidth = width;
			c.globalAlpha = (ink === 'grey' ? 0.24 : 0.75) * f;
			c.strokeStyle = ink === 'grey' ? inks.ink : ink === 'cyan' ? inks.cyan : inks[ink];
			c.beginPath();
			c.moveTo(ax, ay);
			c.lineTo(bx, by);
			c.stroke();
		}
		for (const ink of INKS) {
			const atlas = atlases[ink];
			const list = glyphs[ink];
			if (!atlas || !list.length) continue;
			const [dx, dy] = OFF_REGISTER[ink];
			for (let i = 0; i < list.length; i += 6) {
				const w = list[i + 3];
				const h = list[i + 4];
				c.globalAlpha = list[i + 5] * (ink === 'ink' ? 0.9 : 1);
				c.drawImage(atlas, list[i] * CELL, 0, CELL, CELL, list[i + 1] - w / 2 + dx, list[i + 2] - h / 2 + dy, w, h);
			}
		}
		c.globalAlpha = 1;
		for (const { quad, back, front } of faces) {
			const points = quad.map(([x, y, z]) => project(x, y, z));
			if (back === front) {
				c.fillStyle = inks[back];
			} else {
				// Across the panel, from its back edge to the one nearest the eye.
				const [bx, by] = project(quad[0][0], (quad[0][1] + quad[3][1]) / 2, 0);
				const [fx, fy] = project(quad[0][0], (quad[0][1] + quad[3][1]) / 2, depth);
				const shade = c.createLinearGradient(bx, by, fx, fy);
				shade.addColorStop(0, inks[back]);
				shade.addColorStop(1, inks[front]);
				c.fillStyle = shade;
			}
			c.beginPath();
			points.forEach(([sx, sy], i) => (i === 0 ? c.moveTo(sx, sy) : c.lineTo(sx, sy)));
			c.closePath();
			c.fill();
		}
		// The front's dot screen (`arcade-dots`), carried round onto the sides.
		c.globalAlpha = 0.11;
		c.fillStyle = inks.ink;
		c.beginPath();
		for (let i = 0; i < screen.length; i += 3) {
			c.moveTo(screen[i] + screen[i + 2], screen[i + 1]);
			c.arc(screen[i], screen[i + 1], screen[i + 2], 0, Math.PI * 2);
		}
		c.fill();
		c.globalAlpha = 1;
		c.strokeStyle = inks.brand;
		c.lineWidth = 2 * scale(depth);
		c.lineJoin = 'miter';
		c.beginPath();
		molding.forEach(([sx, sy], i) => (i === 0 ? c.moveTo(sx, sy) : c.lineTo(sx, sy)));
		c.stroke();
		moldingPath = molding.map(([sx, sy], i) => `${i ? 'L' : 'M'}${sx.toFixed(1)} ${sy.toFixed(1)}`).join(' ');
		c.globalAlpha = 1;
	}

	function resize() {
		width = host.clientWidth;
		height = host.clientHeight;
		if (!width || !height) return;
		ctx = fitCanvas(canvas, width, height, 1.5);
		schedule();
	}

	onMount(() => {
		inks = {
			ink: cssToken('--phonon-ink', inks.ink),
			brand: cssToken('--phonon-accent', inks.brand),
			lime: cssToken('--phonon-room-light', inks.lime),
			sun: cssToken('--phonon-room-mid', inks.sun),
			pale: cssToken('--phonon-room-dim', inks.pale),
			side: cssToken('--phonon-side', inks.side),
			sideLit: cssToken('--phonon-side-lit', inks.sideLit),
			roof: cssToken('--phonon-roof', inks.roof),
			roofFront: cssToken('--phonon-roof-front', inks.roofFront),
			edge: cssToken('--phonon-board-edge', inks.edge),
			cyan: cssToken('--phonon-room-light', inks.cyan)
		};
		const family = getComputedStyle(canvas).fontFamily;
		void document.fonts.load(`500 40px ${family}`).finally(() => {
			makeAtlases(family);
			schedule();
		});
		resize();
		const observer = new ResizeObserver(resize);
		observer.observe(host);
		return () => {
			observer.disconnect();
			cancelAnimationFrame(frame);
		};
	});
</script>

<div bind:this={host} aria-hidden="true" class="pointer-events-none absolute inset-0 overflow-hidden max-md:hidden">
	<canvas bind:this={canvas} class="absolute inset-0 block font-mono"></canvas>
	<!-- The T-molding's light: a short glow running round the frame's line,
	     up the left board, across the top, down the right, as if the strip
	     were alive. Drawn over the canvas on the same path, so it moves with
	     no redraw; still under reduced motion. -->
	<svg class="absolute inset-0 size-full motion-reduce:hidden">
		<path
			d={moldingPath}
			pathLength="100"
			fill="none"
			stroke="var(--phonon-accent)"
			stroke-width="4"
			stroke-linecap="round"
			stroke-dasharray="18 82"
			class="animate-arcade-chase drop-shadow-[0_0_7px_var(--phonon-accent)]"
		/>
	</svg>
</div>
