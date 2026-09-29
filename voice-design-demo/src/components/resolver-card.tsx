"use client";

import { Check } from "lucide-react";
import { useState } from "react";
import type { useDesignQueue } from "@/hooks/use-pipeline";
import { ENERGIES, REGISTERS, TONES } from "@/lib/pipeline/questions";
import { distance, specKey, type Resolution } from "@/lib/pipeline/resolve";
import type { LibraryEntry, VoiceSpec } from "@/lib/pipeline/types";
import { DesignedVoice } from "./designed-voice";
import { StepLabel } from "./composer-card";

type Props = {
  spec: VoiceSpec;
  resolution: Resolution;
  library: Map<string, LibraryEntry>;
  queue: ReturnType<typeof useDesignQueue>;
  libraryState: { error?: string };
  hasGradium: boolean;
  onOpenKeys: () => void;
};

const COLS = REGISTERS.flatMap((register) => ENERGIES.map((energy) => ({ register, energy })));

export function ResolverCard({ spec, resolution, library, queue, libraryState, hasGradium, onOpenKeys }: Props) {
  const queuedKeys = new Map(queue.items.map((q) => [q.key, q.status]));
  const [picking, setPicking] = useState<string | null>(null);
  const pickItem = picking ? queue.items.find((i) => i.key === picking) : undefined;

  const pick = (key: string) => {
    if (!hasGradium) return onOpenKeys();
    const status = queuedKeys.get(key);
    if (status === "queued" || status === "error") queue.generate(key);
    setPicking(key);
  };

  return (
    <section className="grid grid-cols-1 gap-2">
      <StepLabel n="03" title="Resolve a voice without waiting for one" />
      <div className="card grid gap-4 p-5">
        <Verdict resolution={resolution} />

        <div className="overflow-x-auto">
          <table className="w-full min-w-[420px] border-separate border-spacing-1 text-xs">
            <thead>
              <tr>
                <th className="w-24" />
                {COLS.map((c) => (
                  <th key={`${c.register}${c.energy}`} className="pb-1 text-center font-normal text-muted-foreground">
                    <div className="font-mono text-[10px]">{c.register}</div>
                    <div>{c.energy}</div>
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {TONES.map((tone) => (
                <tr key={tone}>
                  <th className="pr-2 text-right font-normal text-muted-foreground">{tone}</th>
                  {COLS.map(({ register, energy }) => {
                    const cell: VoiceSpec = { language: spec.language, register, tone, energy };
                    const key = specKey(cell);
                    const entry = library.get(key);
                    const isCurrent = key === specKey(spec);
                    const isChosen = resolution.key === key;
                    const q = queuedKeys.get(key);
                    return (
                      <td key={key}>
                        <div
                          title={entry ? `${key}\nvoice_id ${entry.voiceId}` : q ? `${key}\n${q}` : `${key}\nno approved voice`}
                          className={[
                            "relative grid h-11 place-items-center rounded-lg border transition-colors duration-300",
                            entry ? "border-(--mood)/40 bg-(--mood)/12" : q ? "border-dashed border-miss bg-miss/5" : "border-dashed bg-muted/30",
                            isCurrent ? "ring-2 ring-(--mood) ring-offset-1 ring-offset-card" : "",
                          ].join(" ")}
                        >
                          {isChosen ? (
                            <Check className="size-4 text-(--mood-ink)" />
                          ) : entry ? (
                            <span className="font-mono text-[10px] text-muted-foreground">d={distance(entry.spec, spec)}</span>
                          ) : q && q !== "approved" ? (
                            <button
                              onClick={() => pick(key)}
                              className={`group absolute inset-0 grid place-items-center rounded-lg px-1 font-mono text-[10px] leading-tight text-miss hover:bg-miss/10 focus-visible:bg-miss/10 ${picking === key ? "bg-miss/10" : ""}`}
                            >
                              <span className="group-hover:hidden group-focus-visible:hidden">{q}</span>
                              <span className="hidden text-center group-hover:block group-focus-visible:block">Design voice</span>
                            </button>
                          ) : null}
                        </div>
                      </td>
                    );
                  })}
                </tr>
              ))}
            </tbody>
          </table>
        </div>
        <p className="text-xs text-muted-foreground">
          Click a queued cell to design a voice, then save it to your library for the next matching message.
        </p>

        {libraryState.error && <p className="text-sm text-danger">{libraryState.error}</p>}
      </div>
      {pickItem && <DesignedVoice item={pickItem} queue={queue} onClose={() => setPicking(null)} />}
    </section>
  );
}

function Verdict({ resolution }: { resolution: Resolution }) {
  const [title, body, tone] = resolution.exact
    ? ["Exact match", "An approved voice exists for this spec.", "text-(--mood-ink)"]
    : resolution.stock
      ? [
          "No approved voice yet",
          "Using the default voice and queuing up voice design from the specs.",
          "text-miss",
        ]
      : ["Nearest approved voice", `Closest match at distance ${resolution.distance}, from ${resolution.key}. The exact spec is queued for design.`, "text-miss"];
  return (
    <div className="flex flex-wrap items-start justify-between gap-3">
      <div className="min-w-0">
        <div className={`font-medium ${tone}`}>{title}</div>
        <p className="text-sm text-muted-foreground">{body}</p>
      </div>
      <div className="grid justify-items-end gap-0.5">
        <span className="font-mono text-[11px] text-muted-foreground">voice_id</span>
        <code className="rounded-md bg-muted px-2 py-0.5 font-mono text-xs">{resolution.voiceId}</code>
      </div>
    </div>
  );
}
