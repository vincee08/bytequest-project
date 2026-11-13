import "server-only";
import { createHmac, timingSafeEqual } from "node:crypto";
export const RECOVERY_COOKIE = "bq-password-recovery";
const ttl = 15 * 60;
export function recoveryProof(
  userId: string,
  sessionId: string,
  now = Date.now(),
) {
  const payload = Buffer.from(
    JSON.stringify({
      userId,
      sessionId,
      expires: Math.floor(now / 1000) + ttl,
    }),
  ).toString("base64url");
  return `${payload}.${signature(payload)}`;
}
function signature(payload: string) {
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key) throw Error("RECOVERY_NOT_CONFIGURED");
  return createHmac("sha256", key)
    .update("bytequest-password-recovery:v1:" + payload)
    .digest("base64url");
}
export function validRecoveryProof(
  proof: string | undefined,
  userId: string,
  sessionId: string,
  now = Date.now(),
) {
  try {
    const [payload, mac] = proof?.split(".") ?? [];
    if (!payload || !mac) return false;
    const expected = Buffer.from(signature(payload)),
      actual = Buffer.from(mac);
    if (actual.length !== expected.length || !timingSafeEqual(actual, expected))
      return false;
    const value = JSON.parse(
      Buffer.from(payload, "base64url").toString("utf8"),
    );
    return (
      value.userId === userId &&
      value.sessionId === sessionId &&
      value.expires > Math.floor(now / 1000) &&
      value.expires <= Math.floor(now / 1000) + ttl
    );
  } catch {
    return false;
  }
}
export function sessionId(accessToken: string) {
  // Used only after the Auth server has verified the token with getUser().
  const payload = JSON.parse(
    Buffer.from(accessToken.split(".")[1], "base64url").toString("utf8"),
  );
  if (typeof payload.session_id !== "string") throw Error("SESSION_REQUIRED");
  return payload.session_id as string;
}
