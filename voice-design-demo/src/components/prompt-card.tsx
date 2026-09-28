"use client";

import { voicePromptParts } from "@/lib/pipeline/prompt";
import { specKey } from "@/lib/pipeline/resolve";
import type { VoiceSpec } from "@/lib/pipeline/types";
import { StepLabel } from "./composer-card";

const SOURCES = {
  persona: { label: "persona", note: "fixed per language", cls: "decoration-neutral-400" },
  tone: { label: "tone", note: "from Jev", cls: "decoration-(--mood)" },
  energy: { label: "energy", note: "from Jev", cls: "decoration-(--mood) decoration-dashed" },
  register: { label: "register", note: "from the product", cls: "decoration-sky-500" },
} as const;

export function PromptCard({ spec, prompt }: { spec: VoiceSpec; prompt: string }) {
  return (
    <section className="grid grid-cols-1 gap-2">
      <StepLabel n="02" title="Map signals to a voice description" />
      <div className="card grid gap-4 p-5">
        <p className="text-[15px] leading-8">
          {voicePromptParts(spec).map((part, i) =>
            part.source ? (
              <span key={i} title={`${SOURCES[part.source].label}: ${SOURCES[part.source].note}`} className={`underline decoration-2 underline-offset-[6px] ${SOURCES[part.source].cls}`}>
                {part.text}
              </span>
            ) : (
              <span key={i}>{part.text}</span>
            ),
          )}
        </p>
        <div className="flex flex-wrap items-center gap-x-4 gap-y-2 text-xs text-muted-foreground">
          {Object.values(SOURCES).map((s) => (
            <span key={s.label} className="flex items-center gap-1.5">
              <span className={`inline-block w-4 underline decoration-2 underline-offset-2 ${s.cls}`}>&nbsp;&nbsp;&nbsp;&nbsp;</span>
              {s.label} <span className="text-muted-foreground/70">({s.note})</span>
            </span>
          ))}
        </div>
        <div className="flex flex-wrap items-center gap-2 border-t pt-3 font-mono text-[11px] text-muted-foreground">
          <span className="chip font-mono text-foreground">{specKey(spec)}</span>
          <span className="tabular-nums">{prompt.length}/500 chars</span>
        </div>
      </div>
    </section>
  );
}
