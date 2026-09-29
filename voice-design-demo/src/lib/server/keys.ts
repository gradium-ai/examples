import "server-only";
import type { JevCreds } from "@/lib/pipeline/context";
import { UpstreamError } from "@/lib/pipeline/gradium";

// Keys typed in the UI arrive as headers on same-origin requests; the server
// forwards them upstream and never logs or stores them. Env vars are the fallback.
const pick = (req: Request, header: string, env: string) =>
  req.headers.get(header)?.trim() || process.env[env]?.trim() || "";

export function jevCreds(req: Request): JevCreds | null {
  const preferred = req.headers.get("x-jev-provider") === "typesafe" ? "typesafe" : "openrouter";
  const keys = {
    openrouter: pick(req, "x-openrouter-key", "OPENROUTER_API_KEY"),
    typesafe: pick(req, "x-typesafe-key", "TYPESAFE_API_KEY"),
  };
  if (keys[preferred]) return { provider: preferred, key: keys[preferred] };
  const other = preferred === "openrouter" ? "typesafe" : "openrouter";
  return keys[other] ? { provider: other, key: keys[other] } : null;
}

export const gradiumKey = (req: Request) => pick(req, "x-gradium-key", "GRADIUM_API_KEY");

export const envKeys = () => ({
  openrouter: Boolean(process.env.OPENROUTER_API_KEY?.trim()),
  typesafe: Boolean(process.env.TYPESAFE_API_KEY?.trim()),
  gradium: Boolean(process.env.GRADIUM_API_KEY?.trim()),
});

export function errorResponse(err: unknown) {
  const upstream = err instanceof UpstreamError ? err.upstream : (err as { upstream?: unknown })?.upstream;
  const message = err instanceof Error ? err.message : String(err);
  return Response.json({ error: message, upstream }, { status: 502 });
}

export const missingGradium = () =>
  Response.json({ error: "No Gradium API key. Add one in Keys or set GRADIUM_API_KEY." }, { status: 401 });
