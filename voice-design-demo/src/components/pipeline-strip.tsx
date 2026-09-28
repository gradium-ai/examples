"use client";

import { ArrowRight } from "lucide-react";
import type { DesignItem, useClassify, useSpeak } from "@/hooks/use-pipeline";
import type { Resolution } from "@/lib/pipeline/resolve";
import type { VoiceSpec } from "@/lib/pipeline/types";
import { fmtMs, useTraces } from "@/lib/trace";

type NodeState = "idle" | "active" | "done" | "miss" | "error";

export type Computed = { spec: VoiceSpec; prompt: string; resolution: Resolution; mapMs: number; resolveMs: number } | null;

type Props = {
  classify: ReturnType<typeof useClassify>;
  computed: Computed;
  speech: ReturnType<typeof useSpeak>;
  queue: DesignItem[];
  librarySize: number;
};

export function PipelineStrip({ classify, computed, speech, queue, librarySize }: Props) {
  const r = classify.result;
  const res = computed?.resolution;
  const designing = queue.filter((i) => ["generating", "waiting", "converting"].includes(i.status)).length;
  const waiting = queue.filter((i) => i.status === "queued" || i.status === "ready").length;
  const traces = useTraces();
  const designOnHotPath = traces
    .flatMap((t) => t.spans)
    .filter((s) => s.lane === "hot" && /voice-generator|from-embedding/.test(s.upstream?.url ?? "")).length;

  const hot: { label: string; value: string; ms?: number; state: NodeState }[] = [
    { label: "Message", value: r ? "received" : "waiting", state: r ? "done" : "idle" },
    {
      label: "Jev",
      value: r ? `${r.context.tone} · ${r.context.energy}` : classify.error ? "error" : "classify",
      ms: r?.clientMs,
      state: classify.pending ? "active" : classify.error ? "error" : r ? "done" : "idle",
    },
    { label: "Voice spec", value: computed ? `${computed.prompt.length} chars` : "map", ms: computed?.mapMs, state: computed ? "done" : "idle" },
    {
      label: "Resolve",
      value: res ? (res.exact ? "exact" : res.stock ? "stock" : "nearest") : "lookup",
      ms: computed?.resolveMs,
      state: res ? (res.exact ? "done" : "miss") : "idle",
    },
    {
      label: "TTS",
      value: speech.last ? `${fmtMs(speech.last.ttfbMs)} 1st byte` : speech.error ? "error" : "speak",
      ms: speech.last?.clientMs,
      state: speech.pending ? "active" : speech.error ? "error" : speech.last ? "done" : "idle",
    },
  ];

  const off: { label: string; value: string; state: NodeState }[] = [
    { label: "Design queue", value: `${waiting} waiting`, state: waiting ? "miss" : "idle" },
    { label: "Voice Design", value: designing ? `${designing} running` : "generate, audition, convert", state: designing ? "active" : "idle" },
    { label: "Library", value: `${librarySize} approved`, state: librarySize ? "done" : "idle" },
  ];

  const total = r && computed ? r.clientMs + computed.mapMs + computed.resolveMs + (speech.last?.clientMs ?? 0) : null;

  return (
    <section aria-label="Pipeline" className="grid gap-2">
      <div className="flex items-baseline justify-between gap-2">
        <span className="eyebrow">Critical path, runs every turn</span>
        {total !== null && (
          <span className="font-mono text-xs text-muted-foreground tabular-nums">
            {speech.last ? "message to audio" : "message to voice_id"} {fmtMs(total)}
          </span>
        )}
      </div>
      <ol className="grid grid-cols-5 items-stretch gap-1.5">
        {hot.map((n, i) => (
          <li key={n.label} className="relative">
            <Node {...n} />
            {i < hot.length - 1 && <ArrowRight className="absolute top-1/2 -right-2 z-10 size-3 -translate-y-1/2 text-muted-foreground/60" />}
          </li>
        ))}
      </ol>
      <div className="mt-1 flex items-baseline justify-between gap-2">
        <span className="eyebrow">Off the hot path, never awaited by a turn</span>
        <span
          className={`font-mono text-xs tabular-nums ${designOnHotPath ? "text-danger" : "text-muted-foreground"}`}
          title="Voice Design requests recorded on the critical path in the trace"
        >
          Voice Design calls on critical path: {designOnHotPath}
        </span>
      </div>
      <ol className="grid grid-cols-3 gap-1.5">
        {off.map((n) => (
          <li key={n.label}>
            <Node {...n} dashed />
          </li>
        ))}
      </ol>
    </section>
  );
}

const STYLES: Record<NodeState, string> = {
  idle: "border-border text-muted-foreground",
  active: "border-(--mood) pulsing",
  done: "border-(--mood)/60 bg-(--mood)/[0.06]",
  miss: "border-miss bg-miss/10",
  error: "border-danger bg-danger/10",
};

function Node({ label, value, ms, state, dashed }: { label: string; value: string; ms?: number; state: NodeState; dashed?: boolean }) {
  return (
    <div className={`h-full min-w-0 rounded-2xl border bg-card px-2.5 py-2 transition-colors duration-300 sm:px-3 ${dashed ? "border-dashed" : ""} ${STYLES[state]}`}>
      <div className="flex items-baseline justify-between gap-1">
        <span className="truncate text-[11px] font-medium sm:text-xs">{label}</span>
        {ms !== undefined && <span className="hidden font-mono text-[10px] text-muted-foreground tabular-nums sm:inline">{fmtMs(ms)}</span>}
      </div>
      <div className="mt-0.5 truncate font-mono text-[10px] text-muted-foreground sm:text-[11px]">{value}</div>
    </div>
  );
}
