"use client";

import type { useClassify, useSpeak } from "@/hooks/use-pipeline";
import { fmtMs } from "@/lib/trace";
import type { Computed } from "./pipeline-strip";

type Props = { classify: ReturnType<typeof useClassify>; computed: Computed; speech: ReturnType<typeof useSpeak> };

export function LatencyHud({ classify, computed, speech }: Props) {
  const r = classify.result;
  const parts = [
    classify.pending ? "reading..." : r ? `jev ${fmtMs(r.clientMs)}` : null,
    computed ? `map ${fmtMs(computed.mapMs)}` : null,
    computed ? `resolve ${fmtMs(computed.resolveMs)}` : null,
    speech.pending ? "speaking..." : speech.last ? `tts ${fmtMs(speech.last.ttfbMs)} 1st byte` : null,
  ].filter(Boolean);
  if (!parts.length) return null;
  return (
    <p className="fixed right-4 bottom-4 hidden rounded-full border bg-card/90 px-3 py-1 font-mono text-xs text-muted-foreground tabular-nums shadow-sm backdrop-blur sm:block" aria-live="polite">
      {parts.join(" · ")}
    </p>
  );
}
