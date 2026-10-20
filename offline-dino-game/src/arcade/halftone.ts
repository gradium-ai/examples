/**
 * The arcade page draws in halftone, not pixels: a print screen of dots on a
 * staggered grid (every other row shifted half a pitch, the way a 45° screen
 * reads), each dot as large as the tone it stands for. One helper, three
 * canvases: the title's wordmark, the voice grille, the backdrop's rings.
 */

/** A canvas sized to its element in CSS pixels, its context scaled for the screen. */
export function fitCanvas(
	canvas: HTMLCanvasElement,
	width: number,
	height: number,
	maxDpr = 2
): CanvasRenderingContext2D | null {
	const dpr = Math.min(maxDpr, window.devicePixelRatio || 1);
	canvas.width = Math.max(1, Math.round(width * dpr));
	canvas.height = Math.max(1, Math.round(height * dpr));
	canvas.style.width = `${width}px`;
	canvas.style.height = `${height}px`;
	const ctx = canvas.getContext('2d');
	ctx?.setTransform(dpr, 0, 0, dpr, 0, 0);
	return ctx;
}

/**
 * Every cell of a staggered grid of `pitch` over `width` × `height`, centre
 * first: `visit(x, y, column, row)`.
 */
export function eachCell(
	width: number,
	height: number,
	pitch: number,
	visit: (x: number, y: number, column: number, row: number) => void
): void {
	const rowPitch = pitch * 0.866; // a triangular lattice: rows closer than columns
	const rows = Math.ceil(height / rowPitch) + 1;
	const columns = Math.ceil(width / pitch) + 1;
	for (let row = 0; row < rows; row++) {
		const shift = row % 2 ? pitch / 2 : 0;
		const y = row * rowPitch + rowPitch / 2;
		for (let column = 0; column < columns; column++) {
			visit(column * pitch + shift, y, column, row);
		}
	}
}

/**
 * A deterministic noise in [0, 1) for a cell and a frame: the same cell
 * twinkles the same way each time round, so a loop does not shimmer.
 */
export function hash(a: number, b: number, c = 0): number {
	const n = Math.sin(a * 127.1 + b * 311.7 + c * 74.7) * 43758.5453;
	return n - Math.floor(n);
}

/** One path of dots: `radius(x, y)` in CSS pixels, 0 or less for none. */
export function dotPath(
	ctx: CanvasRenderingContext2D,
	width: number,
	height: number,
	pitch: number,
	radius: (x: number, y: number, column: number, row: number) => number
): void {
	ctx.beginPath();
	eachCell(width, height, pitch, (x, y, column, row) => {
		const r = radius(x, y, column, row);
		if (r <= 0.15) return;
		ctx.moveTo(x + r, y);
		ctx.arc(x, y, r, 0, Math.PI * 2);
	});
}

export const reducedMotion = (): boolean =>
	typeof window !== 'undefined' && window.matchMedia('(prefers-reduced-motion: reduce)').matches;
