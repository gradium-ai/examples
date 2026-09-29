import { envKeys } from "@/lib/server/keys";

export const GET = () => Response.json({ env: envKeys() });
