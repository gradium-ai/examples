"use client";

import { Check, Loader2, Play, X } from "lucide-react";
import type { DesignItem, useDesignQueue } from "@/hooks/use-pipeline";
import { fmtMs } from "@/lib/trace";

const STATUS: Record<DesignItem["status"], string> = {
  queued: "queued",
  generating: "generating candidates",
  waiting: "waiting until ready",
  ready: "ready to audition",
  converting: "converting",
  approved: "approved",
  error: "failed",
};

type Props = { item: DesignItem; queue: ReturnType<typeof useDesignQueue>; onClose: () => void };

// Voice Design off the hot path: generate, wait, audition, convert.
export function CandidatePicker({ item, queue, onClose }: Props) {
  const busy = ["generating", "waiting", "converting"].includes(item.status);
  return (
    <div className="card-off grid gap-3 p-5">
      <div className="flex flex-wrap items-center gap-2">
        <span className="text-sm font-medium">Candidates for</span>
        <code className="font-mono text-xs">{item.key}</code>
        <span className={`chip ${item.status === "approved" ? "border-emerald-500/50 text-emerald-700" : item.status === "error" ? "border-danger/50 text-danger" : ""}`}>
          {busy && <Loader2 className="size-3 animate-spin" />}
          {STATUS[item.status]}
          {item.status === "waiting" && ` · ${item.polls} polls`}
        </span>
        {item.waitedMs !== undefined && <span className="font-mono text-[11px] text-muted-foreground">ready in {fmtMs(item.waitedMs)}</span>}
        <button onClick={onClose} className="ml-auto text-muted-foreground hover:text-foreground" aria-label="Close candidate picker">
          <X className="size-4" />
        </button>
      </div>

      {item.status === "error" && (
        <button onClick={() => queue.generate(item.key)} className="btn pressable w-fit">
          Retry
        </button>
      )}

      {item.candidates.length > 0 && (
        <ul className="grid gap-1.5 sm:grid-cols-3">
          {item.candidates.map((c, i) => (
            <li key={c.id} className="grid gap-2 rounded-xl border bg-card px-3 py-2">
              <div className="flex items-center justify-between gap-2">
                <span className="text-xs font-medium">candidate {i + 1}</span>
                <span className={`size-1.5 rounded-full ${c.ready ? "bg-emerald-500" : "bg-neutral-300"}`} title={c.ready ? "ready" : "not ready"} />
              </div>
              <div className="flex gap-1.5">
                <button
                  onClick={() => (c.audio ? new Audio(c.audio).play() : queue.audition(item, c.id))}
                  disabled={!c.ready || c.auditioning || item.status === "approved"}
                  className="btn px-2.5 py-1 text-xs"
                >
                  {c.auditioning ? <Loader2 className="size-3 animate-spin" /> : <Play className="size-3" />} {c.audio ? "replay" : "audition"}
                </button>
                <button
                  onClick={() => queue.convert(item, c.id)}
                  disabled={!c.audio || item.status !== "ready"}
                  title={c.audio ? "Convert to a permanent voice. Uses one custom-voice slot." : "Audition first"}
                  className="btn px-2.5 py-1 text-xs"
                >
                  <Check className="size-3" /> approve
                </button>
              </div>
            </li>
          ))}
        </ul>
      )}
      {item.status === "ready" && <p className="text-xs text-muted-foreground">Approving converts the candidate into a permanent voice_id and uses one custom-voice slot.</p>}
      {item.status === "approved" && (
        <p className="text-xs text-muted-foreground">
          Added to the library as <code className="font-mono">{item.voiceId}</code>. The next turn with this spec resolves to it exactly.
        </p>
      )}
      {item.error && <p className="text-xs text-danger">{item.error}</p>}
    </div>
  );
}
