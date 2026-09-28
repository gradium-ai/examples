"use client";

import { useCallback, useEffect, useRef, useState } from "react";
import { AUDITION } from "@/lib/content";
import type { ClassifyResult, Language, LibraryEntry, Register, UpstreamCall, VoiceSpec } from "@/lib/pipeline/types";
import { specKey } from "@/lib/pipeline/resolve";
import { beginTrace, handleFor, type TraceHandle } from "@/lib/trace";

type Headers = Record<string, string>;

async function api<T>(path: string, headers: Headers, init: RequestInit = {}) {
  const started = performance.now();
  const res = await fetch(path, { ...init, headers: { ...headers, ...(init.headers as Headers) } });
  const clientMs = performance.now() - started;
  const json = res.headers.get("content-type")?.includes("json") ? await res.json() : null;
  return { res, json: json as T & { error?: string; upstream?: UpstreamCall }, clientMs, started };
}

/** Records a server-measured upstream call as a child row, centred inside the browser round trip. */
function recordUpstream(trace: TraceHandle, name: string, parentStart: number, clientMs: number, upstream: UpstreamCall, lane: "hot" | "off") {
  const offset = Math.max(0, (clientMs - upstream.ms) / 2);
  trace.record({
    name,
    lane,
    child: true,
    start: parentStart + offset,
    end: parentStart + offset + upstream.ms,
    status: upstream.status < 400 ? "ok" : "error",
    detail: `${upstream.method} ${upstream.status}`,
    upstream,
  });
}

export type Classified = ClassifyResult & { serverMs: number; clientMs: number; traceId: string };

// Step 1: classify the message as the user types, debounced and abortable.
export function useClassify(text: string, language: Language, register: Register, headers: Headers, debounceMs = 450) {
  const [result, setResult] = useState<Classified | null>(null);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const turn = useRef(0);
  const empty = !text.trim();
  // language and register are passed in, not classified, so changing them does not re-call Jev.
  const ctx = useRef({ language, register });
  useEffect(() => {
    ctx.current = { language, register };
  }, [language, register]);

  useEffect(() => {
    if (empty) return;
    const controller = new AbortController();
    const timer = setTimeout(async () => {
      setPending(true);
      const trace = beginTrace("turn", `turn #${++turn.current}`);
      const span = trace.span("POST /api/classify", "hot");
      const started = performance.now();
      try {
        const res = await fetch("/api/classify", {
          method: "POST",
          headers,
          body: JSON.stringify({ message: text, ...ctx.current }),
          signal: controller.signal,
        });
        const clientMs = performance.now() - started;
        const json = await res.json();
        if (!res.ok) {
          span.end({ status: "error", detail: json.error, upstream: json.upstream });
          setError(json.error ?? `HTTP ${res.status}`);
        } else {
          span.end({ detail: json.source === "offline" ? "offline classifier" : `${json.source} · ${json.model}` });
          if (json.upstream) recordUpstream(trace, "Jev decision (upstream)", started, clientMs, json.upstream, "hot");
          else trace.record({ name: "keyword classifier (offline)", lane: "hot", child: true, start: started, end: started + json.serverMs, status: "ok" });
          setError(null);
          setResult({ ...json, clientMs, traceId: trace.id });
        }
      } catch {
        span.end({ status: "error", detail: "aborted" });
        return;
      }
      setPending(false);
    }, debounceMs);
    return () => {
      clearTimeout(timer);
      controller.abort();
    };
  }, [text, empty, headers, debounceMs]);

  return { result: empty ? null : result, pending: !empty && pending, error: empty ? null : error };
}

// The approved library lives in the Gradium account: custom voices named after a spec key.
export function useLibrary(headers: Headers, enabled: boolean) {
  const [library, setLibrary] = useState<Map<string, LibraryEntry>>(new Map());
  const [state, setState] = useState<{ loading: boolean; error?: string; totalCustom?: number }>({ loading: false });

  const refresh = useCallback(async () => {
    if (!enabled) return setLibrary(new Map());
    setState((s) => ({ ...s, loading: true }));
    const trace = beginTrace("library", "load approved voices");
    const span = trace.span("GET /api/library", "off");
    const { res, json, clientMs, started } = await api<{ entries: LibraryEntry[]; totalCustom: number }>("/api/library", headers);
    if (!res.ok) {
      span.end({ status: "error", detail: json?.error, upstream: json?.upstream });
      return setState({ loading: false, error: json?.error ?? `HTTP ${res.status}` });
    }
    span.end({ detail: `${json.entries.length} approved of ${json.totalCustom} custom voices` });
    if (json.upstream) recordUpstream(trace, "Gradium GET /voices", started, clientMs, json.upstream, "off");
    setLibrary(new Map(json.entries.map((e) => [specKey(e.spec), e])));
    setState({ loading: false, totalCustom: json.totalCustom });
  }, [headers, enabled]);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- fetch on key change
    refresh();
  }, [refresh]);

  return { library, refresh, ...state };
}

export type Spoken = { url: string; voiceId: string; clientMs: number; ttfbMs: number; upstreamMs: number; bytes: number };

// Step 4: synthesize the reply with whatever voice the resolver picked.
export function useSpeak(headers: Headers) {
  const [state, setState] = useState<{ pending: boolean; last?: Spoken; error?: string }>({ pending: false });

  const speak = useCallback(
    async (text: string, voiceId: string) => {
      setState((s) => ({ ...s, pending: true, error: undefined }));
      const trace = beginTrace("speak", "speak reply");
      const span = trace.span("POST /api/speak", "hot", { detail: voiceId });
      const started = performance.now();
      const res = await fetch("/api/speak", { method: "POST", headers, body: JSON.stringify({ text, voiceId }) });
      if (!res.ok) {
        const json = await res.json().catch(() => ({}));
        span.end({ status: "error", detail: json.error, upstream: json.upstream });
        return setState({ pending: false, error: json.error ?? `HTTP ${res.status}` });
      }
      const blob = await res.blob();
      const clientMs = performance.now() - started;
      const ttfbMs = Number(res.headers.get("x-upstream-ttfb-ms"));
      const upstreamMs = Number(res.headers.get("x-upstream-ms"));
      const bytes = Number(res.headers.get("x-upstream-bytes"));
      span.end({ detail: `${(bytes / 1024).toFixed(0)} KB wav` });
      const upstream = { method: "POST", url: "https://api.gradium.ai/api/post/speech/tts", status: 200, request: { text, voice_id: voiceId, output_format: "wav", only_audio: true }, response: `audio/wav, ${bytes} bytes` };
      const offset = Math.max(0, (clientMs - upstreamMs) / 2);
      trace.record({ name: "Gradium TTS: first byte", lane: "hot", child: true, start: started + offset, end: started + offset + ttfbMs, status: "ok", upstream: { ...upstream, ms: ttfbMs } });
      trace.record({ name: "Gradium TTS: full body", lane: "hot", child: true, start: started + offset, end: started + offset + upstreamMs, status: "ok", upstream: { ...upstream, ms: upstreamMs } });
      const url = URL.createObjectURL(blob);
      setState((s) => {
        if (s.last) URL.revokeObjectURL(s.last.url);
        return { pending: false, last: { url, voiceId, clientMs, ttfbMs, upstreamMs, bytes } };
      });
    },
    [headers],
  );

  return { ...state, speak };
}

export type DesignStatus = "queued" | "generating" | "waiting" | "ready" | "converting" | "approved" | "error";
export type DesignCandidate = { id: string; ready: boolean; audio?: string; auditioning?: boolean };
export type DesignItem = {
  key: string;
  spec: VoiceSpec;
  status: DesignStatus;
  candidates: DesignCandidate[];
  polls: number;
  error?: string;
  voiceId?: string;
  traceId?: string;
  waitedMs?: number;
};

const POLL_MS = 500;
const TIMEOUT_MS = 120_000;
const N_SAMPLES = 3;

// The dotted path of the article: generate, wait, audition, convert. Nothing here
// is awaited by the conversation; the resolver keeps answering from the library.
export function useDesignQueue(headers: Headers, onApproved: () => void) {
  const [items, setItems] = useState<DesignItem[]>([]);
  const patch = useCallback((key: string, fn: (i: DesignItem) => Partial<DesignItem>) => {
    setItems((all) => all.map((i) => (i.key === key ? { ...i, ...fn(i) } : i)));
  }, []);

  const enqueue = useCallback((spec: VoiceSpec) => {
    const key = specKey(spec);
    setItems((all) => (all.some((i) => i.key === key) ? all : [{ key, spec, status: "queued", candidates: [], polls: 0 }, ...all]));
  }, []);

  const dismiss = useCallback((key: string) => setItems((all) => all.filter((i) => i.key !== key)), []);

  const generate = useCallback(
    async (key: string) => {
      const trace = beginTrace("design", `design ${key}`);
      patch(key, () => ({ status: "generating", error: undefined, candidates: [], polls: 0, traceId: trace.id }));
      const span = trace.span("generate candidates", "off");
      const { res, json, clientMs, started } = await api<{ ids: string[] }>("/api/design/generate", headers, {
        method: "POST",
        body: JSON.stringify({ key, n: N_SAMPLES }),
      });
      if (!res.ok) {
        span.end({ status: "error", detail: json?.error, upstream: json?.upstream });
        return patch(key, () => ({ status: "error", error: json?.error }));
      }
      span.end({ detail: `${json.ids.length} candidates` });
      if (json.upstream) recordUpstream(trace, "Gradium POST /voice-generator/generate", started, clientMs, json.upstream, "off");
      patch(key, () => ({ status: "waiting", candidates: json.ids.map((id) => ({ id, ready: false })) }));

      // waitUntilReady from the article, run for every candidate at once.
      const wait = trace.span("wait until ready", "off");
      const waitStart = performance.now();
      const pendingIds = new Set(json.ids);
      let polls = 0;
      let last: UpstreamCall | undefined;
      while (pendingIds.size && performance.now() - waitStart < TIMEOUT_MS) {
        await new Promise((r) => setTimeout(r, POLL_MS));
        const results = await Promise.all(
          [...pendingIds].map(async (id) => {
            const r = await api<{ ready: boolean }>(`/api/design/status?id=${encodeURIComponent(id)}`, headers);
            last = r.json?.upstream ?? last;
            return { id, ready: Boolean(r.res.ok && r.json.ready) };
          }),
        );
        polls += 1;
        for (const { id, ready } of results) {
          if (!ready) continue;
          pendingIds.delete(id);
          handleFor(trace.id).record({ name: `candidate ${json.ids.indexOf(id) + 1} ready`, lane: "off", child: true, start: waitStart, end: performance.now(), status: "ok", detail: id });
        }
        patch(key, (i) => ({ polls, candidates: i.candidates.map((c) => ({ ...c, ready: !pendingIds.has(c.id) })) }));
      }
      const waitedMs = performance.now() - waitStart;
      if (pendingIds.size) {
        wait.end({ status: "error", detail: `timed out after ${polls} polls`, upstream: last });
        return patch(key, () => ({ status: "error", error: "Candidates not ready after 2 minutes", waitedMs }));
      }
      wait.end({ detail: `${polls} polls every ${POLL_MS}ms`, upstream: last });
      patch(key, () => ({ status: "ready", waitedMs }));
    },
    [headers, patch],
  );

  const audition = useCallback(
    async (item: DesignItem, candidateId: string) => {
      const trace = handleFor(item.traceId ?? beginTrace("design", `design ${item.key}`).id);
      patch(item.key, (i) => ({ candidates: i.candidates.map((c) => (c.id === candidateId ? { ...c, auditioning: true } : c)) }));
      const span = trace.span(`audition ${candidateId.slice(-6)}`, "off");
      const res = await fetch("/api/speak", { method: "POST", headers, body: JSON.stringify({ text: AUDITION[item.spec.language](item.candidates.findIndex((c) => c.id === candidateId) + 1), voiceId: candidateId }) });
      if (!res.ok) {
        const json = await res.json().catch(() => ({}));
        span.end({ status: "error", detail: json.error, upstream: json.upstream });
        return patch(item.key, (i) => ({ error: json.error, candidates: i.candidates.map((c) => (c.id === candidateId ? { ...c, auditioning: false } : c)) }));
      }
      const url = URL.createObjectURL(await res.blob());
      span.end({ detail: `TTS first byte ${res.headers.get("x-upstream-ttfb-ms")}ms` });
      patch(item.key, (i) => ({ candidates: i.candidates.map((c) => (c.id === candidateId ? { ...c, auditioning: false, audio: url } : c)) }));
      new Audio(url).play().catch(() => {});
    },
    [headers, patch],
  );

  const convert = useCallback(
    async (item: DesignItem, candidateId: string) => {
      const trace = handleFor(item.traceId ?? beginTrace("design", `design ${item.key}`).id);
      patch(item.key, () => ({ status: "converting" }));
      const span = trace.span("convert to voice_id", "off");
      const { res, json, clientMs, started } = await api<{ uid: string }>("/api/design/convert", headers, {
        method: "POST",
        body: JSON.stringify({ key: item.key, candidateId }),
      });
      if (!res.ok) {
        span.end({ status: "error", detail: json?.error, upstream: json?.upstream });
        return patch(item.key, () => ({ status: "ready", error: json?.error }));
      }
      span.end({ detail: json.uid });
      if (json.upstream) recordUpstream(trace, "Gradium POST /voices/from-embedding", started, clientMs, json.upstream, "off");
      patch(item.key, () => ({ status: "approved", voiceId: json.uid }));
      onApproved();
    },
    [headers, patch, onApproved],
  );

  return { items, enqueue, dismiss, generate, audition, convert };
}
