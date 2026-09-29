"use client";

import { motion } from "motion/react";
import type { useClassify } from "@/hooks/use-pipeline";
import { EXAMPLES } from "@/lib/content";
import { panel, row } from "@/lib/motion";
import { LANGUAGES, MIN_CONFIDENCE, QUESTIONS, REGISTERS } from "@/lib/pipeline/questions";
import type { Answer, Energy, Language, Register, Tone } from "@/lib/pipeline/types";
import { Segmented } from "./segmented";

type Props = {
  text: string;
  example: number | null;
  onExample: (i: number) => void;
  language: Language;
  onLanguage: (l: Language) => void;
  register: Register;
  onRegister: (r: Register) => void;
  classify: ReturnType<typeof useClassify>;
  overrides: { tone?: Tone; energy?: Energy };
  onOverride: (field: "tone" | "energy", value: string | undefined) => void;
  hasJev: boolean;
};

export function ComposerCard(p: Props) {
  const r = p.classify.result;
  return (
    <section className="grid grid-cols-1 gap-2">
      <StepLabel n="01" title="Extract context" />
      <div className="mood-ring overflow-hidden rounded-[28px] border bg-card">
        <div role="radiogroup" aria-label="Example message" className="flex flex-wrap gap-1.5 px-5 pt-4">
          {EXAMPLES.map((e, i) => {
            const on = i === p.example;
            return (
              <button
                key={e.label}
                role="radio"
                aria-checked={on}
                onClick={() => p.onExample(i)}
                className={`rounded-full border px-3 py-1 text-xs transition-colors ${on ? "border-(--mood)/60 bg-(--mood)/10 font-medium text-(--mood-ink)" : "text-muted-foreground hover:border-foreground/30 hover:text-foreground"}`}
              >
                {e.label}
              </button>
            );
          })}
        </div>
        <p aria-live="polite" className={`px-5 pt-3 pb-2 text-lg leading-relaxed sm:text-xl ${p.text ? "" : "text-muted-foreground"}`}>
          {p.text || "Pick an example message to start the demo."}
        </p>
        <div className="flex flex-wrap items-center gap-x-4 gap-y-2 px-5 pb-4">
          <Segmented label="language" options={LANGUAGES} value={p.language} onChange={p.onLanguage} />
          <Segmented label="register" options={REGISTERS} value={p.register} onChange={p.onRegister} />
          <span className="text-xs text-muted-foreground">known properties, passed in, not classified</span>
        </div>

        {r && (
          <motion.div variants={panel} initial="hidden" animate="shown" className="border-t">
            <div className="grid gap-5 px-5 pt-4 pb-5 sm:grid-cols-2">
              {(["tone", "energy"] as const).map((field) => (
                <motion.div key={field} variants={row}>
                  <Question
                    field={field}
                    answer={r.answers[field]}
                    override={p.overrides[field]}
                    onOverride={(v) => p.onOverride(field, v)}
                  />
                </motion.div>
              ))}
            </div>
            <motion.div variants={row} className="flex flex-wrap items-center gap-2 border-t bg-muted/40 px-5 py-2.5 font-mono text-[11px] text-muted-foreground">
              {r.source === "offline" ? (
                <span className="chip border-miss/50 bg-miss/10 text-foreground">offline keyword classifier: add a Jev key for the real model</span>
              ) : (
                <>
                  <span className="chip">{r.source === "openrouter" ? "OpenRouter" : "TypeSafe"} · {r.model}</span>
                  {r.inputTokens !== undefined && <span>{r.inputTokens} input tokens</span>}
                  {r.costUsd !== undefined && <span>${r.costUsd.toFixed(8)}</span>}
                </>
              )}
              <span className="ml-auto tabular-nums">server {r.serverMs}ms · round trip {Math.round(r.clientMs)}ms</span>
            </motion.div>
          </motion.div>
        )}
      </div>

      {p.classify.error && <p className="px-2 text-sm text-danger">{p.classify.error}</p>}

      {!p.hasJev && <p className="px-2 text-center text-xs text-muted-foreground">No Jev key yet: an offline keyword classifier stands in.</p>}
    </section>
  );
}

function Question({ field, answer, override, onOverride }: { field: "tone" | "energy"; answer: Answer; override?: string; onOverride: (v: string | undefined) => void }) {
  const q = QUESTIONS[field];
  const selected = override ?? answer.choice;
  return (
    <div className="grid gap-2">
      <div className="flex items-baseline justify-between gap-2">
        <span className="text-sm font-medium">{field}</span>
        <span className="font-mono text-[11px] text-muted-foreground tabular-nums" title={`Fallback to default below ${MIN_CONFIDENCE}`}>
          confidence {answer.confidence.toFixed(2)}
        </span>
      </div>
      <p className="-mt-1 text-xs text-muted-foreground">{q.instructions}</p>
      <div className="grid gap-1">
        {Object.keys(q.criteria).map((label) => {
          const prob = answer.probabilities[label] ?? 0;
          const isSel = label === selected;
          return (
            <button
              key={label}
              onClick={() => onOverride(label === answer.choice ? undefined : label)}
              title="Click to override the classifier"
              className={`group relative overflow-hidden rounded-lg border px-2.5 py-1.5 text-left text-sm transition-colors ${isSel ? "border-(--mood)/70" : "border-transparent hover:border-border"}`}
            >
              <span
                className="absolute inset-y-0 left-0 bg-(--mood)/15 transition-[width] duration-300 ease-(--ease-out)"
                style={{ width: `${Math.round(prob * 100)}%` }}
              />
              <span className="relative flex items-center justify-between gap-2">
                <span className={isSel ? "font-medium text-(--mood-ink)" : "text-muted-foreground"}>{label}</span>
                <span className="font-mono text-xs tabular-nums text-muted-foreground">{prob.toFixed(2)}</span>
              </span>
            </button>
          );
        })}
      </div>
      <div className="flex min-h-5 flex-wrap gap-1.5">
        {answer.fellBack && <span className="chip border-miss/50 bg-miss/10">low confidence: default used</span>}
        {override && (
          <button onClick={() => onOverride(undefined)} className="chip border-(--mood)/50 hover:bg-muted">
            manual override · reset
          </button>
        )}
      </div>
    </div>
  );
}

export function StepLabel({ n, title, off }: { n: string; title: string; off?: boolean }) {
  return (
    <div className="flex min-w-0 items-baseline gap-2 px-2">
      <span className={`font-mono text-xs ${off ? "text-muted-foreground" : "text-(--mood-ink)"}`}>{n}</span>
      <h2 className="shrink-0 text-sm font-medium">{title}</h2>
    </div>
  );
}
