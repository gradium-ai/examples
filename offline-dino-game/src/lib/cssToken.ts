/**
 * Read a theme token as a resolved colour, for the places CSS `var()` cannot
 * reach: canvas libraries (WaveSurfer), Chart.js configs, SVG `color` props
 * on the server.
 *
 * Everywhere else, use `var(--token)` in a class. This is the escape hatch,
 * not the default — a literal fallback is still required so SSR and tests
 * paint something.
 */
export function cssToken(name: string, fallback: string): string {
	if (typeof window === 'undefined') return fallback;
	return getComputedStyle(document.documentElement).getPropertyValue(name).trim() || fallback;
}
