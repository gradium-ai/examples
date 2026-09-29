import { voicePrompt } from "./prompt";
import { resolveWithStock } from "./resolve";
import type { LibraryEntry, VoiceSpec } from "./types";

// Steps 2 and 3 of a turn: pure functions, timed to the microsecond.
export function mapAndResolve(spec: VoiceSpec, library: Map<string, LibraryEntry>) {
  const t0 = performance.now();
  const prompt = voicePrompt(spec);
  const t1 = performance.now();
  const resolution = resolveWithStock(spec, library);
  const t2 = performance.now();
  return { spec, prompt, resolution, t0, mapMs: t1 - t0, resolveMs: t2 - t1 };
}
