import { isReady } from "@/lib/pipeline/gradium";
import { errorResponse, gradiumKey, missingGradium } from "@/lib/server/keys";

export async function GET(req: Request) {
  const key = gradiumKey(req);
  if (!key) return missingGradium();
  const id = new URL(req.url).searchParams.get("id");
  if (!id) return Response.json({ error: "Expected ?id=" }, { status: 400 });
  try {
    return Response.json(await isReady(key, id));
  } catch (err) {
    return errorResponse(err);
  }
}
