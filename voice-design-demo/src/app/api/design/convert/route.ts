import { convert } from "@/lib/pipeline/gradium";
import { parseSpecKey } from "@/lib/pipeline/resolve";
import { errorResponse, gradiumKey, missingGradium } from "@/lib/server/keys";

export async function POST(req: Request) {
  const key = gradiumKey(req);
  if (!key) return missingGradium();
  const body = await req.json().catch(() => null);
  const spec = parseSpecKey(String(body?.key ?? ""));
  const candidateId = String(body?.candidateId ?? "");
  if (!spec || !candidateId) return Response.json({ error: "Expected { key, candidateId }" }, { status: 400 });
  try {
    return Response.json(await convert(key, candidateId, spec));
  } catch (err) {
    return errorResponse(err);
  }
}
