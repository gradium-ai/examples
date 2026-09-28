export type Language = "en" | "fr" | "de";
export type Register = "formal" | "casual";
export type Tone = "frustrated" | "neutral" | "enthusiastic";
export type Energy = "relaxed" | "urgent";

export type VoiceSpec = { language: Language; register: Register; tone: Tone; energy: Energy };

export type LibraryEntry = { spec: VoiceSpec; voiceId: string; name: string };

export type Answer = {
  choice: string;
  confidence: number;
  probabilities: Record<string, number>;
  /** True when confidence fell below MIN_CONFIDENCE and the default was used instead. */
  fellBack: boolean;
};

/** What the server saw on the wire for one upstream call. Keys are redacted. */
export type UpstreamCall = {
  method: string;
  url: string;
  status: number;
  ms: number;
  request?: unknown;
  response?: unknown;
};

export type ClassifyResult = {
  context: VoiceSpec;
  answers: { tone: Answer; energy: Answer };
  source: "openrouter" | "typesafe" | "offline";
  model: string;
  costUsd?: number;
  inputTokens?: number;
  upstream?: UpstreamCall;
};

export type Candidate = { id: string; ready: boolean };
