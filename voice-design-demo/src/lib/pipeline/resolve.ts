import type { Language, LibraryEntry, VoiceSpec } from "./types";

// Step 3 of the article: pick an approved voice now, never wait for Voice Design.
export const WEIGHTS = { tone: 2, energy: 1, register: 1 } as const;

export const specKey = (s: VoiceSpec) => `${s.language}:${s.register}:${s.tone}:${s.energy}`;

const KEY_RE = /^(en|fr|de):(formal|casual):(frustrated|neutral|enthusiastic):(relaxed|urgent)$/;

export function parseSpecKey(key: string): VoiceSpec | null {
  const m = KEY_RE.exec(key);
  if (!m) return null;
  return { language: m[1], register: m[2], tone: m[3], energy: m[4] } as VoiceSpec;
}

export const distance = (a: VoiceSpec, b: VoiceSpec) =>
  (Object.entries(WEIGHTS) as [keyof typeof WEIGHTS, number][])
    .reduce((d, [field, w]) => d + (a[field] === b[field] ? 0 : w), 0);

export type Resolution = { voiceId: string; exact: boolean; key?: string; distance: number; stock?: boolean };

export function resolveVoice(spec: VoiceSpec, library: Map<string, LibraryEntry>): Resolution {
  const exact = library.get(specKey(spec));
  if (exact) return { voiceId: exact.voiceId, exact: true, key: specKey(spec), distance: 0 };

  let best: (LibraryEntry & { distance: number }) | null = null;
  for (const entry of library.values()) {
    if (entry.spec.language !== spec.language) continue;
    const d = distance(entry.spec, spec);
    if (!best || d < best.distance) best = { ...entry, distance: d };
  }
  if (!best) throw new Error(`No approved voice for "${spec.language}"`);
  return { voiceId: best.voiceId, exact: false, key: specKey(best.spec), distance: best.distance };
}

// Demo-only: before any voice is approved for a language, `resolveVoice` throws.
// The demo then speaks with a Gradium flagship voice so the page stays usable.
export const STOCK_VOICES: Record<Language, { voiceId: string; name: string }> = {
  en: { voiceId: "4SZHfMpw-p46Ywgs", name: "Harper (flagship)" },
  fr: { voiceId: "YhIHaAfQ0cQPDV9R", name: "Solene (flagship)" },
  de: { voiceId: "MAYVpVTYBzLRqNC7", name: "Resi (flagship)" },
};

export function resolveWithStock(spec: VoiceSpec, library: Map<string, LibraryEntry>): Resolution {
  try {
    return resolveVoice(spec, library);
  } catch {
    return { voiceId: STOCK_VOICES[spec.language].voiceId, exact: false, distance: Infinity, stock: true };
  }
}
