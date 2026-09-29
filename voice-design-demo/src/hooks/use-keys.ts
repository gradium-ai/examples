"use client";

import { useCallback, useEffect, useMemo, useState } from "react";

export type Keys = { provider: "openrouter" | "typesafe"; openrouter: string; typesafe: string; gradium: string };
export type EnvKeys = { openrouter: boolean; typesafe: boolean; gradium: boolean };

const STORAGE = "voice-design-demo.keys";
const LEGACY_STORAGE = "overtone.keys";
const EMPTY: Keys = { provider: "openrouter", openrouter: "", typesafe: "", gradium: "" };

function load(): Keys {
  try {
    return { ...EMPTY, ...JSON.parse(localStorage.getItem(STORAGE) ?? localStorage.getItem(LEGACY_STORAGE) ?? "{}") };
  } catch {
    return EMPTY;
  }
}

export function useKeys() {
  const [keys, setKeysState] = useState<Keys>(EMPTY);
  const [env, setEnv] = useState<EnvKeys>({ openrouter: false, typesafe: false, gradium: false });

  useEffect(() => {
    // eslint-disable-next-line react-hooks/set-state-in-effect -- hydrate from storage after mount
    setKeysState(load());
    fetch("/api/health")
      .then((r) => r.json())
      .then((j) => setEnv(j.env))
      .catch(() => {});
  }, []);

  const setKeys = useCallback((next: Keys) => {
    setKeysState(next);
    try {
      localStorage.setItem(STORAGE, JSON.stringify(next));
    } catch {}
  }, []);

  const headers = useMemo(() => {
    const h: Record<string, string> = { "content-type": "application/json", "x-jev-provider": keys.provider };
    if (keys.openrouter) h["x-openrouter-key"] = keys.openrouter;
    if (keys.typesafe) h["x-typesafe-key"] = keys.typesafe;
    if (keys.gradium) h["x-gradium-key"] = keys.gradium;
    return h;
  }, [keys]);

  const hasJev = Boolean(keys.openrouter || keys.typesafe || env.openrouter || env.typesafe);
  const hasGradium = Boolean(keys.gradium || env.gradium);

  return { keys, setKeys, env, headers, hasJev, hasGradium };
}
