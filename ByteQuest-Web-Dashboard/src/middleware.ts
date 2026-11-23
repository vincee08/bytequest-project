import type { NextRequest } from "next/server";
import { gateRequest } from "@/lib/auth/session-gate";

export function middleware(request: NextRequest) {
  return gateRequest(request);
}

export const config = {
  matcher: [
    // API routes authenticate themselves. Skipping the no-op middleware also
    // avoids Next 15's 10 MB cloned-body truncation on 50 MB resource uploads.
    "/((?!api(?:/|$)|_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)",
  ],
};
