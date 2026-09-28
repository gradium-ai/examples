// Step 1 of the article: the two Choice questions sent to Jev in one request.
export const QUESTIONS = {
  tone: {
    type: "choice",
    instructions: "How does the writer of this message feel?",
    criteria: {
      frustrated: "Annoyed, upset, or dissatisfied.",
      neutral: "Matter-of-fact, no strong emotion.",
      enthusiastic: "Excited, happy, or eager.",
    },
  },
  energy: {
    type: "choice",
    instructions: "How urgent is this request?",
    criteria: {
      relaxed: "Can be handled at a normal pace.",
      urgent: "Needs prompt attention.",
    },
  },
} as const;

export const DEFAULTS = { tone: "neutral", energy: "relaxed" } as const;
export const MIN_CONFIDENCE = 0.6;

export const TONES = Object.keys(QUESTIONS.tone.criteria) as (keyof typeof QUESTIONS.tone.criteria)[];
export const ENERGIES = Object.keys(QUESTIONS.energy.criteria) as (keyof typeof QUESTIONS.energy.criteria)[];
export const REGISTERS = ["formal", "casual"] as const;
export const LANGUAGES = ["en", "fr", "de"] as const;
