import { listLibrary } from "@/lib/pipeline/gradium";
import { errorResponse, gradiumKey, missingGradium } from "@/lib/server/keys";

export async function GET(req: Request) {
  const key = gradiumKey(req);
  if (!key) return missingGradium();
  try {
    return Response.json(await listLibrary(key));
  } catch (err) {
    return errorResponse(err);
  }
}
