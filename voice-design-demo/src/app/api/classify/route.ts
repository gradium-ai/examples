import { extractContext } from "@/lib/pipeline/context";
import { LANGUAGES, REGISTERS } from "@/lib/pipeline/questions";
import type { Language, Register } from "@/lib/pipeline/types";
import { errorResponse, jevCreds } from "@/lib/server/keys";

export async function POST(req: Request) {
  const body = await req.json().catch(() => null);
  const message = typeof body?.message === "string" ? body.message.trim().slice(0, 2000) : "";
  const language = LANGUAGES.includes(body?.language) ? (body.language as Language) : "en";
  const register = REGISTERS.includes(body?.register) ? (body.register as Register) : "formal";
  if (!message) return Response.json({ error: "Expected { message }" }, { status: 400 });

  const started = performance.now();
  try {
    const result = await extractContext(message, { language, register }, jevCreds(req), req.signal);
    return Response.json({ ...result, serverMs: Math.round(performance.now() - started) });
  } catch (err) {
    if (req.signal.aborted) return new Response(null, { status: 499 });
    return errorResponse(err);
  }
}
