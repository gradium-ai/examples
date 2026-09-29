"use client";

import { KeyRound } from "lucide-react";
import { AnimatePresence, MotionConfig, motion } from "motion/react";
import { EASE_OUT } from "@/lib/motion";
import { useEffect, useMemo, useRef, useState } from "react";
import { useKeys } from "@/hooks/use-keys";
import { EXAMPLES } from "@/lib/content";
import { useClassify, useLibrary, useVoiceSpeech } from "@/hooks/use-pipeline";
import { specKey } from "@/lib/pipeline/resolve";
import { mapAndResolve } from "@/lib/pipeline/turn";
import type { Energy, Language, Register, Tone, VoiceSpec } from "@/lib/pipeline/types";
import { beginTrace, handleFor } from "@/lib/trace";
import { ComposerCard } from "./composer-card";
import { KeysDialog } from "./keys-dialog";
import { LatencyHud } from "./latency-hud";
import { PromptCard } from "./prompt-card";
import { SpeakCard } from "./speak-card";
import { TracePanel } from "./trace-panel";

export function Demo() {
  const k = useKeys();
  const [keysOpen, setKeysOpen] = useState(false);
  const [example, setExample] = useState<number | null>(null);
  const [language, setLanguage] = useState<Language>("en");
  const [register, setRegister] = useState<Register>("formal");
  // The message follows the picked example in the current language and register.
  const text = example === null ? "" : EXAMPLES[example].text[language][register];
  const [overrides, setOverrides] = useState<{ tone?: Tone; energy?: Energy }>({});

  const classify = useClassify(text, language, register, k.headers);
  const lib = useLibrary(k.headers, k.hasGradium);
  const speech = useVoiceSpeech(k.headers, lib.refresh);
  const result = classify.result;

  // A new message clears manual overrides.
  const lastTrace = result?.traceId;
  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- reset per turn
    setOverrides({});
  }, [lastTrace]);

  const spec: VoiceSpec | null = result
    ? {
        language,
        register,
        tone: overrides.tone ?? (result.answers.tone.choice as Tone),
        energy: overrides.energy ?? (result.answers.energy.choice as Energy),
      }
    : null;
  const key = spec ? specKey(spec) : null;

  // Steps 2 and 3 run in the browser: pure functions, timed to the microsecond.
  const computed = useMemo(
    () => (spec ? mapAndResolve(spec, lib.library) : null),
    // eslint-disable-next-line react-hooks/exhaustive-deps -- spec is keyed by `key`
    [key, lib.library],
  );

  // Record mapping and the library lookup for this turn.
  const resolvedFor = useRef<string | null>(null);
  useEffect(() => {
    if (!computed || !result) return;
    const fresh = resolvedFor.current !== result.traceId;
    resolvedFor.current = result.traceId;
    const trace = fresh ? handleFor(result.traceId) : beginTrace("turn", "re-resolve (context changed)");
    const { t0, mapMs, resolveMs, resolution, prompt } = computed;
    trace.record({ name: "map signals to voice prompt", lane: "hot", start: t0, end: t0 + mapMs, status: "ok", detail: `${prompt.length}/500 chars` });
    trace.record({
      name: "resolve voice",
      lane: "hot",
      start: t0 + mapMs,
      end: t0 + mapMs + resolveMs,
      status: resolution.exact ? "ok" : "miss",
      detail: resolution.exact ? "exact match" : resolution.stock ? "voice will be generated when Speak is clicked" : `nearest, distance ${resolution.distance}`,
    });

  }, [computed, result]);

  return (
    <MotionConfig reducedMotion="user">
      <main data-mood={spec?.tone ?? "idle"} className="flex min-h-dvh flex-col items-center px-4 pt-10 pb-24 sm:pt-16">
        <header className="mb-8 grid w-full max-w-3xl gap-6">
          <div className="flex items-start justify-between gap-4">
            <div>
              <h1 className="text-2xl font-semibold tracking-tight">Demo: Giving voice agents a voice that adapts to context</h1>
            </div>
            <button onClick={() => setKeysOpen(true)} className="btn pressable shrink-0">
              <KeyRound className="size-4" /> Keys
              <span className="flex gap-1 pl-1">
                <Dot on={k.hasJev} label="Jev" />
                <Dot on={k.hasGradium} label="Gradium" />
              </span>
            </button>
          </div>
        </header>

        <div className="grid w-full max-w-3xl grid-cols-1">
          <Reveal step={0}>
            <ComposerCard
              text={text}
              example={example}
              onExample={setExample}
              language={language}
              onLanguage={setLanguage}
              register={register}
              onRegister={setRegister}
              classify={classify}
              overrides={overrides}
              onOverride={(field, value) => setOverrides((o) => ({ ...o, [field]: value }))}
              hasJev={k.hasJev}
            />
          </Reveal>
          <AnimatePresence>
            {computed && (
              <Reveal key="map" step={1}>
                <PromptCard spec={computed.spec} prompt={computed.prompt} />
              </Reveal>
            )}
            {computed && (
              <Reveal key="speak" step={2}>
                <SpeakCard spec={computed.spec} resolution={computed.resolution} speech={speech} hasGradium={k.hasGradium} />
              </Reveal>
            )}
          </AnimatePresence>
          <div className="pt-5">
            <TracePanel />
          </div>
        </div>

        <LatencyHud classify={classify} computed={computed} speech={speech} />
        <KeysDialog open={keysOpen} onClose={() => setKeysOpen(false)} keys={k.keys} env={k.env} onSave={k.setKeys} />
      </main>
    </MotionConfig>
  );
}

function Dot({ on, label }: { on: boolean; label: string }) {
  return <span title={`${label}: ${on ? "key set" : "no key"}`} className={`size-1.5 rounded-full ${on ? "bg-emerald-500" : "bg-neutral-300"}`} />;
}

// Steps reveal top-down: 01 on load, then 02, 03, 04 once the first example is classified,
// each after a pause. Height grows from 0 so everything below slides down instead of jumping.
const REVEAL = 0.8;
const PAUSE = 1.5;

function Reveal({ step, children }: { step: number; children: React.ReactNode }) {
  if (step === 0)
    return (
      <motion.div initial={{ opacity: 0, y: -12 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.8, ease: EASE_OUT }}>
        {children}
      </motion.div>
    );
  return (
    <motion.div
      initial={{ opacity: 0, height: 0, overflow: "hidden" }}
      animate={{ opacity: 1, height: "auto", transitionEnd: { overflow: "visible" } }}
      exit={{ opacity: 0, height: 0, overflow: "hidden", transition: { duration: 0.3, ease: EASE_OUT } }}
      transition={{ duration: REVEAL, ease: EASE_OUT, delay: step * PAUSE + (step - 1) * REVEAL }}
    >
      <div className="pt-5">{children}</div>
    </motion.div>
  );
}
