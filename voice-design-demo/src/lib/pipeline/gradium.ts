import "server-only";
import type { UpstreamCall, VoiceSpec } from "./types";
import { voicePrompt } from "./prompt";
import { parseSpecKey, specKey } from "./resolve";

const BASE = "https://api.gradium.ai/api";

const headers = (key: string) => ({ "x-api-key": key, "Content-Type": "application/json" });

export class UpstreamError extends Error {
  constructor(message: string, readonly upstream: UpstreamCall) {
    super(message);
  }
}

async function call(key: string, method: string, path: string, body?: unknown) {
  const url = `${BASE}${path}`;
  const started = performance.now();
  const res = await fetch(url, { method, headers: headers(key), body: body ? JSON.stringify(body) : undefined });
  const text = await res.text();
  let json: unknown = text;
  try {
    json = JSON.parse(text);
  } catch {}
  const upstream: UpstreamCall = { method, url, status: res.status, ms: Math.round(performance.now() - started), request: body, response: json };
  if (!res.ok) throw new UpstreamError(`${method} ${path} failed: ${res.status}`, upstream);
  return { json: json as Record<string, unknown>, upstream };
}

// Article: generateCandidates
export async function generateCandidates(key: string, spec: VoiceSpec, n = 3) {
  const { json, upstream } = await call(key, "POST", "/voice-generator/generate", {
    prompt: voicePrompt(spec),
    language: spec.language,
    n_samples: n,
  });
  const embeddings = json.embeddings as { embedding_id: string }[];
  return { ids: embeddings.map((e) => e.embedding_id), upstream };
}

// Article: one iteration of waitUntilReady. The loop runs in the browser so
// every poll shows up in the trace.
export async function isReady(key: string, id: string) {
  const { json, upstream } = await call(key, "GET", `/voice-generator/embeddings?embedding_id=${encodeURIComponent(id)}`);
  const embeddings = json.embeddings as { ready?: boolean }[];
  return { ready: Boolean(embeddings[0]?.ready), upstream };
}

// Article: convert
export async function convert(key: string, candidateId: string, spec: VoiceSpec) {
  const { json, upstream } = await call(key, "POST", "/voices/from-embedding", {
    voxium_embedding_id: candidateId,
    name: specKey(spec),
    description: voicePrompt(spec),
  });
  return { uid: json.uid as string, upstream };
}

/** Approved voices are the account's custom voices whose name is a spec key. */
export async function listLibrary(key: string) {
  const { json, upstream } = await call(key, "GET", "/voices/?limit=500");
  const voices = (Array.isArray(json) ? json : []) as { uid: string; name: string }[];
  const entries = voices.flatMap((v) => {
    const spec = parseSpecKey(v.name);
    return spec ? [{ spec, voiceId: v.uid, name: v.name }] : [];
  });
  return { entries, totalCustom: voices.length, upstream: { ...upstream, response: `${voices.length} voices` } };
}

// Article: speak. Returns timings separately: time to headers and time to full body.
export async function speak(key: string, text: string, voiceId: string) {
  const url = `${BASE}/post/speech/tts`;
  const body = { text, voice_id: voiceId, output_format: "wav", only_audio: true };
  const started = performance.now();
  const res = await fetch(url, { method: "POST", headers: headers(key), body: JSON.stringify(body) });
  const ttfbMs = Math.round(performance.now() - started);
  if (!res.ok) {
    const err = await res.text();
    throw new UpstreamError(`TTS failed: ${res.status}`, { method: "POST", url, status: res.status, ms: ttfbMs, request: body, response: err });
  }
  const audio = await res.arrayBuffer();
  return { audio, ttfbMs, totalMs: Math.round(performance.now() - started), request: body, url };
}
