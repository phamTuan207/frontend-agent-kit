// types/globals.d.ts — the only ambient declarations this project needs.
// The Expo base tsconfig sets lib ["DOM", "ESNext"], so fetch,
// Response, Request, AbortSignal and crypto already come from lib.dom —
// do NOT redeclare them here (that would be a duplicate identifier).
// What lib.dom does NOT provide:
//   1. Deno — used only by supabase/functions/ai/index.ts.
//   2. The EXPO_PUBLIC_CONVEX_URL key on process.env — expo/types
//      (referenced by the generated expo-env.d.ts) declares process.env
//      itself; this interface MERGES with it (interfaces merge, so
//      there is no duplicate) and documents the one key the app reads.

declare namespace Deno {
  const env: { get(key: string): string | undefined };
  function serve(
    handler: (
      req: EdgeFunctionRequest,
    ) => Response | Promise<Response>,
  ): void;
}

// Minimal shape of the incoming edge-function request. The real Deno
// Request is structurally assignable to this (it has .json() and
// .headers.get()); the handler only uses these two members.
interface EdgeFunctionRequest {
  readonly method: string;
  json(): Promise<unknown>;
  readonly headers: { get(name: string): string | null };
}

declare namespace NodeJS {
  interface ProcessEnv {
    EXPO_PUBLIC_CONVEX_URL?: string;
  }
}
