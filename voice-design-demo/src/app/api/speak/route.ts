import { speak } from "@/lib/pipeline/gradium";
import { errorResponse, gradiumKey, missingGradium } from "@/lib/server/keys";

export async function POST(req: Request) {
  const key = gradiumKey(req);
  if (!key) return missingGradium();
  const body = await req.json().catch(() => null);
  const text = typeof body?.text === "string" ? body.text.trim() : "";
  const voiceId = typeof body?.voiceId === "string" ? body.voiceId : "";
  if (!text || !voiceId) return Response.json({ error: "Expected { text, voiceId }" }, { status: 400 });
  // Candidates (vox_emb_*) are capped at 100 characters by the API.
  if (voiceId.startsWith("vox_emb_") && text.length > 100)
    return Response.json({ error: "Audition text is capped at 100 characters" }, { status: 400 });
  try {
    const { audio, ttfbMs, totalMs } = await speak(key, text, voiceId);
    return new Response(audio, {
      headers: {
        "content-type": "audio/wav",
        "x-upstream-ttfb-ms": String(ttfbMs),
        "x-upstream-ms": String(totalMs),
        "x-upstream-bytes": String(audio.byteLength),
      },
    });
  } catch (err) {
    return errorResponse(err);
  }
}
