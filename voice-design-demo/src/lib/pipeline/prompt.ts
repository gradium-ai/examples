import type { VoiceSpec } from "./types";

// Step 2 of the article: persona is fixed per language, delivery comes from context.
export const PERSONA = {
  en: "A female voice, 30 to 40, neutral American accent, mid pitch",
  fr: "A female voice, 30 to 40, Parisian accent, mid pitch",
  de: "A female voice, 30 to 40, standard German accent, mid pitch",
} as const;

export const DELIVERY = {
  tone: {
    frustrated: "calm and reassuring, warm rounded resonance",
    neutral: "clear and direct, balanced resonance",
    enthusiastic: "bright and upbeat, lively resonance",
  },
  energy: {
    relaxed: "unhurried pacing, medium energy",
    urgent: "steady, efficient pacing, focused energy",
  },
  register: {
    formal: "Ideal for a professional support line.",
    casual: "Ideal for a friendly in-app assistant.",
  },
} as const;

export function voicePrompt({ language, register, tone, energy }: VoiceSpec) {
  const persona = PERSONA[language];
  if (!persona) throw new Error(`No persona for language "${language}"`);

  const prompt =
    `${persona}: ${DELIVERY.tone[tone]}, ${DELIVERY.energy[energy]}. ` +
    DELIVERY.register[register];

  if (prompt.length > 500) throw new Error("Voice description exceeds 500 characters");
  return prompt;
}

/** The same prompt split by where each part came from, for highlighting in the UI. */
export function voicePromptParts({ language, register, tone, energy }: VoiceSpec) {
  return [
    { source: "persona", text: PERSONA[language] },
    { source: null, text: ": " },
    { source: "tone", text: DELIVERY.tone[tone] },
    { source: null, text: ", " },
    { source: "energy", text: DELIVERY.energy[energy] },
    { source: null, text: ". " },
    { source: "register", text: DELIVERY.register[register] },
  ] as const;
}
