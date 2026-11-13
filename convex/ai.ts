// convex/ai.ts — the ONE AI entry point. "use node" action.
// DATA LAYER ONLY for Convex: this action never calls a model directly
// and never holds the Gemini key. It POSTs to the Supabase Edge
// Function (supabase/functions/ai), which owns the key. If the Edge
// Function is not configured yet (no SUPABASE_URL in the Convex
// dashboard), the action returns the canned 3-step answer through this
// SAME code path — same JSON shape, same persistence, same counter —
// and marks it stubbed: true. The UI labels stubbed answers STUBBED.
//
// Errors are ALWAYS ConvexError with a code — never a plain Error:
// plain errors lose their code on the client and the UI cannot tell a
// bad input from an upstream outage.
'use node';

import { ConvexError, v } from 'convex/values';
import { action } from './_generated/server';
import { api, internal } from './_generated/api';
import type { Id } from './_generated/dataModel';

const MAX_PROMPT_CHARS = 4000;
const UPSTREAM_TIMEOUT_MS = 25000;
const MAX_TOKENS = 800;

type AiStep = { title: string; detail: string };

// Canned 3-step answer for stub mode. Same shape as the live answer.
const STUB_STEPS: AiStep[] = [
  {
    title: 'Step 1 — Understand the request',
    detail:
      'This is a stubbed answer: no AI key is configured yet, so the flow returns a canned 3-step plan instead of calling a model.',
  },
  {
    title: 'Step 2 — Draft the plan',
    detail:
      'Set the Supabase URL and Gemini secret tonight (see README), then the same button returns a live answer through this same code path.',
  },
  {
    title: 'Step 3 — Ship it',
    detail:
      'The run is already persisted and counted, and the share link below already works — stub mode exercises the whole flow end to end.',
  },
];

function fail(code: string, message: string): never {
  throw new ConvexError({ code, message });
}

function parseSteps(value: unknown): AiStep[] {
  if (typeof value !== 'object' || value === null) {
    fail('AI_BAD_RESPONSE', 'AI endpoint returned a non-object payload.');
  }
  const steps = (value as { steps?: unknown }).steps;
  if (!Array.isArray(steps) || steps.length === 0) {
    fail('AI_BAD_RESPONSE', 'AI endpoint returned no steps array.');
  }
  const parsed: AiStep[] = [];
  for (const s of steps) {
    if (
      typeof s !== 'object' ||
      s === null ||
      typeof (s as { title?: unknown }).title !== 'string' ||
      typeof (s as { detail?: unknown }).detail !== 'string'
    ) {
      fail('AI_BAD_RESPONSE', 'AI endpoint returned a malformed step.');
    }
    parsed.push({
      title: (s as { title: string }).title,
      detail: (s as { detail: string }).detail,
    });
  }
  return parsed;
}

export const runAi = action({
  args: {
    userId: v.id('users'),
    prompt: v.string(),
    idempotencyKey: v.string(),
  },
  // Explicit return type: breaks the circular inference between this
  // action and the generated `api` (which includes this module), so
  // `runAi` and every ctx.runQuery/runMutation result infer properly.
  handler: async (
    ctx,
    args,
  ): Promise<{
    runId: Id<'aiRuns'>;
    shareId: string;
    steps: AiStep[];
    stubbed: boolean;
  }> => {
    const prompt = args.prompt.trim();
    if (prompt.length === 0) {
      fail('BAD_INPUT', 'Prompt must not be empty.');
    }
    if (prompt.length > MAX_PROMPT_CHARS) {
      fail(
        'BAD_INPUT',
        `Prompt must be at most ${MAX_PROMPT_CHARS} characters.`,
      );
    }
    if (args.idempotencyKey.length === 0) {
      fail('BAD_INPUT', 'idempotencyKey must not be empty.');
    }

    // Idempotency: a double-tap or retry returns the first run.
    const existing = await ctx.runQuery(
      api.aiRuns.findByIdempotencyKey,
      { idempotencyKey: args.idempotencyKey },
    );
    if (existing) {
      const share = await ctx.runQuery(api.shares.getShareByRun, {
        runId: existing._id,
      });
      if (!share) {
        fail('AI_STATE', 'Run exists but its share is missing.');
      }
      return {
        runId: existing._id,
        shareId: share.shareId,
        steps: existing.steps,
        stubbed: existing.stubbed,
      };
    }

    const supabaseUrl = process.env.SUPABASE_URL;
    const supabaseAnonKey = process.env.SUPABASE_ANON_KEY;

    let steps: AiStep[];
    let stubbed = false;

    if (!supabaseUrl) {
      // STUB MODE — no AI endpoint configured yet. Same path, canned
      // answer, still persisted and counted below.
      steps = STUB_STEPS;
      stubbed = true;
    } else {
      if (!supabaseAnonKey) {
        fail(
          'CONFIG_MISSING',
          'SUPABASE_URL is set but SUPABASE_ANON_KEY is missing in the Convex dashboard (Settings → Environment Variables).',
        );
      }
      let res: Awaited<ReturnType<typeof fetch>>;
      try {
        res = await fetch(`${supabaseUrl}/functions/v1/ai`, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            Authorization: `Bearer ${supabaseAnonKey}`,
          },
          body: JSON.stringify({
            prompt,
            max_tokens: MAX_TOKENS,
            response_format: { type: 'json_object' },
          }),
          signal: AbortSignal.timeout(UPSTREAM_TIMEOUT_MS),
        });
      } catch (err) {
        const message =
          err instanceof Error ? err.message : 'Upstream request failed.';
        fail('AI_UPSTREAM', `AI endpoint unreachable: ${message}`);
      }
      if (!res.ok) {
        // 429 from the endpoint means over-limit: fail, never bill.
        fail(
          'AI_UPSTREAM',
          `AI endpoint returned HTTP ${res.status}.`,
        );
      }
      const payload: unknown = await res.json();
      steps = parseSteps(payload);
      stubbed = false;
    }

    // Persist BEFORE returning: the phone subscribes via useQuery, and
    // a result that lives only in phone memory is an empty screen
    // after kill-and-reopen.
    const runId = await ctx.runMutation(internal.aiRuns.recordRun, {
      userId: args.userId,
      prompt,
      steps,
      stubbed,
      idempotencyKey: args.idempotencyKey,
    });

    const shareId = crypto.randomUUID();
    await ctx.runMutation(internal.shares.createShare, {
      shareId,
      runId,
      userId: args.userId,
    });

    return { runId, shareId, steps, stubbed };
  },
});
