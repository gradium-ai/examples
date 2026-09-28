"use client";

export function Segmented<T extends string>({ label, options, value, onChange }: { label: string; options: readonly T[]; value: T; onChange: (v: T) => void }) {
  return (
    <div role="radiogroup" aria-label={label} className="flex items-center gap-2">
      <span className="font-mono text-[11px] text-muted-foreground">{label}</span>
      <div className="flex rounded-full border bg-muted/50 p-0.5">
        {options.map((o) => (
          <button
            key={o}
            role="radio"
            aria-checked={o === value}
            onClick={() => onChange(o)}
            className={`rounded-full px-2.5 py-0.5 text-xs transition-colors ${o === value ? "bg-card font-medium shadow-sm" : "text-muted-foreground hover:text-foreground"}`}
          >
            {o}
          </button>
        ))}
      </div>
    </div>
  );
}
