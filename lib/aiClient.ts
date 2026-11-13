// lib/aiClient.ts — THE seam between the UI and the AI flow.
// Exactly one function calls the Convex action. Screens never import the
// Convex API directly for AI; they call runAiFlow with the bound action
// from useAction(). The action itself decides stub vs live (see
// convex/ai.ts): when no Supabase URL is configured in Convex, the
// action returns the canned 3-step answer through this SAME code path —
// same JSON shape, same screens, same counter increment — and marks it
// stubbed: true. The UI must render the STUBBED badge whenever
// stubbed is true and must never present a stubbed answer as live AI.

import type { FunctionArgs, FunctionReturnType } from 'convex/server';
import type { api } from '../convex/_generated/api';

export type AiStep = { title: string; detail: string };

export type AiResult = FunctionReturnType<typeof api.ai.runAi>;
export type RunAiArgs = FunctionArgs<typeof api.ai.runAi>;

export async function runAiFlow(
  runAi: (args: RunAiArgs) => Promise<AiResult>,
  input: RunAiArgs,
): Promise<AiResult> {
  return runAi(input);
}
