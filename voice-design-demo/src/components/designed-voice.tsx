"use client";

import { Check, Loader2, X } from "lucide-react";
import type { DesignItem, useDesignQueue } from "@/hooks/use-pipeline";
import { fmtMs } from "@/lib/trace";

const STATUS: Record<DesignItem["status"], string> = {
  queued: "queued",
  generating: "generating voice",
  waiting: "waiting until ready",
  ready: "ready to save",
  converting: "converting",
  approved: "approved",
  error: "failed",
};

type Props = { item: DesignItem; queue: ReturnType<typeof useDesignQueue>; onClose: () => void };

// Voice Design off the hot path: generate, wait, convert.
export function DesignedVoice({ item, queue, onClose }: Props) {
  const busy = ["generating", "waiting", "converting"].includes(item.status);
  return (
    <div className="card-off grid gap-3 p-5">
      <div className="flex flex-wrap items-center gap-2">
        <span className="text-sm font-medium">Voice for</span>
        <code className="font-mono text-xs">{item.key}</code>
        <span className={`chip ${item.status === "approved" ? "border-emerald-500/50 text-emerald-700" : item.status === "error" ? "border-danger/50 text-danger" : ""}`}>
          {busy && <Loader2 className="size-3 animate-spin" />}
          {STATUS[item.status]}
          {item.status === "waiting" && ` · ${item.polls} polls`}
        </span>
        {item.waitedMs !== undefined && <span className="font-mono text-[11px] text-muted-foreground">ready in {fmtMs(item.waitedMs)}</span>}
        <button onClick={onClose} className="ml-auto text-muted-foreground hover:text-foreground" aria-label="Close voice design">
          <X className="size-4" />
        </button>
      </div>

      {item.status === "error" && (
        <button onClick={() => queue.generate(item.key)} className="btn pressable w-fit">
          Retry
        </button>
      )}

      {item.status === "ready" && (
        <div className="grid gap-2">
          <button onClick={() => queue.convert(item)} className="btn pressable w-fit">
            <Check className="size-3" /> Save voice
          </button>
          <p className="text-xs text-muted-foreground">Save this voice to your library. Uses one custom-voice slot.</p>
        </div>
      )}
      {item.status === "approved" && (
        <p className="text-xs text-muted-foreground">
          Added to the library as <code className="font-mono">{item.voiceId}</code>. The next turn with this spec resolves to it exactly.
        </p>
      )}
      {item.error && <p className="text-xs text-danger">{item.error}</p>}
    </div>
  );
}
