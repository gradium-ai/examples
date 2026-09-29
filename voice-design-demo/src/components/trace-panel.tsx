"use client";

import { ChevronRight } from "lucide-react";
import { useState } from "react";
import { clearTraces, fmtMs, type Span, type Trace, useTraces } from "@/lib/trace";
import { StepLabel } from "./composer-card";

const KIND: Record<Trace["kind"], string> = { turn: "turn", speak: "speak", design: "design", library: "library" };

export function TracePanel() {
  const traces = useTraces();
  const [limit, setLimit] = useState(6);

  return (
    <section className="grid grid-cols-1 gap-2">
      <div className="flex items-baseline justify-between">
        <StepLabel n="obs" title="Trace" />
        {traces.length > 0 && (
          <button onClick={clearTraces} className="px-2 text-xs text-muted-foreground underline decoration-dotted underline-offset-4 hover:text-foreground">
            clear
          </button>
        )}
      </div>
      <div className="card grid gap-1 p-3 sm:p-4">
        <Legend />
        {traces.length === 0 ? (
          <p className="px-1 py-4 text-sm text-muted-foreground">Type a message to record the first turn.</p>
        ) : (
          traces.slice(0, limit).map((t) => <TraceView key={t.id} trace={t} />)
        )}
        {traces.length > limit && (
          <button onClick={() => setLimit((l) => l + 6)} className="py-1 text-xs text-muted-foreground hover:text-foreground">
            show {Math.min(6, traces.length - limit)} more
          </button>
        )}
      </div>
    </section>
  );
}

function Legend() {
  return (
    <div className="flex flex-wrap gap-x-4 gap-y-1 px-1 pb-2 font-mono text-[10px] text-muted-foreground">
      <span className="flex items-center gap-1.5"><span className="h-2 w-4 rounded-sm bg-(--mood)" />critical path</span>
      <span className="flex items-center gap-1.5"><span className="hatch h-2 w-4 rounded-sm" />off the hot path</span>
      <span className="flex items-center gap-1.5"><span className="h-2 w-4 rounded-sm bg-miss" />resolver miss</span>
      <span className="flex items-center gap-1.5"><span className="h-2 w-4 rounded-sm bg-danger" />error</span>
      <span className="flex items-center gap-1.5"><span className="h-2 w-4 rounded-sm border border-(--mood) bg-(--mood)/15" />measured upstream by the server</span>
    </div>
  );
}

function TraceView({ trace }: { trace: Trace }) {
  const [open, setOpen] = useState<string | null>(null);
  const end = Math.max(trace.start + 1, ...trace.spans.map((s) => s.end ?? s.start));
  const dur = end - trace.start;
  const hotMs = trace.spans.filter((s) => s.lane === "hot" && !s.child && s.end).reduce((a, s) => a + (s.end! - s.start), 0);

  return (
    <div className="rounded-xl border border-transparent px-1 py-2 hover:border-border">
      <div className="mb-1.5 flex items-baseline gap-2">
        <span className="chip px-2 py-0 font-mono text-[10px]">{KIND[trace.kind]}</span>
        <span className="truncate text-xs font-medium">{trace.title}</span>
        <span className="ml-auto shrink-0 font-mono text-[10px] text-muted-foreground tabular-nums">
          {hotMs > 0 && <>critical {fmtMs(hotMs)} · </>}span {fmtMs(dur)}
        </span>
      </div>
      <ul className="grid gap-0.5">
        {trace.spans.map((s) => (
          <li key={s.id}>
            <button onClick={() => setOpen(open === s.id ? null : s.id)} className="grid w-full grid-cols-[minmax(0,11rem)_1fr_3.5rem] items-center gap-2 rounded-md px-1 py-0.5 text-left hover:bg-muted/60 sm:grid-cols-[minmax(0,16rem)_1fr_4rem]">
              <span className={`flex min-w-0 items-center gap-1 text-[11px] ${s.child ? "pl-3 text-muted-foreground" : ""}`}>
                <ChevronRight className={`size-3 shrink-0 text-muted-foreground/60 transition-transform ${open === s.id ? "rotate-90" : ""}`} />
                <span className="truncate">{s.name}</span>
              </span>
              <span className="relative h-3">
                <Bar span={s} traceStart={trace.start} dur={dur} />
              </span>
              <span className="text-right font-mono text-[10px] text-muted-foreground tabular-nums">
                {s.end !== undefined ? fmtMs(s.end - s.start) : "..."}
              </span>
            </button>
            {open === s.id && <Inspector span={s} />}
          </li>
        ))}
      </ul>
    </div>
  );
}

function Bar({ span, traceStart, dur }: { span: Span; traceStart: number; dur: number }) {
  const left = ((span.start - traceStart) / dur) * 100;
  const width = span.end !== undefined ? ((span.end - span.start) / dur) * 100 : 100 - left;
  const color =
    span.status === "error"
      ? "bg-danger"
      : span.status === "miss"
        ? "bg-miss"
        : span.lane === "off"
          ? "hatch"
          : span.child
            ? "border border-(--mood) bg-(--mood)/15"
            : "bg-(--mood)";
  return (
    <span
      className={`absolute inset-y-0 min-w-[3px] rounded-sm ${color} ${span.status === "running" ? "animate-pulse" : ""}`}
      style={{ left: `${Math.max(0, Math.min(left, 99.5))}%`, width: `${Math.max(0, Math.min(width, 100 - left))}%` }}
    />
  );
}

function Inspector({ span }: { span: Span }) {
  const u = span.upstream;
  return (
    <div className="mx-1 mt-1 mb-2 grid gap-2 rounded-lg bg-muted/60 p-3 font-mono text-[11px]">
      <div className="flex flex-wrap gap-x-4 gap-y-1 text-muted-foreground">
        <span>lane: {span.lane === "hot" ? "critical path" : "off the hot path"}</span>
        <span>status: {span.status}</span>
        {span.detail && <span className="break-all">{span.detail}</span>}
      </div>
      {u ? (
        <>
          <div className="break-all">
            <span className="font-semibold">{u.method}</span> {u.url} <span className="text-muted-foreground">{u.status} · {u.ms}ms upstream</span>
          </div>
          {u.request !== undefined && <Json label="request body" value={u.request} />}
          {u.response !== undefined && <Json label="response" value={u.response} />}
          <p className="text-muted-foreground">API keys are sent as headers and never shown here.</p>
        </>
      ) : (
        <p className="text-muted-foreground">{span.child ? "Measured on the server." : "No upstream call: this step runs in the browser."}</p>
      )}
    </div>
  );
}

function Json({ label, value }: { label: string; value: unknown }) {
  const text = typeof value === "string" ? value : JSON.stringify(value, null, 2);
  return (
    <details open={label === "response"}>
      <summary className="cursor-pointer text-muted-foreground">{label}</summary>
      <pre className="mt-1 max-h-64 overflow-auto rounded-md bg-card p-2 whitespace-pre-wrap">{text.length > 4000 ? `${text.slice(0, 4000)}\n...` : text}</pre>
    </details>
  );
}
