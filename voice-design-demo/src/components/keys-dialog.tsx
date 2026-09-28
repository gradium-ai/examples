"use client";

import { Eye, EyeOff, X } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import type { EnvKeys, Keys } from "@/hooks/use-keys";
import { Segmented } from "./segmented";

type Props = { open: boolean; onClose: () => void; keys: Keys; env: EnvKeys; onSave: (k: Keys) => void };

export function KeysDialog({ open, onClose, keys, env, onSave }: Props) {
  const ref = useRef<HTMLDialogElement>(null);
  const [draft, setDraft] = useState(keys);

  useEffect(() => {
    const d = ref.current;
    if (!d) return;
    if (open && !d.open) {
      setDraft(keys);
      d.showModal();
    }
    if (!open && d.open) d.close();
  }, [open, keys]);

  const set = (field: keyof Keys) => (v: string) => setDraft((d) => ({ ...d, [field]: v }));

  return (
    <dialog
      ref={ref}
      onClose={onClose}
      onClick={(e) => e.target === ref.current && onClose()}
      className="m-auto w-[min(32rem,calc(100vw-2rem))] rounded-3xl border bg-card p-0 text-foreground shadow-2xl backdrop:bg-black/20 backdrop:backdrop-blur-[2px]"
    >
      <form
        method="dialog"
        onSubmit={() => {
          onSave(draft);
          onClose();
        }}
        className="grid gap-5 p-6"
      >
        <div className="flex items-start justify-between">
          <div>
            <h2 className="text-lg font-semibold">API keys</h2>
            <p className="mt-1 text-sm text-muted-foreground">
              Stored in this browser only. Sent as headers to this app&apos;s own server routes, which forward them to the API and never log them.
            </p>
          </div>
          <button type="button" onClick={onClose} aria-label="Close" className="text-muted-foreground hover:text-foreground">
            <X className="size-5" />
          </button>
        </div>

        <fieldset className="grid gap-3">
          <div className="flex items-center justify-between">
            <legend className="text-sm font-medium">Jev</legend>
            <Segmented label="call through" options={["openrouter", "typesafe"] as const} value={draft.provider} onChange={set("provider")} />
          </div>
          <KeyField label="OpenRouter API key" value={draft.openrouter} onChange={set("openrouter")} envSet={env.openrouter} placeholder="sk-or-v1-..." hint="model typesafe/jev-1.13" />
          <KeyField label="TypeSafe API key" value={draft.typesafe} onChange={set("typesafe")} envSet={env.typesafe} placeholder="ts-..." hint="model jev-latest" />
        </fieldset>

        <fieldset className="grid gap-3">
          <legend className="text-sm font-medium">Gradium</legend>
          <KeyField label="Gradium API key" value={draft.gradium} onChange={set("gradium")} envSet={env.gradium} placeholder="gd-..." hint="TTS and Voice Design" />
        </fieldset>

        <div className="flex items-center justify-between gap-2">
          <button type="button" onClick={() => setDraft({ ...draft, openrouter: "", typesafe: "", gradium: "" })} className="text-xs text-muted-foreground underline decoration-dotted underline-offset-4 hover:text-foreground">
            clear all
          </button>
          <div className="flex gap-2">
            <button type="button" onClick={onClose} className="btn">
              Cancel
            </button>
            <button type="submit" className="btn btn-primary pressable">
              Save
            </button>
          </div>
        </div>
      </form>
    </dialog>
  );
}

function KeyField({ label, value, onChange, envSet, placeholder, hint }: { label: string; value: string; onChange: (v: string) => void; envSet: boolean; placeholder: string; hint: string }) {
  const [show, setShow] = useState(false);
  return (
    <label className="grid gap-1.5">
      <span className="flex items-baseline justify-between text-xs">
        <span>{label}</span>
        <span className="font-mono text-[10px] text-muted-foreground">{envSet && !value ? "using server env" : hint}</span>
      </span>
      <span className="flex items-center rounded-xl border bg-muted/30 focus-within:border-(--mood)/60">
        <input
          type={show ? "text" : "password"}
          value={value}
          onChange={(e) => onChange(e.target.value.trim())}
          placeholder={envSet ? "set on the server, paste to override" : placeholder}
          autoComplete="off"
          spellCheck={false}
          className="min-w-0 flex-1 bg-transparent px-3 py-2 font-mono text-xs outline-none"
        />
        <button type="button" onClick={() => setShow((s) => !s)} className="px-3 text-muted-foreground hover:text-foreground" aria-label={show ? "Hide key" : "Show key"}>
          {show ? <EyeOff className="size-4" /> : <Eye className="size-4" />}
        </button>
      </span>
    </label>
  );
}
