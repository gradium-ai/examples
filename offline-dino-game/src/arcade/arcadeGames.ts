/**
 * The other machines' games: what each cabinet along the aisle's walls shows
 * on its screen, printed in ASCII the way the classic ASCII-art planet is,
 * a tone field run through a long character ramp, dense glyphs where the
 * image is bright, a space where it is dark.
 *
 * Each game is an image function: given a point on its screen (x across,
 * scaled by the screen's aspect so a circle stays round; y down, both centred
 * on 0), it answers a tone (0 to 1) and the ink to print it in, or null for
 * nothing. No randomness: the same screen draws the same picture every frame.
 * The machines and their games are placed in `ArcadeRoom.svelte`.
 *
 * Every shape is drawn here from scratch; nothing is another game's sprite.
 */

export type Ink = 'ink' | 'lime' | 'sun' | 'pale';
export type Pixel = [tone: number, ink: Ink] | null;
export type Game = (x: number, y: number, aspect: number) => Pixel;

/** The classic ramp, light to dense: what the planet is printed in. */
export const RAMP =
	" .'`^\",:;Il!i><~+_-?][}{1)(|\\/tfjrxnuvczXYUJCLQ0OZmwqpdbkhao*#MW&8%B@$";

const clamp = (v: number, lo = 0, hi = 1) => Math.max(lo, Math.min(hi, v));
/** The fractional part, in [0, 1) for negatives too (`%` would go negative). */
const frac = (v: number) => v - Math.floor(v);

/** A bitmap sprite, one string per row, `x` a pixel: true where (x, y) lands on one. */
function sprite(rows: string[], x: number, y: number, left: number, top: number, cell: number): boolean {
	const c = Math.floor((x - left) / cell);
	const r = Math.floor((y - top) / cell);
	return r >= 0 && r < rows.length && c >= 0 && c < rows[0].length && rows[r][c] === 'x';
}

/** Fixed stars: a lattice, every so often a point. Placed, not random. */
function star(x: number, y: number): boolean {
	const gx = Math.round(x * 18);
	const gy = Math.round(y * 18);
	const near = Math.abs(x * 18 - gx) < 0.22 && Math.abs(y * 18 - gy) < 0.22;
	return near && (gx * 7 + gy * 13) % 11 === 0;
}

/** Deep space: a ringed planet, lit from the upper left, its ring (with its
 *  gap) passing in front below and behind above, a cratered moon, a comet
 *  with its tail, and a field of stars, some of them bright crosses. */
const planet: Game = (x, y, aspect) => {
	// The moon, up on the right.
	const mx = x - aspect * 0.32;
	const my = y + 0.3;
	const md = Math.hypot(mx, my) / 0.075;
	if (md <= 1) {
		const crater = Math.hypot(mx - 0.02, my + 0.015) < 0.022 || Math.hypot(mx + 0.025, my - 0.02) < 0.014;
		return [crater ? 0.35 : 0.8 - 0.3 * clamp(mx / 0.075 + 0.3), 'pale'];
	}
	// The comet, low on the left, its tail streaming up and away.
	const cx = x + aspect * 0.33;
	const cy = y - 0.32;
	const head = Math.hypot(cx, cy) < 0.022;
	const along = -(cx * 0.8 + cy * 0.6);
	const across = Math.abs(-cx * 0.6 + cy * 0.8);
	if (head) return [1, 'lime'];
	if (along > 0 && along < 0.22 && across < 0.012 + along * 0.08) return [0.75 * (1 - along / 0.22), 'lime'];
	// Bright stars, as four-point crosses, placed on a lattice.
	const gx = Math.round(x * 6);
	const gy = Math.round(y * 6);
	if ((gx * 5 + gy * 3) % 7 === 0) {
		const ox = x * 6 - gx;
		const oy = y * 6 - gy;
		if ((Math.abs(ox) < 0.05 && Math.abs(oy) < 0.22) || (Math.abs(oy) < 0.05 && Math.abs(ox) < 0.22)) return [0.9, 'ink'];
	}
	// The planet small in its sky, so the whole ring fits the screen with
	// space round it: `S` scales the planet and its ring together.
	const S = 0.58;
	const R = 0.36 * S;
	const px = x + 0.02;
	const py = y + 0.01;
	const d2 = (px * px + py * py) / (R * R);
	const tilt = -0.36;
	const rx = px * Math.cos(tilt) - py * Math.sin(tilt);
	const ry = px * Math.sin(tilt) + py * Math.cos(tilt);
	const e = Math.hypot(rx / (0.64 * S), ry / (0.13 * S));
	// Two bands with a dark gap between them, like the real thing.
	const ring = (e > 0.66 && e < 0.8) || (e > 0.85 && e < 1);
	const ringTone = e < 0.8 ? 0.95 : 0.6;
	if (d2 <= 1) {
		if (ring && ry > 0) return [ringTone, 'sun'];
		const nz = Math.sqrt(1 - d2);
		const light = clamp(-0.55 * (px / R) - 0.5 * (py / R) + 0.68 * nz);
		const bands = 0.85 + 0.15 * Math.sin((py / R) * 8 + 0.6);
		return [0.05 + 0.95 * Math.pow(light, 0.75) * bands, 'ink'];
	}
	if (ring) return [ringTone * 0.85, 'sun'];
	return star(x, y) ? [0.3, 'ink'] : null;
};

/** A rock game: an electric guitar on the diagonal, neck up to the right,
 *  its body in peach with lime pickups, frets along the neck, a headstock
 *  with its pegs, and notes in the air beside it. */
const guitar: Game = (x, y, aspect) => {
	const s = Math.min(1, aspect * 0.95);
	const u = x / s;
	const v = y / s;
	// The neck and headstock, along a line from the body to the top right.
	const ax = -0.06;
	const ay = 0.1;
	const bx = 0.3;
	const by = -0.42;
	const dx = bx - ax;
	const dy = by - ay;
	const len2 = dx * dx + dy * dy;
	const t = ((u - ax) * dx + (v - ay) * dy) / len2;
	const dist = Math.abs((u - ax) * dy - (v - ay) * dx) / Math.sqrt(len2);
	if (t > 0.86 && t < 1.04 && dist < 0.045) {
		const peg = Math.abs(dist - 0.04) < 0.012 && Math.floor(t * 60) % 3 === 0;
		return [peg ? 1 : 0.85, peg ? 'lime' : 'ink'];
	}
	if (t > 0 && t <= 0.86 && dist < 0.026) {
		const fret = Math.floor(t * 40) % 3 === 0;
		return [fret ? 1 : 0.6, 'ink'];
	}
	// The body: two bouts and a waist, a horn toward the neck.
	const lower = Math.hypot((u + 0.16) / 0.21, (v - 0.29) / 0.17);
	const upper = Math.hypot((u + 0.05) / 0.15, (v - 0.1) / 0.11);
	const horn = Math.hypot((u - 0.06) / 0.05, (v - 0.04) / 0.09);
	if (lower < 1 || upper < 1 || horn < 1) {
		// Two pickups across the strings, and the bridge.
		const k = (u - ax) * dx + (v - ay) * dy;
		const pickup = dist < 0.07 && [-0.03, -0.065, -0.1].some((at) => Math.abs(k / Math.sqrt(len2) - at) < 0.012);
		if (pickup) return [0.95, 'lime'];
		const edge = Math.min(lower, upper, horn);
		return [0.45 + 0.5 * (1 - edge), 'sun'];
	}
	// Notes in the air, to the left of the neck.
	const notes: [number, number][] = [
		[-0.3, -0.25],
		[0.05, -0.35]
	];
	for (const [nx, ny] of notes) {
		const head = Math.hypot((u - nx) / 0.03, (v - ny) / 0.022) < 1;
		const stem = Math.abs(u - nx - 0.027) < 0.007 && v < ny && v > ny - 0.1;
		if (head || stem) return [0.85, 'pale'];
	}
	return star(x, y) ? [0.25, 'ink'] : null;
};

/** Rex mid-stride over the ground, a cactus coming. */
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
	'...xxxxxx......',
	'....xxx.x......',
	'....x....x.....',
	'.........xx....'
];
const CACTUS = ['..x..', '..x.x', 'x.x.x', 'x.xxx', 'xxx..', '..x..', '..x..', '..x..'];
const runner: Game = (x, y) => {
	const ground = 0.3;
	if (Math.abs(y - ground) < 0.022) return [0.55, 'ink'];
	if (y > ground && Math.abs(y - ground - 0.07) < 0.012 && Math.round(x * 30) % 3 === 0) return [0.25, 'ink'];
	if (sprite(REX, x, y, -0.55, ground - 16 * 0.034, 0.034)) return [1, 'lime'];
	if (sprite(CACTUS, x, y, 0.32, ground - 8 * 0.04, 0.04)) return [0.9, 'ink'];
	if (Math.abs(y + 0.3) < 0.04 && Math.abs(x - 0.1) < 0.12) return [0.2, 'ink'];
	return null;
};

/** A sun going down behind mountains, a grid floor running to it. */
const sunset: Game = (x, y) => {
	const horizon = 0.12;
	const sy = y + 0.05;
	const sun = Math.hypot(x, sy) < 0.3 && y < horizon;
	if (sun) {
		// The sun's slats, wider toward the horizon.
		const slat = y > -0.08 && Math.sin((y - horizon) * 60) > 0.55 - (y + 0.08) * 2;
		if (slat) return null;
		return [0.55 + 0.45 * clamp((horizon - y) / 0.4), y < -0.05 ? 'sun' : 'lime'];
	}
	const ridge = horizon - 0.12 * Math.max(0, 1 - Math.abs(frac(x * 2.4) * 2 - 1) * 1.4);
	if (y < horizon && y > ridge && Math.abs(x) > 0.18) return [0.3, 'ink'];
	if (y >= horizon) {
		const d = y - horizon;
		const row = Math.sin(Math.log(d + 0.02) * 9) > 0.86;
		const col = frac((x / (d + 0.08)) * 0.9 + 0.04) < 0.08;
		if (row || col) return [0.35 + d, 'pale'];
		return null;
	}
	return star(x, y) ? [0.25, 'ink'] : null;
};

/** A squadron in formation over a ship. Drawn for this cabinet, not borrowed. */
const ALIEN = ['...xxxxx...', '.xxxxxxxxx.', 'xx..xxx..xx', 'xxxxxxxxxxx', '..xx...xx..', '.xx.x.x.xx.', 'xx.......xx'];
const SHIP = ['....x....', '...xxx...', '.xxxxxxx.', 'xxxxxxxxx'];
const squadron: Game = (x, y, aspect) => {
	const cell = 0.022;
	for (let row = 0; row < 3; row++) {
		for (let col = 0; col < 5; col++) {
			const left = -aspect * 0.38 + col * 0.3 + (row % 2) * 0.06;
			if (sprite(ALIEN, x, y, left, -0.42 + row * 0.2, cell)) return [row === 0 ? 0.95 : 0.7, 'ink'];
		}
	}
	if (sprite(SHIP, x, y, -0.1, 0.32, 0.026)) return [1, 'lime'];
	if (Math.abs(x + 0.0) < 0.008 && y > 0.05 && y < 0.25) return [0.6, 'lime'];
	if (Math.abs(y - 0.46) < 0.01) return [0.4, 'ink'];
	return null;
};

/** A voice, as Phonon would show it: a waveform, mirrored about its line. */
const voice: Game = (x, y, aspect) => {
	const t = x / aspect + 0.5;
	const env = Math.abs(Math.sin(t * 9.5) * Math.sin(t * 3.1 + 0.8)) * 0.85 + 0.06;
	const bar = Math.abs(frac(x * 22) - 0.5) < 0.32;
	const a = env * 0.42;
	if (bar && Math.abs(y) < a) {
		const k = 1 - Math.abs(y) / a;
		return [0.35 + 0.65 * k, k > 0.6 ? 'lime' : 'ink'];
	}
	if (Math.abs(y) < 0.008) return [0.3, 'ink'];
	return null;
};

/** Two paddles, a ball, a net, the score. */
const DIGITS: Record<string, string[]> = {
	'3': ['xxx', '..x', 'xxx', '..x', 'xxx'],
	'7': ['xxx', '..x', '..x', '..x', '..x']
};
const paddles: Game = (x, y, aspect) => {
	const edge = aspect * 0.42;
	if (Math.abs(x + edge) < 0.02 && Math.abs(y + 0.12) < 0.12) return [1, 'ink'];
	if (Math.abs(x - edge) < 0.02 && Math.abs(y - 0.1) < 0.12) return [1, 'ink'];
	if (Math.hypot(x - 0.18, y + 0.05) < 0.035) return [1, 'sun'];
	if (Math.abs(x) < 0.016 && Math.sin(y * 34) > 0) return [0.5, 'ink'];
	if (sprite(DIGITS['3'], x, y, -0.22, -0.44, 0.03) || sprite(DIGITS['7'], x, y, 0.13, -0.44, 0.03)) return [0.8, 'pale'];
	return null;
};

/** A maze: a fixed plan of walls, a few pellets, the player. */
const MAZE = [
	'xxxxxxxxxxxxxxx',
	'x.....x.......x',
	'x.xxx.x.xxxxx.x',
	'x.x.........x.x',
	'x.x.xxx.xxx.x.x',
	'x.....x.x.....x',
	'xxx.x.....x.xxx',
	'x...x.xxx.x...x',
	'x.xxx.....xxx.x',
	'xxxxxxxxxxxxxxx'
];
const maze: Game = (x, y, aspect) => {
	const cell = Math.min((aspect * 0.92) / MAZE[0].length, 0.92 / MAZE.length);
	const left = (-MAZE[0].length * cell) / 2;
	const top = (-MAZE.length * cell) / 2;
	const c = Math.floor((x - left) / cell);
	const r = Math.floor((y - top) / cell);
	if (r < 0 || r >= MAZE.length || c < 0 || c >= MAZE[0].length) return null;
	if (MAZE[r][c] === 'x') return [0.75, 'ink'];
	const fx = (x - left) / cell - c - 0.5;
	const fy = (y - top) / cell - r - 0.5;
	if (r === 3 && c === 7 && Math.hypot(fx, fy) < 0.38) return [1, 'sun'];
	if (Math.hypot(fx, fy) < 0.12 && (r + c) % 2 === 0) return [0.3, 'pale'];
	return null;
};

export const GAMES = { planet, runner, sunset, squadron, voice, paddles, maze, guitar } as const;
export type GameName = keyof typeof GAMES;
