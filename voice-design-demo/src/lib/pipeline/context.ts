import "server-only";
import type { Answer, ClassifyResult, Language, Register, UpstreamCall } from "./types";
import { DEFAULTS, MIN_CONFIDENCE, QUESTIONS } from "./questions";
import { offlineAnswers } from "./offline";

export type JevCreds = { provider: "openrouter" | "typesafe"; key: string };

const ENDPOINTS = {
  openrouter: { url: "https://openrouter.ai/api/alpha/decisions", model: "typesafe/jev-1.13" },
  typesafe: { url: "https://api.typesafe.ai/v1/systemone", model: "jev-latest" },
};

type RawAnswer = { choice: string; confidence: number; probabilities: Record<string, number> };

// Same shape as `extractContext` in the article, with the credentials passed in
// instead of read from process.env, and the raw answers kept for the demo UI.
export async function extractContext(
  message: string,
  { language, register }: { language: Language; register: Register },
  creds: JevCreds | null,
  signal?: AbortSignal,
): Promise<ClassifyResult> {
  if (!creds) {
    const answers = applyThreshold(offlineAnswers(message));
    return { context: toContext(answers, language, register), answers, source: "offline", model: "keyword-offline" };
  }

  const { url, model } = ENDPOINTS[creds.provider];
  const body = { model, state: message, questions: QUESTIONS };
  const started = performance.now();
  const res = await fetch(url, {
    method: "POST",
    headers: { Authorization: `Bearer ${creds.key}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
    signal,
  });
  const json = await res.json().catch(() => null);
  const upstream: UpstreamCall = {
    method: "POST",
    url,
    status: res.status,
    ms: Math.round(performance.now() - started),
    request: body,
    response: json,
  };
  if (!res.ok) throw Object.assign(new Error(`Jev request failed: ${res.status}`), { upstream });

  const answers = applyThreshold(json.answers as Record<"tone" | "energy", RawAnswer>);
  return {
    context: toContext(answers, language, register),
    answers,
    source: creds.provider,
    model: json.model ?? model,
    costUsd: json.usage?.cost,
    inputTokens: json.usage?.input_tokens,
    upstream,
  };
}

function applyThreshold(raw: Record<"tone" | "energy", RawAnswer>) {
  const out = {} as Record<"tone" | "energy", Answer>;
  for (const field of ["tone", "energy"] as const) {
    const a = raw[field];
    const fellBack = a.confidence < MIN_CONFIDENCE;
    out[field] = { ...a, choice: fellBack ? DEFAULTS[field] : a.choice, fellBack };
  }
  return out;
}

const toContext = (a: Record<"tone" | "energy", Answer>, language: Language, register: Register) =>
  ({ language, register, tone: a.tone.choice, energy: a.energy.choice }) as ClassifyResult["context"];
