import { createClient, type Client } from "rivetkit/client";
import type { Registry } from "./registry";

/** Bearer + refresh token pair the mac app stashes in keychain. */
export type StackBearer = { accessToken: string; refreshToken: string };

/**
 * Authoritative base URL for the Rivet gateway. On Vercel we trust VERCEL_URL (deployment
 * only, set by the platform). Local dev reads `CMUX_VM_API_BASE_URL` or falls back to
 * `http://localhost:3000`. Deriving this from `request.url.origin` is unsafe — a misconfigured
 * reverse proxy could rewrite Host and redirect Stack Auth tokens to an attacker-controlled
 * endpoint.
 */
function rivetBaseURL(): string {
  const explicit = process.env.CMUX_VM_API_BASE_URL?.trim();
  if (explicit) return explicit.replace(/\/$/, "");
  const vercel = process.env.VERCEL_URL?.trim();
  if (vercel) return `https://${vercel}`;
  return "http://localhost:3000";
}

export function parseBearer(request: Request): StackBearer | null {
  const auth = request.headers.get("authorization");
  const refresh = request.headers.get("x-stack-refresh-token");
  if (!auth?.toLowerCase().startsWith("bearer ") || !refresh) return null;
  const accessToken = auth.slice("bearer ".length).trim();
  const refreshToken = refresh.trim();
  if (!accessToken || !refreshToken) return null;
  return { accessToken, refreshToken };
}

export function rivetClient(bearer: StackBearer): Client<Registry> {
  return createClient<Registry>({
    endpoint: `${rivetBaseURL()}/api/rivet`,
    headers: {
      authorization: `Bearer ${bearer.accessToken}`,
      "x-stack-refresh-token": bearer.refreshToken,
    },
  });
}

/**
 * Confirms this user owns `vmId` before any mutation (destroy, exec, openSSH, snapshot).
 * Prevents IDOR: without this, any authenticated user could DELETE/exec/ssh anyone else's
 * VM by passing the raw provider id to the route. Checks against the coordinator actor's
 * own list rather than asking the vmActor directly (the vmActor would happily getOrCreate a
 * brand-new shell actor for an id it's never seen).
 */
export async function userOwnsVm(
  client: Client<Registry>,
  userId: string,
  vmId: string,
): Promise<boolean> {
  const list = await client.userVmsActor.getOrCreate([userId]).list();
  return list.some((v) => v.providerVmId === vmId);
}

/**
 * `Response.json(...)` misbehaves under Next.js 16's turbopack dev build (the handler's
 * promise settles but turbopack reports "No response is returned from route handler").
 * Use `new Response(JSON.stringify(...), { ... })` explicitly instead.
 */
export function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "content-type": "application/json" },
  });
}

export function notFoundVm(vmId: string): Response {
  return jsonResponse({ error: `vm not found: ${vmId}` }, 404);
}
