import { CHAINHOOKS_BASE_URL, ChainhooksClient } from "@hirosystems/chainhooks-client";

export async function GET() {
  const baseUrl = process.env.NEXT_PUBLIC_CHAINHOOKS_API_URL ?? CHAINHOOKS_BASE_URL.testnet;
  const client = new ChainhooksClient({ baseUrl });

  try {
    await client.getStatus();
    return Response.json({ ok: true, baseUrl });
  } catch (error) {
    return Response.json({ ok: false, baseUrl }, { status: 503 });
  }
}
