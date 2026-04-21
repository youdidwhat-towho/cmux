import { unauthorized, verifyRequest } from "../../../../../services/vms/auth";
import {
  jsonResponse,
  notFoundVm,
  parseBearer,
  rivetClient,
  userOwnsVm,
} from "../../../../../services/vms/routeHelpers";

export const dynamic = "force-dynamic";

export async function POST(
  request: Request,
  { params }: { params: Promise<{ id: string }> },
): Promise<Response> {
  try {
    const user = await verifyRequest(request);
    if (!user) return unauthorized();
    const bearer = parseBearer(request);
    if (!bearer) return unauthorized();

    const body = (await request.json().catch(() => ({}))) as {
      command?: string;
      timeoutMs?: number;
    };
    if (!body.command) return jsonResponse({ error: "command is required" }, 400);

    const { id } = await params;
    const client = rivetClient(bearer);
    if (!(await userOwnsVm(client, user.id, id))) return notFoundVm(id);
    const result = await client.vmActor
      .getOrCreate([id])
      .exec(body.command, body.timeoutMs ?? 30_000);
    return jsonResponse(result);
  } catch (err) {
    console.error("/api/vm/[id]/exec POST failed", err);
    return jsonResponse(
      { error: err instanceof Error ? `${err.name}: ${err.message}` : String(err) },
      500,
    );
  }
}
