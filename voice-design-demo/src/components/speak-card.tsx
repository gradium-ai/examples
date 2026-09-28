"use client";

import { Loader2, Volume2 } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import type { useSpeak } from "@/hooks/use-pipeline";
import { REPLIES } from "@/lib/content";
import type { Resolution } from "@/lib/pipeline/resolve";
import type { VoiceSpec } from "@/lib/pipeline/types";
import { StepLabel } from "./composer-card";

type Props = { spec: VoiceSpec; resolution: Resolution; speech: ReturnType<typeof useSpeak>; hasGradium: boolean };

export function SpeakCard({ spec, resolution, speech, hasGradium }: Props) {
  const suggested = REPLIES[spec.language][spec.tone];
  const [reply, setReply] = useState(suggested);
  const [edited, setEdited] = useState(false);
  const audio = useRef<HTMLAudioElement>(null);

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- follow the suggestion until the user edits
    if (!edited) setReply(suggested);
  }, [suggested, edited]);

  useEffect(() => {
    if (speech.last && audio.current) audio.current.play().catch(() => {});
  }, [speech.last]);

  const last = speech.last;
  return (
    <section className="grid grid-cols-1 gap-2">
      <StepLabel n="04" title="Speak" />
      <div className="card grid gap-3 p-5">
        <textarea
          rows={2}
          value={reply}
          onChange={(e) => {
            setReply(e.target.value);
            setEdited(true);
          }}
          aria-label="Agent reply"
          className="w-full resize-none rounded-xl border bg-muted/30 px-3 py-2 text-sm leading-relaxed outline-none focus:border-(--mood)/60"
        />
        <div className="flex flex-wrap items-center gap-3">
          <button
            onClick={() => speech.speak(reply, resolution.voiceId)}
            disabled={!hasGradium || speech.pending || !reply.trim()}
            className="btn btn-primary pressable"
          >
            {speech.pending ? <Loader2 className="size-4 animate-spin" /> : <Volume2 className="size-4" />}
            Speak with {resolution.exact ? "approved" : resolution.stock ? "stock" : "nearest"} voice
          </button>
          {edited && (
            <button onClick={() => setEdited(false)} className="text-xs text-muted-foreground underline decoration-dotted underline-offset-4 hover:text-foreground">
              reset reply
            </button>
          )}
          {!hasGradium && <span className="text-xs text-muted-foreground">Add a Gradium key to synthesize.</span>}
        </div>
        {speech.error && <p className="text-sm text-danger">{speech.error}</p>}
        {last && (
          <div className="grid gap-2 border-t pt-3">
            <audio ref={audio} src={last.url} controls className="h-9 w-full" />
            <p className="text-xs text-muted-foreground">
              REST returns the whole file. A live agent would stream over the WebSocket endpoint with the same voice_id.
            </p>
          </div>
        )}
      </div>
    </section>
  );
}
