/**
 * Text as a dot-matrix marquee can show it.
 *
 * Komuna, the page's display face, has no accented letters: É, Ü, Ç, Ã fall
 * back to another face mid-word, heavier and solid, which breaks the dot
 * matrix exactly where French, German, Spanish and Portuguese need it. An
 * arcade marquee never had accents either, so this does what they did:
 * German umlauts and ß are spelled out (MÜNZE → MUENZE, the way German
 * keyboards without them always wrote it), and every other mark is dropped
 * (TERMINÉE → TERMINEE, NÃO → NAO).
 *
 * Only for text set in Komuna. Anything set in the sans or the mono keeps its
 * accents; that is where the small, readable copy lives.
 */
const SPELLED: Record<string, string> = {
	ä: 'ae',
	ö: 'oe',
	ü: 'ue',
	Ä: 'AE',
	Ö: 'OE',
	Ü: 'UE',
	ß: 'ss'
};

export function marquee(text: string): string {
	return text
		.replace(/[äöüÄÖÜß]/g, (c) => SPELLED[c])
		.normalize('NFD')
		.replace(/\p{M}/gu, '');
}
