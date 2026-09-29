"use client";

import { useSyncExternalStore } from "react";
import type { UpstreamCall } from "@/lib/pipeline/types";

export type Lane = "hot" | "off";
export type SpanStatus = "running" | "ok" | "error" | "miss";

export type Span = {
  id: string;
  name: string;
  lane: Lane;
  start: number;
  end?: number;
  status: SpanStatus;
  detail?: string;
  /** Measured on the server, shown nested under the browser round trip. */
  child?: boolean;
  upstream?: UpstreamCall;
};

export type Trace = { id: string; kind: "turn" | "speak" | "design" | "library"; title: string; start: number; spans: Span[] };

let traces: Trace[] = [];
const listeners = new Set<() => void>();
let seq = 0;
const MAX_TRACES = 30;

const emit = () => listeners.forEach((l) => l());
const now = () => performance.now();

function mutate(traceId: string, fn: (t: Trace) => Trace) {
  traces = traces.map((t) => (t.id === traceId ? fn(t) : t));
  emit();
}

export type SpanHandle = {
  id: string;
  end: (patch?: Partial<Omit<Span, "id">>) => void;
};

export type TraceHandle = {
  id: string;
  span: (name: string, lane: Lane, extra?: Partial<Span>) => SpanHandle;
  /** Record an already-measured span, e.g. a synchronous step timed with performance.now(). */
  record: (span: Omit<Span, "id">) => void;
};

export function beginTrace(kind: Trace["kind"], title: string, start = now()): TraceHandle {
  const id = `t${++seq}`;
  traces = [{ id, kind, title, start, spans: [] }, ...traces].slice(0, MAX_TRACES);
  emit();
  return handleFor(id);
}

export function handleFor(traceId: string): TraceHandle {
  return {
    id: traceId,
    span(name, lane, extra) {
      const sid = `s${++seq}`;
      const span: Span = { id: sid, name, lane, start: now(), status: "running", ...extra };
      mutate(traceId, (t) => ({ ...t, spans: [...t.spans, span] }));
      return {
        id: sid,
        end: (patch) =>
          mutate(traceId, (t) => ({
            ...t,
            spans: t.spans.map((s) => (s.id === sid ? { ...s, status: "ok", end: now(), ...patch } : s)),
          })),
      };
    },
    record(span) {
      const sid = `s${++seq}`;
      mutate(traceId, (t) => ({ ...t, spans: [...t.spans, { id: sid, ...span }] }));
    },
  };
}

export const clearTraces = () => {
  traces = [];
  emit();
};

const subscribe = (l: () => void) => {
  listeners.add(l);
  return () => listeners.delete(l);
};

const empty: Trace[] = [];
export const useTraces = () => useSyncExternalStore(subscribe, () => traces, () => empty);

export const fmtMs = (ms: number) =>
  ms < 1 ? `${Math.max(1, Math.round(ms * 1000))}µs` : ms < 1000 ? `${Math.round(ms)}ms` : `${(ms / 1000).toFixed(2)}s`;
