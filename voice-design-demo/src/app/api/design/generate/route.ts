import { generateCandidates } from "@/lib/pipeline/gradium";
import { parseSpecKey } from "@/lib/pipeline/resolve";
import { errorResponse, gradiumKey, missingGradium } from "@/lib/server/keys";

export async function POST(req: Request) {
  const key = gradiumKey(req);
  if (!key) return missingGradium();
  const body = await req.json().catch(() => null);
  const spec = parseSpecKey(String(body?.key ?? ""));
  if (!spec) return Response.json({ error: "Expected { key: specKey }" }, { status: 400 });
  try {
    return Response.json(await generateCandidates(key, spec, 1));
  } catch (err) {
    return errorResponse(err);
  }
}
